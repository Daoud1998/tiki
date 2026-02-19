import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/product_card.dart';
import '../../product/state/products_providers.dart';

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
    final cs = Theme.of(context).colorScheme;

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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _t(context,
                      ar: 'لا توجد منتجات منشورة لهذا البائع',
                      fr: 'Aucun produit publié pour ce vendeur',
                      en: 'No published products for this seller'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface.withAlpha(180)),
                ),
              ),
            );
          }
          return ListView.separated(
            key: PageStorageKey('seller_products_$sellerId'),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: items.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _t(context,
                        ar: 'عدد الإعلانات: ${items.length}',
                        fr: 'Annonces: ${items.length}',
                        en: 'Listings: ${items.length}'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withAlpha(200),
                    ),
                  ),
                );
              }
              final p = items[i - 1];
              return ProductCard(
                product: p,
                onTap: () => context.push('/product/${p.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
