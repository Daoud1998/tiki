import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiki/core/widgets/product_card.dart';
import 'package:tiki/features/product/state/products_providers.dart';

class SellerProductsScreen extends ConsumerWidget {
  const SellerProductsScreen({
    super.key,
    required this.sellerId,
    this.sellerName,
  });

  final String sellerId;
  final String? sellerName;

  String _t(BuildContext context,
      {required String ar, required String fr, required String en}) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    if (lang.startsWith('ar')) return ar;
    if (lang.startsWith('fr')) return fr;
    return en;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sellerProductsProvider(sellerId));

    return Scaffold(
      appBar: AppBar(
        title: Text(sellerName?.trim().isNotEmpty == true
            ? sellerName!.trim()
            : _t(context,
                ar: 'منتجات البائع',
                fr: 'Produits du vendeur',
                en: 'Seller products')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Text(_t(context,
              ar: 'تعذر تحميل المنتجات',
              fr: 'Impossible de charger',
              en: 'Failed to load')),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(_t(context,
                  ar: 'لا توجد منتجات',
                  fr: 'Aucun produit',
                  en: 'No products')),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) => ProductCard(
              product: items[i],
              onTap: () {
                // Handle product card tap
              },
            ),
          );
        },
      ),
    );
  }
}
