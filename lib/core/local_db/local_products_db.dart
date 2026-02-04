import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/product/domain/app_product.dart';

/// Local (SQLite) cache of Firestore products for super-fast search.
///
/// Works on Android/iOS. If you build for web, use the Firestore search fallback.
class LocalProductsDb {
  LocalProductsDb._(this._db);

  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  static const _dbName = 'tiki_products_cache_v1.db';
  static const _table = 'products_cache';

  static Future<LocalProductsDb> open() async {
    final base = await getDatabasesPath();
    final path = p.join(base, _dbName);

    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
CREATE TABLE $_table (
  id TEXT PRIMARY KEY,
  status TEXT,
  category TEXT,
  phoneTail8 TEXT,
  publishedAtMs INTEGER,
  searchText TEXT,
  dataJson TEXT NOT NULL
);
''');
        await db.execute('CREATE INDEX idx_products_status ON $_table(status);');
        await db.execute('CREATE INDEX idx_products_category ON $_table(category);');
        await db.execute('CREATE INDEX idx_products_phoneTail8 ON $_table(phoneTail8);');
        await db.execute('CREATE INDEX idx_products_publishedAt ON $_table(publishedAtMs);');
      },
    );

    return LocalProductsDb._(db);
  }

  Future<void> close() async {
    await _changes.close();
    await _db.close();
  }

  // ---------------- Normalization helpers ----------------

  static String _stripDiacritics(String s) {
    // Arabic harakat + tatweel
    return s.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
  }

  static String normalizeSearchText(String input) {
    var s = input.toLowerCase();

    // Arabic normalization
    s = s
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه');

    // French/Latin diacritics (basic)
    s = s
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');

    s = _stripDiacritics(s);

    // Keep letters/digits/spaces only
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _digitsOnly(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  static String _tail8(String digits) =>
      digits.length <= 8 ? digits : digits.substring(digits.length - 8);

  // ---------------- JSON conversion ----------------

  static dynamic _toJsonValue(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is GeoPoint) return {'lat': v.latitude, 'lng': v.longitude};
    if (v is DocumentReference) return v.path;
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _toJsonValue(val)));
    }
    if (v is List) return v.map(_toJsonValue).toList(growable: false);
    return v;
  }

  static Map<String, dynamic> _docToJsonMap(Map<String, dynamic> data) {
    return data.map((k, v) => MapEntry(k, _toJsonValue(v)));
  }

  static int _publishedAtMs(Map<String, dynamic> d) {
    final v = d['publishedAt'] ?? d['createdAt'] ?? d['created_at'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
    return 0;
  }

  static String _buildSearchText(Map<String, dynamic> d) {
    final parts = <String>[
      (d['title'] ?? '').toString(),
      (d['subtitle'] ?? '').toString(),
      (d['description'] ?? '').toString(),
      (d['details'] ?? '').toString(),
      (d['category'] ?? '').toString(),
      (d['subCategory'] ?? '').toString(),
      (d['sellerName'] ?? '').toString(),
      (d['wilaya'] ?? '').toString(),
      (d['moughataa'] ?? '').toString(),
      (d['neighborhood'] ?? '').toString(),
      (d['brand'] ?? '').toString(),
      (d['model'] ?? '').toString(),
      (d['year'] ?? '').toString(),
      (d['phone'] ?? '').toString(),
      // attrs IDs help if you search by wilaya ID etc.
      ((d['attrs'] is Map) ? (d['attrs'] as Map)['wilaya_id']?.toString() ?? '' : ''),
      ((d['attrs'] is Map) ? (d['attrs'] as Map)['moughataa_id']?.toString() ?? '' : ''),
    ];
    return normalizeSearchText(parts.where((e) => e.trim().isNotEmpty).join(' '));
  }

  // ---------------- Sync from Firestore ----------------

  Future<void> applySnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    if (kIsWeb) return;

    final changes = snap.docChanges;
    if (changes.isEmpty) return;

    await _db.transaction((txn) async {
      for (final ch in changes) {
        final id = ch.doc.id;
        if (ch.type == DocumentChangeType.removed) {
          await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
          continue;
        }

        final raw = ch.doc.data() ?? <String, dynamic>{};
        final d = Map<String, dynamic>.from(raw);
        d['id'] = (d['id'] ?? id).toString();

        final status = (d['status'] ?? 'active').toString();
        final category = (d['category'] ?? '').toString();
        final phoneDigits = _digitsOnly((d['phone'] ?? '').toString());
        final phoneTail8 = phoneDigits.isEmpty ? null : _tail8(phoneDigits);

        final pubMs = _publishedAtMs(d);
        final searchText = _buildSearchText(d);
        final jsonMap = _docToJsonMap(d);
        final dataJson = jsonEncode(jsonMap);

        await txn.insert(
          _table,
          {
            'id': id,
            'status': status,
            'category': category.isEmpty ? null : category,
            'phoneTail8': phoneTail8,
            'publishedAtMs': pubMs,
            'searchText': searchText,
            'dataJson': dataJson,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    _changes.add(null);
  }

  // ---------------- Search ----------------

  Stream<List<AppProduct>> watchSearchContains(
    String query, {
    String? categoryId,
    int limit = 80,
  }) {
    final controller = StreamController<List<AppProduct>>();
    Future<void> emit() async {
      try {
        final items = await searchContains(
          query,
          categoryId: categoryId,
          limit: limit,
        );
        if (!controller.isClosed) controller.add(items);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    // initial
    emit();

    final sub = changes.listen((_) => emit());
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  Future<List<AppProduct>> searchContains(
    String query, {
    String? categoryId,
    int limit = 80,
  }) async {
    final qRaw = query.trim();
    final where = <String>[];
    final args = <Object?>[];

    // Always only show active products for search UX
    where.add("(status IS NULL OR status = 'active')");
    final cat = (categoryId ?? '').trim();
    if (cat.isNotEmpty) {
      where.add('category = ?');
      args.add(cat);
    }

    final digits = _digitsOnly(qRaw);
    final looksPhone = digits.length >= 8;
    if (looksPhone) {
      where.add('phoneTail8 = ?');
      args.add(_tail8(digits));
    } else if (qRaw.isNotEmpty) {
      final norm = normalizeSearchText(qRaw);
      if (norm.isNotEmpty) {
        final parts = norm.split(' ').where((p) => p.trim().isNotEmpty).toList();
        // "contains anywhere": each part must be contained.
        for (final p0 in parts) {
          where.add('searchText LIKE ?');
          args.add('%$p0%');
        }
      }
    }

    final sql = '''
SELECT dataJson
FROM $_table
${where.isEmpty ? '' : 'WHERE ' + where.join(' AND ')}
ORDER BY publishedAtMs DESC
LIMIT ?
''';
    args.add(limit);

    final rows = await _db.rawQuery(sql, args);

    final items = <AppProduct>[];
    for (final r in rows) {
      final jsonStr = (r['dataJson'] ?? '').toString();
      if (jsonStr.isEmpty) continue;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      items.add(AppProduct.fromMap(map));
    }
    return items;
  }
}
