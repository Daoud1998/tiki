import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiki/features/product/data/products_repository.dart';
import 'package:tiki/features/product/domain/app_product.dart';
export '../data/products_repository.dart' show productsRepositoryProvider;

final productsFeedProvider = StreamProvider<List<AppProduct>>((ref) {
  return ref.watch(productsRepositoryProvider).watchActiveFeed();
});

final sellerProductsProvider =
    StreamProvider.family<List<AppProduct>, String>((ref, sellerId) {
  return ref.watch(productsRepositoryProvider).watchSellerProducts(sellerId);
});

final productByIdProvider =
    StreamProvider.family<AppProduct?, String>((ref, id) {
  return ref.watch(productsRepositoryProvider).watchById(id);
});

final productsSearchProvider =
    StreamProvider.family<List<AppProduct>, String>((ref, query) {
  return ref.watch(productsRepositoryProvider).watchSearch(query);
});
