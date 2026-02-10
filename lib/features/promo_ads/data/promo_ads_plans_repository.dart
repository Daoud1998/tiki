import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class PromoAdsDuration {
  const PromoAdsDuration({required this.days, required this.priceMru});
  final int days;
  final int priceMru;
}

@immutable
class PromoAdsVipPlan {
  const PromoAdsVipPlan({
    required this.active,
    required this.countryWideMultiplier,
    this.multiWilayaExtraPercent = 0.20,
    this.multiWilayaMaxMultiplier = 2.0,
    required this.durations,
  });

  final bool active;
  final int countryWideMultiplier;

  /// Extra percent (fraction) added per extra wilaya beyond the first.
  /// Example: 0.20 => +20%.
  ///
  /// Admin-configurable in: promo_ads_plans/vip.multiWilayaExtraPercent
  /// (also accepts percent values like 20).
  final double multiWilayaExtraPercent;

  /// Cap multiplier for multi-wilaya pricing.
  /// The effective cap is also limited by [countryWideMultiplier].
  ///
  /// Admin-configurable in: promo_ads_plans/vip.multiWilayaMaxMultiplier
  final double multiWilayaMaxMultiplier;
  final List<PromoAdsDuration> durations;
}

class PromoAdsPlansRepository {
  PromoAdsPlansRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _vipDoc =>
      _db.collection('promo_ads_plans').doc('vip');

  Stream<PromoAdsVipPlan?> watchVipPlan() {
    return _vipDoc.snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;

      final active = _asBool(data['active'], fallback: true);
      final mult = _asInt(data['countryWideMultiplier'], fallback: 1);

      // Admin-configurable multi-wilaya pricing.
      // Accepts either fraction (0.2) or percent (20).
      final extraPct = _asFraction(
        data['multiWilayaExtraPercent'] ?? data['multiWilayaExtraPct'],
        fallback: 0.20,
      );
      final capMult = _asDouble(
        data['multiWilayaMaxMultiplier'] ?? data['multiWilayaCapMultiplier'],
        fallback: (mult <= 0 ? 1.0 : mult.toDouble()),
      );

      final durations = <PromoAdsDuration>[];
      final raw = data['durations'];
      if (raw is List) {
        for (final v in raw) {
          if (v is! Map) continue;
          final days = _asInt(v['days'], fallback: 0);
          final price = _asInt(v['priceMru'], fallback: 0);
          if (days <= 0 || price <= 0) continue;
          durations.add(PromoAdsDuration(days: days, priceMru: price));
        }
      }
      durations.sort((a, b) => a.days.compareTo(b.days));

      return PromoAdsVipPlan(
        active: active,
        countryWideMultiplier: mult <= 0 ? 1 : mult,
        multiWilayaExtraPercent: extraPct < 0 ? 0.0 : extraPct,
        multiWilayaMaxMultiplier: capMult <= 0 ? 1.0 : capMult,
        durations: durations,
      );
    });
  }

  static bool _asBool(Object? v, {required bool fallback}) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return fallback;
  }

  static int _asInt(Object? v, {required int fallback}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? fallback;
  }

  static double _asDouble(Object? v, {required double fallback}) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString()) ?? fallback;
  }

  /// Accepts fraction (0.2) or percent (20).
  static double _asFraction(Object? v, {required double fallback}) {
    final d = _asDouble(v, fallback: fallback);
    if (d > 1.5) return d / 100.0;
    return d;
  }
}
