import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// VIP / Promotion + Lightweight Moderation
/// ---------------------------------------------------------------------------
///
/// Storage strategy:
/// - VIP + review info is stored inside a product-like object's `attrs` map.
/// - To keep backward compatibility, we support BOTH key families:
///   - "promo_status" ... (new)
///   - "__promo_status" ... (old/system)
///
/// This file intentionally avoids depending on MockProduct so it can work with
/// both MockProduct and Firestore-backed AppProduct.

class PromoStatus {
  static const String none = '';
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
  static const String needsPrice = 'needs_price';
}

class PromoKeys {
  // New keys
  static const String promoStatus = 'promo_status';
  static const String promoPkgId = 'promo_pkg_id';
  static const String promoTier = 'promo_tier';
  static const String promoTxId = 'promo_tx_id';
  static const String promoWalletId = 'promo_wallet_id';
  static const String promoReqAtMs = 'promo_req_at_ms';
  static const String promoApprAtMs = 'promo_appr_at_ms';
  static const String promoUntilMs = 'promo_until_ms';
  static const String promoDays = 'promo_days';
  static const String promoPriceMru = 'promo_price_mru';
  static const String promoRejectReason = 'promo_reject_reason';

  // Aliases (some screens used old names)
  static const String promoRequestedAtMs = promoReqAtMs;
  static const String promoApprovedAtMs = promoApprAtMs;

  // Legacy / reserved keys
  static const String rPromoStatus = '__promo_status';
  static const String rPromoPkgId = '__promo_pkg_id';
  static const String rPromoTier = '__promo_tier';
  static const String rPromoTxId = '__promo_tx_id';
  static const String rPromoReqAtMs = '__promo_req_at_ms';
  static const String rPromoApprAtMs = '__promo_appr_at_ms';
  static const String rPromoUntilMs = '__promo_until_ms';
  static const String rPromoDays = '__promo_days';
  static const String rPromoPriceMru = '__promo_price_mru';
  static const String rPromoRejectReason = '__promo_reject_reason';

  static bool isReserved(String key) => PromoModeration.isReserved(key);
}

@immutable
class PromoPackage {
  final String id;
  final String labelAr;
  final String labelFr;
  final String labelEn;
  final int days;
  final int priceMru;

  const PromoPackage({
    required this.id,
    required this.labelAr,
    required this.labelFr,
    required this.labelEn,
    required this.days,
    required this.priceMru,
  });

  String labelOf(BuildContext context) =>
      PromoModeration._tr(context, ar: labelAr, fr: labelFr, en: labelEn);

  // Backward-compat alias used by some screens.
  String titleOf(BuildContext context) => labelOf(context);
}

class PromoModeration {
  static const List<PromoPackage> packages = <PromoPackage>[
PromoPackage(
  id: 'boost_1d',
  labelAr: 'تعزيز',
  labelFr: 'Boost',
  labelEn: 'Boost',
  days: 1,
  priceMru: 100,
),
PromoPackage(
  id: 'boost_3d',
  labelAr: 'تعزيز',
  labelFr: 'Boost',
  labelEn: 'Boost',
  days: 3,
  priceMru: 220,
),
PromoPackage(
  id: 'boost_7d',
  labelAr: 'تعزيز',
  labelFr: 'Boost',
  labelEn: 'Boost',
  days: 7,
  priceMru: 390,
),
PromoPackage(
  id: 'boost_15d',
  labelAr: 'تعزيز',
  labelFr: 'Boost',
  labelEn: 'Boost',
  days: 15,
  priceMru: 650,
),
PromoPackage(
  id: 'boost_30d',
  labelAr: 'تعزيز',
  labelFr: 'Boost',
  labelEn: 'Boost',
  days: 30,
  priceMru: 1100,
),
PromoPackage(
  id: 'featured_1d',
  labelAr: 'مميّز',
  labelFr: 'Vedette',
  labelEn: 'Featured',
  days: 1,
  priceMru: 180,
),
PromoPackage(
  id: 'featured_3d',
  labelAr: 'مميّز',
  labelFr: 'Vedette',
  labelEn: 'Featured',
  days: 3,
  priceMru: 420,
),
PromoPackage(
  id: 'featured_7d',
  labelAr: 'مميّز',
  labelFr: 'Vedette',
  labelEn: 'Featured',
  days: 7,
  priceMru: 780,
),
PromoPackage(
  id: 'featured_15d',
  labelAr: 'مميّز',
  labelFr: 'Vedette',
  labelEn: 'Featured',
  days: 15,
  priceMru: 1350,
),
PromoPackage(
  id: 'featured_30d',
  labelAr: 'مميّز',
  labelFr: 'Vedette',
  labelEn: 'Featured',
  days: 30,
  priceMru: 2400,
),
PromoPackage(
  id: 'top_1d',
  labelAr: 'TOP',
  labelFr: 'TOP',
  labelEn: 'TOP',
  days: 1,
  priceMru: 250,
),
PromoPackage(
  id: 'top_3d',
  labelAr: 'TOP',
  labelFr: 'TOP',
  labelEn: 'TOP',
  days: 3,
  priceMru: 600,
),
PromoPackage(
  id: 'top_7d',
  labelAr: 'TOP',
  labelFr: 'TOP',
  labelEn: 'TOP',
  days: 7,
  priceMru: 1150,
),
PromoPackage(
  id: 'top_15d',
  labelAr: 'TOP',
  labelFr: 'TOP',
  labelEn: 'TOP',
  days: 15,
  priceMru: 2000,
),
PromoPackage(
  id: 'top_30d',
  labelAr: 'TOP',
  labelFr: 'TOP',
  labelEn: 'TOP',
  days: 30,
  priceMru: 3600,
),
// Legacy aliases kept for backwards compatibility with older docs/clients.
PromoPackage(
  id: 'boost_7',
  labelAr: 'تعزيز',
  labelFr: 'Boost',
  labelEn: 'Boost',
  days: 7,
  priceMru: 390,
),
PromoPackage(
  id: 'featured_14',
  labelAr: 'مميّز',
  labelFr: 'Vedette',
  labelEn: 'Featured',
  days: 15,
  priceMru: 1350,
),
  ];

  static PromoPackage? packageById(String? id) {
    final x = (id ?? '').trim();
    if (x.isEmpty) return null;
    for (final p in packages) {
      if (p.id == x) return p;
    }
    return null;
  }

  static Map<String, String> _attrs(dynamic p) {
    try {
      final a = (p is Map) ? p['attrs'] : (p as dynamic).attrs;
      if (a is Map) {
        return a.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
      }
    } catch (_) {}
    return const <String, String>{};
  }

  static String _get(Map<String, String> attrs, String key, String legacyKey) {
    final v = (attrs[key] ?? '').trim();
    if (v.isNotEmpty) return v;
    return (attrs[legacyKey] ?? '').trim();
  }

  static bool isReserved(String key) =>
      key.startsWith('__promo_') || key.startsWith('promo_');

  static String reviewStatus(dynamic p) {
    // In this app, "review status" is the promo status.
    return promoStatus(p);
  }

  static String promoStatus(dynamic p) {
    final a = _attrs(p);
    return _get(a, PromoKeys.promoStatus, PromoKeys.rPromoStatus);
  }

  static int _parseInt(String s) => int.tryParse(s) ?? 0;

  static int promoDays(dynamic p) {
    final a = _attrs(p);
    final raw = _get(a, PromoKeys.promoDays, PromoKeys.rPromoDays);
    return _parseInt(raw);
  }

  static int promoPriceMru(dynamic p) {
    final a = _attrs(p);
    final raw = _get(a, PromoKeys.promoPriceMru, PromoKeys.rPromoPriceMru);
    return _parseInt(raw);
  }

  static DateTime? promoUntil(dynamic p) {
    final a = _attrs(p);
    final raw = _get(a, PromoKeys.promoUntilMs, PromoKeys.rPromoUntilMs);
    final ms = _parseInt(raw);
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static bool isVipActive(dynamic p) {
    final st = promoStatus(p);
    if (st != PromoStatus.approved) return false;
    final until = promoUntil(p);
    if (until == null) return true;
    return until.isAfter(DateTime.now());
  }

  static String promoTier(dynamic p) {
    final a = _attrs(p);
    final tier = _get(a, PromoKeys.promoTier, PromoKeys.rPromoTier);
    if (tier.trim().isNotEmpty) return tier.trim();
    final pkgId = _get(a, PromoKeys.promoPkgId, PromoKeys.rPromoPkgId);
    return _inferTierFromPkgId(pkgId) ?? '';
  }

  static String? _inferTierFromPkgId(String pkgId) {
    final x = pkgId.toLowerCase();
    if (x.contains('top')) return 'top';
    if (x.contains('featured')) return 'featured';
    if (x.contains('boost')) return 'boost';
    return null;
  }

  static bool isVipTopActive(dynamic p) =>
      isVipActive(p) && promoTier(p) == 'top';
  static bool isVipFeaturedActive(dynamic p) =>
      isVipActive(p) && promoTier(p) == 'featured';
  static bool isVipBoostActive(dynamic p) =>
      isVipActive(p) && promoTier(p) == 'boost';

  static String promoBadgeText(BuildContext context, dynamic p) {
    if (!isVipActive(p)) return '';
    final t = promoTier(p);
    if (t == 'top') return _tr(context, ar: 'TOP', fr: 'TOP', en: 'TOP');
    if (t == 'featured')
      return _tr(context, ar: 'مميّز', fr: 'Vedette', en: 'Featured');
    if (t == 'boost')
      return _tr(context, ar: 'تعزيز', fr: 'Boost', en: 'Boost');
    return _tr(context, ar: 'VIP', fr: 'VIP', en: 'VIP');
  }

  static String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    if (lang.startsWith('ar')) return ar;
    if (lang.startsWith('fr')) return fr;
    return en;
  }
}
