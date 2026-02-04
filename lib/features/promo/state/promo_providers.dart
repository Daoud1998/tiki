import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/promo_repository.dart';

final promoRepositoryProvider = Provider<PromoRepository>((ref) {
  return PromoRepository(FirebaseFirestore.instance);
});

/// Active promo tiers ordered by rank (Boost -> Featured -> Top).
final promoTiersProvider = StreamProvider.autoDispose<List<PromoTier>>((ref) {
  return ref.watch(promoRepositoryProvider).watchActiveTiers();
});
