import 'package:flutter/foundation.dart';
import 'pricing_config.dart';

@immutable
class VipPriceBreakdown {
  const VipPriceBreakdown({
    required this.tier,
    required this.days,
    required this.inputProductPriceMru,
    required this.usedPriceMru,
    required this.percent,
    required this.durationMultiplier,
    required this.rawAmountMru,
    required this.clampedAmountMru,
    required this.finalAmountMru,
    required this.minMru,
    required this.maxMru,
    required this.usedFallbackPrice,
  });

  final VipTier tier;
  final int days;

  /// Price provided by the product (0 if missing/unknown).
  final int inputProductPriceMru;

  /// Price used for pricing (either product price or fallback).
  final int usedPriceMru;

  /// Tier percent (e.g. 0.007 for 0.7%).
  final double percent;

  /// Duration multiplier (bundle discount curve).
  final double durationMultiplier;

  /// Raw amount before clamps/rounding.
  final int rawAmountMru;

  /// Amount after min/max clamps but before rounding.
  final int clampedAmountMru;

  /// Final amount after rounding.
  final int finalAmountMru;

  final int minMru;
  final int maxMru;

  /// Whether we used a category fallback price.
  final bool usedFallbackPrice;

  Map<String, Object> toJson() => {
        'tier': tier.name,
        'days': days,
        'inputProductPriceMru': inputProductPriceMru,
        'usedPriceMru': usedPriceMru,
        'percent': percent,
        'durationMultiplier': durationMultiplier,
        'rawAmountMru': rawAmountMru,
        'clampedAmountMru': clampedAmountMru,
        'finalAmountMru': finalAmountMru,
        'minMru': minMru,
        'maxMru': maxMru,
        'usedFallbackPrice': usedFallbackPrice,
      };
}

class VipPricingService {
  const VipPricingService();

  /// Computes conservative VIP price (MRU) based on:
  /// - tier percent of product price
  /// - duration multiplier (bundle discounts)
  /// - min/max clamps
  /// - rounding to a friendly step
  VipPriceBreakdown quote({
    required VipTier tier,
    required int days,
    required int productPriceMru,
    String? categoryId,
    String? subcategoryId,
  }) {
    final safeDays = _clampDays(days);

    final used = _resolvePrice(
      productPriceMru: productPriceMru,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
    );

    final pct = _percentFor(tier);
    final mult = _durationMultiplier(safeDays);

    final raw = (used.usedPriceMru * pct * mult).round();

    final clamp = _clampForTier(tier);
    final clamped = raw.clamp(clamp.minMru, clamp.maxMru);

    final rounded = _roundToStep(clamped, VipPricingConfig.roundStepMru);

    return VipPriceBreakdown(
      tier: tier,
      days: safeDays,
      inputProductPriceMru: productPriceMru,
      usedPriceMru: used.usedPriceMru,
      percent: pct,
      durationMultiplier: mult,
      rawAmountMru: raw,
      clampedAmountMru: clamped,
      finalAmountMru: rounded,
      minMru: clamp.minMru,
      maxMru: clamp.maxMru,
      usedFallbackPrice: used.usedFallback,
    );
  }

  int _clampDays(int days) {
    if (days < 1) return 1;
    if (days > VipPricingConfig.maxDays) return VipPricingConfig.maxDays;
    return days;
  }

  _Clamp _clampForTier(VipTier tier) {
    switch (tier) {
      case VipTier.boost:
        return const _Clamp(
            VipPricingConfig.boostMin, VipPricingConfig.boostMax);
      case VipTier.featured:
        return const _Clamp(
            VipPricingConfig.featuredMin, VipPricingConfig.featuredMax);
      case VipTier.top:
        return const _Clamp(VipPricingConfig.topMin, VipPricingConfig.topMax);
    }
  }

  double _percentFor(VipTier tier) {
    switch (tier) {
      case VipTier.boost:
        return VipPricingConfig.boostPct;
      case VipTier.featured:
        return VipPricingConfig.featuredPct;
      case VipTier.top:
        return VipPricingConfig.topPct;
    }
  }

  /// Interpolates between configured duration multipliers.
  double _durationMultiplier(int days) {
    final m = VipPricingConfig.durationMultipliers;
    if (m.containsKey(days)) return m[days]!;
    final keys = m.keys.toList()..sort();
    // Find nearest lower and upper anchors.
    int lower = keys.first;
    int upper = keys.last;
    for (final k in keys) {
      if (k < days) lower = k;
      if (k > days) {
        upper = k;
        break;
      }
    }
    if (days <= keys.first) return m[keys.first]!;
    if (days >= keys.last) return m[keys.last]!;
    final loVal = m[lower]!;
    final hiVal = m[upper]!;
    final t = (days - lower) / (upper - lower);
    return loVal + (hiVal - loVal) * t;
  }

  _ResolvedPrice _resolvePrice({
    required int productPriceMru,
    String? categoryId,
    String? subcategoryId,
  }) {
    if (productPriceMru > 0) {
      return _ResolvedPrice(productPriceMru, false);
    }
    final id1 = (categoryId ?? '').trim();
    final id2 = (subcategoryId ?? '').trim();

    final ids = <String>{};
    if (id1.isNotEmpty) ids.add(id1);
    if (id2.isNotEmpty) ids.add(id2);

    int fallback = VipPricingConfig.fallbackDefaultMru;
    if (ids.any(VipPricingConfig.vehicleIds.contains)) {
      fallback = VipPricingConfig.fallbackVehiclesMru;
    } else if (ids.any(VipPricingConfig.realEstateIds.contains)) {
      fallback = VipPricingConfig.fallbackRealEstateMru;
    } else if (ids.any(VipPricingConfig.electronicsIds.contains)) {
      fallback = VipPricingConfig.fallbackElectronicsMru;
    }
    return _ResolvedPrice(fallback, true);
  }

  int _roundToStep(int value, int step) {
    if (step <= 1) return value;
    // Round to nearest step (ties round up).
    final div = value / step;
    final rounded = (div).round();
    return rounded * step;
  }
}

@immutable
class _Clamp {
  const _Clamp(this.minMru, this.maxMru);
  final int minMru;
  final int maxMru;
}

@immutable
class _ResolvedPrice {
  const _ResolvedPrice(this.usedPriceMru, this.usedFallback);
  final int usedPriceMru;
  final bool usedFallback;
}
