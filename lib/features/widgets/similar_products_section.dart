import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';


import '../../core/widgets/product_card.dart';
import '../product/domain/app_product.dart';
import '../product/state/products_providers.dart';

class SimilarProductsSection extends ConsumerWidget {
  /// [current] can be AppProduct (Firestore) or any legacy object.
  /// If it's not an AppProduct we simply hide the section (keeps old screens compiling).
  const SimilarProductsSection({
    super.key,
    required this.current,
    this.currentProductId,
  });

  final dynamic current;
  final String? currentProductId; // backward-compat (some screens pass this)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (current is! AppProduct) return const SizedBox.shrink();
    final AppProduct c = current as AppProduct;

    final feed = ref.watch(productsFeedProvider);

    return feed.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (items) {
        // Very lightweight similarity: same category/subCategory/wilaya, exclude self.
        final list = items
            .where((p) {
              if (p.id == c.id) return false;
              if (p?.status != 'active') return false;
              final sameCat = (p.category ?? '') == (c.category ?? '');
              final sameSub = (p.subCategory ?? '') == (c.subCategory ?? '');
              final sameWilaya = p.wilaya == c.wilaya;
              return (sameSub || sameCat) && sameWilaya;
            })
            .take(10)
            .toList(growable: false);

        if (list.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              _tr(
                context,
                ar: 'منتجات مشابهة',
                fr: 'Produits similaires',
                en: 'Similar products',
              ),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            ...list.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ProductCard(
                    product: p,
                    onTap: () {
                      final id = p.id.toString();
                      if (id.isEmpty) return;
                      context.push('/product/$id');
                    },
                  ),
                )),
          ],
        );
      },
    );
  }

  static String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    if (lang.startsWith('ar')) return ar;
    if (lang.startsWith('fr')) return fr;
    return en;
  }
}
