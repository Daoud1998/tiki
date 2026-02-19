import '../monetization/pricing_config.dart';
import '../monetization/pricing_service.dart';

/// Single source of truth for VIP pricing + labels.
///
/// - Products: percentage-based (with category fallback when price is 0).
/// - Ads: fixed packages (handled elsewhere).
class TkiiPricing {
  const TkiiPricing._();

  /// Allowed VIP durations (days).
  static const List<int> vipDays = <int>[1, 3, 7, 15, 30, 60];

  /// Default selections in UI.
  static const VipTier defaultVipTier = VipTier.featured;
  static const int defaultVipDays = 7;

  /// Default fallback price used when product price is missing/0.
  /// (We agreed on 5000 MRU.)
  static const int fallbackProductPriceMru =
      VipPricingConfig.fallbackDefaultMru;

  /// Human label for tiers (localized).
  static String tierLabel({required String langCode, required VipTier tier}) {
    final code = langCode.toLowerCase();
    switch (tier) {
      case VipTier.boost:
        if (code == 'fr') return 'Boost';
        if (code == 'en') return 'Boost';
        return 'تعزيز';
      case VipTier.featured:
        if (code == 'fr') return 'En vedette';
        if (code == 'en') return 'Featured';
        return 'مُميّز';
      case VipTier.top:
        if (code == 'fr') return 'Top';
        if (code == 'en') return 'Top';
        return 'الأعلى';
    }
  }

  /// Quote VIP for a product.
  ///
  /// Important: if productPriceMru is 0, VipPricingService will apply a
  /// category-based fallback (default 5000 MRU).
  static VipPriceBreakdown quoteProductVip({
    required VipTier tier,
    required int days,
    required int productPriceMru,
    String? categoryId,
    String? subcategoryId,
  }) {
    return const VipPricingService().quote(
      tier: tier,
      days: days,
      productPriceMru: productPriceMru,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
    );
  }

  // ---------------------------------------------------------------------------
  // Ads pricing helpers (used by Home promo flow).
  // ---------------------------------------------------------------------------

  static const int countryWideMultiplier = 2;

  static int quoteAdVipFinalMru({
    required int basePriceMru,
    required bool countryWide,
  }) {
    return countryWide ? basePriceMru * countryWideMultiplier : basePriceMru;
  }
}
