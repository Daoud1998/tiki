import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Firebase (Admin config)
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin-configurable "Popular searches" chips.
///
/// Firestore document:
///   collection: admin_config
///   doc: trending_search
///
/// Supported shapes:
/// 1) chips: { ar: ["..."], fr: ["..."], en: ["..."] }
/// 2) chips_ar: ["..."], chips_fr: ["..."], chips_en: ["..."]
///
/// Optional:
/// - enabled: bool (default true)
/// - limit: int (default 12)
final trendingSearchChipsProvider = StreamProvider.family<List<String>, Locale>((ref, locale) {
  // If Firebase isn't ready (or the app is running in mock mode), don't crash.
  if (Firebase.apps.isEmpty) {
    return Stream.value(const <String>[]);
  }

  final lang = locale.languageCode.toLowerCase();
  final doc = FirebaseFirestore.instance
      .collection('admin_config')
      .doc('trending_search');

  return doc.snapshots().map((snap) {
    try {
      final data = snap.data();
      if (data == null) return const <String>[];

      final enabled = data['enabled'];
      if (enabled is bool && enabled == false) return const <String>[];

      final limitRaw = data['limit'];
      final limit = (limitRaw is int && limitRaw > 0) ? limitRaw : 12;

      // Try: chips map {ar/fr/en}
      dynamic raw;
      final chipsMap = data['chips'];
      if (chipsMap is Map) {
        raw = chipsMap[lang] ?? chipsMap[lang.toUpperCase()] ?? chipsMap['default'];
      }

      // Try: chips_ar / chips_fr / chips_en
      raw ??= data['chips_$lang'];
      raw ??= data['chips_${lang.toUpperCase()}'];
      raw ??= data['chips_default'];

      final out = <String>[];
      if (raw is List) {
        for (final v in raw) {
          if (v is! String) continue;
          final s = v.trim();
          if (s.isEmpty) continue;
          if (!out.contains(s)) out.add(s);
          if (out.length >= limit) break;
        }
      }
      return out;
    } catch (_) {
      return const <String>[];
    }
  }).handleError((_) {
    // Do not propagate errors to UI.
  });
});
