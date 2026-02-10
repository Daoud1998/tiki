import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/promo_ads_plans_repository.dart';

final promoAdsPlansRepositoryProvider = Provider<PromoAdsPlansRepository>((ref) {
  return PromoAdsPlansRepository(FirebaseFirestore.instance);
});

final promoAdsVipPlanProvider =
    StreamProvider.autoDispose<PromoAdsVipPlan?>((ref) {
  return ref.watch(promoAdsPlansRepositoryProvider).watchVipPlan();
});
