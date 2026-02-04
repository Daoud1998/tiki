import 'package:flutter/foundation.dart';

/// Conservative pricing configuration for VIP / promo boosts.
/// Currency: MRU.
///
/// Strategy:
/// - Price is based on a percentage of the product price
/// - Multiplied by a duration factor (with bundle discounts)
/// - Clamped by tier-specific min/max
/// - Rounded to a friendly step (default: 5 MRU)
///
/// Notes:
/// - For products with missing/zero price, we fall back to a category-based
///   reference price to keep pricing predictable.
@immutable
class VipPricingConfig {
  const VipPricingConfig._();

  /// Maximum allowed duration for VIP pricing (days).
  static const int maxDays = 60;

  /// Rounds final amount to a multiple of this value.
  static const int roundStepMru = 5;

  /// Duration multipliers (bundle discounts).
  /// Custom durations are linearly interpolated between nearest keys.
  static const Map<int, double> durationMultipliers = {
    1: 0.20,
    3: 0.50,
    7: 1.00,
    15: 1.60,
    30: 2.80,
    60: 4.80,
  };

  /// Percent of product price used for each VIP tier (conservative).
  static const double boostPct = 0.004; // 0.4%
  static const double featuredPct = 0.007; // 0.7%
  static const double topPct = 0.011; // 1.1%

  /// Min/max clamps per tier (MRU).
  static const int boostMin = 15;
  static const int boostMax = 450;

  static const int featuredMin = 30;
  static const int featuredMax = 900;

  static const int topMin = 60;
  static const int topMax = 1500;

  /// Reference prices used when product price is missing/0.
  /// Category IDs are based on `ma_catalog.dart`.
  static const int fallbackVehiclesMru = 80000; // cars, suv4x4, trucks...
  static const int fallbackRealEstateMru = 120000; // land/house/apartment/rent
  static const int fallbackElectronicsMru = 10000; // phones/computers...
  static const int fallbackDefaultMru = 5000;

  /// Vehicle-related categories/subcategories.
  static const Set<String> vehicleIds = {
    'vehicles',
    'cars',
    'suv4x4',
    'trucks',
    'motorcycles',
    'bicycles',
    'parts',
  };

  /// Real-estate categories/subcategories.
  static const Set<String> realEstateIds = {
    'real_estate',
    'land',
    'house',
    'apartment',
    'rent',
    'shops',
  };

  /// Electronics categories/subcategories.
  static const Set<String> electronicsIds = {
    'electronics',
    'phones',
    'computers',
    'tablets',
    'tv_audio',
    'gaming',
    'cameras',
    'wearables',
    'smart_home',
    'printers',
  };
}

enum VipTier {
  boost,
  featured,
  top,
}
