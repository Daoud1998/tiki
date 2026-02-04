import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// One promo tier like: Boost / Featured / Top.
@immutable
class PromoTier {
  const PromoTier({
    required this.id,
    required this.tier,
    required this.rank,
    required this.active,
    required this.titles,
    required this.durations,
  });

  /// Document id in Firestore (recommended: boost/featured/top).
  final String id;

  /// Tier key used inside product attrs (recommended: boost/featured/top).
  final String tier;

  /// Higher rank = more priority in sorting.
  final int rank;

  final bool active;

  /// Map of localized titles. Example: {"ar": "تعزيز", "fr": "Boost", "en": "Boost"}
  final Map<String, String> titles;

  /// Available durations and prices.
  final List<PromoDuration> durations;

  String titleFor(String lang) {
    final code = lang.trim().toLowerCase();
    return titles[code] ?? titles['ar'] ?? titles['en'] ?? tier;
  }
}

@immutable
class PromoDuration {
  const PromoDuration({required this.days, required this.priceMru});

  final int days;
  final int priceMru;
}

class PromoRepository {
  PromoRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _plans =>
      _db.collection('promo_plans');

  /// Watches active promo tiers.
  ///
  /// Query pattern (recommended): where(active==true).orderBy(rank).
  Stream<List<PromoTier>> watchActiveTiers() {
    return _plans
        .where('active', isEqualTo: true)
        .orderBy('rank')
        .snapshots()
        .map((qs) => qs.docs.map(_fromDoc).toList(growable: false));
  }

  /// Get all tiers (active + inactive).
  Stream<List<PromoTier>> watchAllTiers() {
    return _plans
        .orderBy('rank')
        .snapshots()
        .map((qs) => qs.docs.map(_fromDoc).toList(growable: false));
  }

  PromoTier _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};

    final tier = (data['tier'] ?? doc.id).toString().trim();
    final rank = _asInt(data['rank'], fallback: 0);
    final active = _asBool(data['active'], fallback: true);

    final titles = <String, String>{};
    final rawTitles = data['titles'];
    if (rawTitles is Map) {
      for (final e in rawTitles.entries) {
        final k = (e.key ?? '').toString().trim().toLowerCase();
        final v = (e.value ?? '').toString().trim();
        if (k.isEmpty || v.isEmpty) continue;
        titles[k] = v;
      }
    }

    final durations = <PromoDuration>[];
    final rawDurations = data['durations'];
    if (rawDurations is List) {
      for (final v in rawDurations) {
        if (v is! Map) continue;
        final days = _asInt(v['days'], fallback: 0);
        final price = _asInt(v['priceMru'], fallback: 0);
        if (days <= 0 || price <= 0) continue;
        durations.add(PromoDuration(days: days, priceMru: price));
      }
    }

    durations.sort((a, b) => a.days.compareTo(b.days));

    return PromoTier(
      id: doc.id,
      tier: tier,
      rank: rank,
      active: active,
      titles: titles,
      durations: durations,
    );
  }

  static int _asInt(Object? v, {required int fallback}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? fallback;
  }

  static bool _asBool(Object? v, {required bool fallback}) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return fallback;
  }
}
