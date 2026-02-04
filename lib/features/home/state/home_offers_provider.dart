import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Home "offers" notes shown in the split banner (Home header).
///
/// Firestore collection: `home_offers`
///
/// Minimal schema (recommended):
/// ```json
/// {
///   "active": true,
///   "priority": 10,
///   "titles": {"ar": "...", "fr": "...", "en": "..."},
///   "updatedAtMs": 1700000000000
/// }
/// ```
///
/// Optional fields:
/// - `route` (String): route to open when user taps the right tile.
/// - `startsAtMs`, `endsAtMs` (int): schedule visibility.
class HomeOfferNote {
  const HomeOfferNote({
    required this.id,
    required this.titles,
    this.priority = 0,
    this.updatedAtMs,
    this.startsAtMs,
    this.endsAtMs,
    this.route,
  });

  final String id;
  final Map<String, String> titles; // {ar, fr, en}
  final int priority;
  final int? updatedAtMs;
  final int? startsAtMs;
  final int? endsAtMs;
  final String? route;

  static int? _asMs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static String _asStr(dynamic v) => (v == null) ? '' : v.toString();

  static Map<String, String> _asLangMap(dynamic v) {
    if (v is Map) {
      final out = <String, String>{};
      for (final e in v.entries) {
        final k = e.key.toString();
        out[k] = _asStr(e.value);
      }
      return out;
    }
    return const <String, String>{};
  }

  factory HomeOfferNote.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    final titles = _asLangMap(m['titles']);
    return HomeOfferNote(
      id: doc.id,
      titles: titles,
      priority: _asInt(m['priority']),
      updatedAtMs: _asMs(m['updatedAtMs']) ?? _asMs(m['createdAtMs']),
      startsAtMs: _asMs(m['startsAtMs']),
      endsAtMs: _asMs(m['endsAtMs']),
      route: _asStr(m['route']).trim().isEmpty ? null : _asStr(m['route']).trim(),
    );
  }

  bool isActiveNow(int nowMs) {
    if (startsAtMs != null && nowMs < startsAtMs!) return false;
    if (endsAtMs != null && nowMs >= endsAtMs!) return false;
    return true;
  }

  Map<String, String> toUiMap() {
    // The Home widget expects {ar, fr, en} keys.
    return <String, String>{
      'ar': titles['ar'] ?? titles['ar-SA'] ?? titles['ar_MA'] ?? '',
      'fr': titles['fr'] ?? titles['fr-FR'] ?? '',
      'en': titles['en'] ?? titles['en-US'] ?? '',
    };
  }
}

final homeOffersNotesProvider = StreamProvider.autoDispose<List<HomeOfferNote>>(
  (ref) {
    final db = FirebaseFirestore.instance;
    // Keep it index-free: equality filter only. Sort on the client.
    final q = db.collection('home_offers').where('active', isEqualTo: true);
    return q.snapshots().map((snap) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final list = snap.docs
          .map(HomeOfferNote.fromDoc)
          .where((e) => e.isActiveNow(nowMs))
          .toList(growable: false);
      // Sort: higher priority first, then newest.
      list.sort((a, b) {
        final p = b.priority.compareTo(a.priority);
        if (p != 0) return p;
        return (b.updatedAtMs ?? 0).compareTo(a.updatedAtMs ?? 0);
      });
      // Avoid huge UI lists.
      return list.take(min(12, list.length)).toList(growable: false);
    });
  },
);
