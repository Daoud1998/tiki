import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:tiki/core/search/ma_search_tokens.dart';

/// One-time backfill / migration for older product docs.
///
/// الهدف:
/// - إضافة/تصحيح status = 'active'
/// - إضافة publishedAt (من createdAt إن أمكن)
/// - إضافة title عند غيابه
/// - إضافة searchTokens للبحث
/// - نقل wilaya_id/moughataa_id القديمة إلى attrs.{wilaya_id,moughataa_id}
/// - ضمان viewCount
class ProductsMigrator {
  const ProductsMigrator();

  Future<ProductsMigrationStats> run({
    bool dryRun = false,
    int pageSize = 200,
    bool forceRebuildSearchTokens = false,
    bool forceStatusActive = false,
    bool backfillPhoneTail8 = true,
    bool Function()? isCancelled,
    void Function(ProductsMigrationStats stats)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final fs = FirebaseFirestore.instance;
    Query<Map<String, dynamic>> q = fs
        .collection('products')
        .orderBy(FieldPath.documentId)
        .limit(pageSize);

    DocumentSnapshot<Map<String, dynamic>>? last;
    final stats = ProductsMigrationStats(dryRun: dryRun);

    void tick() {
      if (onProgress != null) onProgress(stats);
    }

    onLog?.call(dryRun ? 'DRY RUN: no writes.' : 'Starting migration…');
    if (forceRebuildSearchTokens) {
      onLog?.call('• Rebuilding searchTokens');
    }
    if (forceStatusActive) {
      onLog?.call('• Forcing status=active (except sold)');
    }
    if (backfillPhoneTail8) {
      onLog?.call('• Backfilling phoneTail8 (last 8 digits)');
    }

    while (true) {
      if (isCancelled != null && isCancelled()) {
        stats.cancelled = true;
        onLog?.call('Stopped.');
        tick();
        return stats;
      }

      final snap = (last == null)
          ? await q.get()
          : await q.startAfterDocument(last!).get();

      if (snap.docs.isEmpty) break;

      for (final doc in snap.docs) {
        if (isCancelled != null && isCancelled()) {
          stats.cancelled = true;
          onLog?.call('Stopped.');
          tick();
          return stats;
        }

        stats.scanned++;
        stats.lastId = doc.id;

        final patch = _computePatch(
          doc.data(),
          forceRebuildSearchTokens: forceRebuildSearchTokens,
          forceStatusActive: forceStatusActive,
          backfillPhoneTail8: backfillPhoneTail8,
        );
        if (patch.isEmpty) {
          stats.skipped++;
          continue;
        }

        if (dryRun) {
          stats.updated++;
        } else {
          try {
            await doc.reference.update(patch);
            stats.updated++;
          } catch (e) {
            stats.failed++;
            stats.lastError = e.toString();
            onLog?.call('FAILED ${doc.id}: ${_firstLine(e.toString())}');
          }
        }

        // UI tick every few items (caller decides).
        if (stats.scanned % 5 == 0) tick();
      }

      last = snap.docs.last;
      tick();
    }

    onLog?.call('Done.');
    tick();
    return stats;
  }
}

class ProductsMigrationStats {
  ProductsMigrationStats({required this.dryRun});

  final bool dryRun;

  int scanned = 0;
  int updated = 0;
  int skipped = 0;
  int failed = 0;

  bool cancelled = false;
  String lastId = '';
  String lastError = '';
}

String _firstLine(String s) => s.split('\n').first;

DateTime? _parseAnyDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is int) {
    // Heuristic: seconds vs millis
    if (v < 1000000000000) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    return DateTime.fromMillisecondsSinceEpoch(v);
  }
  if (v is num) return _parseAnyDate(v.toInt());
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
  return null;
}

bool _looksLikeNoiseValue(String v) {
  final s = v.trim().toLowerCase();
  if (s.isEmpty) return true;
  if (s == 'true' || s == 'false' || s == 'null') return true;
  if (s == '0' || s == '1') return true;
  return false;
}

List<String> _buildSearchFields(Map<String, dynamic> d) {
  String pick(dynamic v) => (v ?? '').toString().trim();
  final out = <String>[
    pick(d['title']),
    pick(d['sellerName']),
    pick(d['wilaya']),
    pick(d['moughataa']),
    pick(d['neighborhood']),
    pick(d['description']),
    pick(d['details']),
    pick(d['category']),
    pick(d['subCategory']),
    pick(d['type']),
    pick(d['brand']),
    pick(d['model']),
    pick(d['year']),
  ];

  final attrsRaw = d['attrs'];
  if (attrsRaw is Map) {
    for (final entry in attrsRaw.entries) {
      final v = pick(entry.value);
      if (_looksLikeNoiseValue(v)) continue;
      out.add(v);
    }
  }

  // Legacy top-level ids sometimes exist.
  final legacyWilayaId = pick(d['wilaya_id']);
  final legacyMoughataaId = pick(d['moughataa_id']);
  if (legacyWilayaId.isNotEmpty) out.add(legacyWilayaId);
  if (legacyMoughataaId.isNotEmpty) out.add(legacyMoughataaId);

  return out.where((e) => e.trim().isNotEmpty).toList(growable: false);
}

Map<String, dynamic> _computePatch(
  Map<String, dynamic> d, {
  required bool forceRebuildSearchTokens,
  required bool forceStatusActive,
  required bool backfillPhoneTail8,
}) {
  final patch = <String, dynamic>{};

  // status
  final rawStatus = (d['status'] ?? '').toString().trim().toLowerCase();
  if (rawStatus.isEmpty) {
    patch['status'] = 'active';
  } else if (rawStatus == 'published') {
    patch['status'] = 'active';
  } else if (forceStatusActive) {
    // Keep explicit "sold" as is.
    if (rawStatus != 'active' && rawStatus != 'sold') {
      patch['status'] = 'active';
    }
  }

  // publishedAt
  if (d['publishedAt'] == null) {
    final dt = _parseAnyDate(
      d['createdAt'] ?? d['created_at'] ?? d['updatedAt'] ?? d['updated_at'],
    );
    patch['publishedAt'] =
        dt != null ? Timestamp.fromDate(dt) : FieldValue.serverTimestamp();
  }

  // title (required by AppProduct)
  final title = (d['title'] ?? '').toString().trim();
  if (title.isEmpty) {
    String pick(String key) => (d[key] ?? '').toString().trim();
    final name = pick('name');
    final type = pick('type');
    final brand = pick('brand');
    final model = pick('model');
    final year = pick('year');
    final cat = pick('category');
    final parts = <String>[
      if (name.isNotEmpty) name,
      if (type.isNotEmpty && type != name) type,
      if (brand.isNotEmpty) brand,
      if (model.isNotEmpty) model,
      if (year.isNotEmpty) year,
      if (cat.isNotEmpty) cat,
    ];
    final guess = parts.join(' ').trim();
    if (guess.isNotEmpty) patch['title'] = guess;
  }

  // searchTokens
  final tokensRaw = d['searchTokens'];
  final hasTokens = tokensRaw is List && tokensRaw.isNotEmpty;
  if (!hasTokens || forceRebuildSearchTokens) {
    final fields = _buildSearchFields(d);
    final tokens = maBuildSearchTokens(fields: fields, maxTokens: 90);
    if (tokens.isNotEmpty) patch['searchTokens'] = tokens;
  }

  // Ensure images array for UI consistency
  final imagesRaw = d['images'];
  final hasImages = imagesRaw is List && imagesRaw.isNotEmpty;
  if (!hasImages) {
    final single = (d['imageUrl'] ?? d['image'] ?? '').toString().trim();
    if (single.isNotEmpty) patch['images'] = <String>[single];
  }

  // attrs: move legacy top-level ids into attrs
  final legacyWilayaId = (d['wilaya_id'] ?? '').toString().trim();
  final legacyMoughataaId = (d['moughataa_id'] ?? '').toString().trim();

  if (legacyWilayaId.isNotEmpty || legacyMoughataaId.isNotEmpty) {
    final attrsRaw = d['attrs'];
    final attrs = <String, String>{};
    if (attrsRaw is Map) {
      for (final entry in attrsRaw.entries) {
        attrs[entry.key.toString()] = (entry.value ?? '').toString();
      }
    }

    if (legacyWilayaId.isNotEmpty && (attrs['wilaya_id'] ?? '').trim().isEmpty) {
      attrs['wilaya_id'] = legacyWilayaId;
    }
    if (legacyMoughataaId.isNotEmpty &&
        (attrs['moughataa_id'] ?? '').trim().isEmpty) {
      attrs['moughataa_id'] = legacyMoughataaId;
    }

    if (attrs.isNotEmpty) patch['attrs'] = attrs;
  }


// phoneTail8 (last 8 digits) for phone-number search
if (backfillPhoneTail8) {
  final phone = (d['phone'] ?? '').toString().trim();
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  String? tail8;
  if (digits.length >= 8) {
    tail8 = digits.substring(digits.length - 8);
  }
  final current = (d['phoneTail8'] ?? '').toString().trim();
  if (tail8 != null && tail8.isNotEmpty && tail8 != current) {
    patch['phoneTail8'] = tail8;
  }
}

  // viewCount default
  if (!d.containsKey('viewCount')) {
    patch['viewCount'] = 0;
  }

  return patch;
}
