import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/l10n.dart';
import '../../../core/data/ma_catalog.dart';
import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/search_lang_bar.dart';
import '../../product/domain/app_product.dart';
import '../../product/state/products_providers.dart';

/// A Temu-like "Deals" page.
///
/// Deals are products where `oldPrice > price` and `price > 0`.
/// `price == 0` means "حسب الاتفاق" so it is NOT treated as a deal.
class DealsScreen extends ConsumerWidget {
  const DealsScreen({super.key, this.categoryId, this.subCategoryId});

  final String? categoryId;
  final String? subCategoryId;

  String _tr(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    return en;
  }

  bool _isDeal(AppProduct p) {
    final num price = (p.price) as num;
    final num oldPrice = (p.oldPrice ?? 0) as num;
    return price > 0 && oldPrice > price;
  }

  int _colsFor(double w) {
    if (w >= 900) return 5;
    if (w >= 700) return 4;
    if (w >= 520) return 3;
    return 2;
  }

  double _aspectFor(int cols) {
    if (cols <= 2) return 0.95;
    if (cols == 3) return 0.86;
    return 0.78;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final cs = Theme.of(context).colorScheme;

    final cat = (categoryId ?? '').trim();
    final sub = (subCategoryId ?? '').trim();

    final catById = <String, CategoryNode>{
      for (final c in maCategories) c.id: c,
    };

    final titleBase =
        _tr(context, ar: 'التخفيضات', fr: 'Promotions', en: 'Deals');

    String title = titleBase;
    if (cat.isNotEmpty) {
      final label = catById[cat]?.name.of(context) ?? cat;
      title = '$titleBase • $label';
    }

    final feed = ref.watch(productsFeedProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
      ),
      body: Column(
        children: [
          TikkiSearchLangBar(
            hint: s.searchHint,
            onSearchTap: () => context.go('/search?deals=1'),
          ),
          Expanded(
            child: feed.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    _tr(context,
                        ar: 'حدث خطأ في تحميل المنتجات',
                        fr: 'Erreur de chargement',
                        en: 'Failed to load products'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withOpacity(0.75),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (items) {
                final all = List<AppProduct>.from(items)
                  ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

                bool match(AppProduct p) {
                  if (!_isDeal(p)) return false;

                  if (cat.isNotEmpty) {
                    if ((p.category ?? '').trim() != cat) return false;
                  }

                  if (sub.isNotEmpty) {
                    final pid = resolveSubCategoryIdAny(p.subCategory);
                    if (sub == kOtherSubcategoryId) {
                      return isOtherSubcategoryValue(pid);
                    }
                    return (pid ?? '').trim() == sub;
                  }

                  return true;
                }

                final deals = all.where(match).toList(growable: false);

                if (deals.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_offer_outlined,
                              size: 56, color: cs.onSurface.withOpacity(0.55)),
                          const SizedBox(height: 12),
                          Text(
                            _tr(context,
                                ar: 'لا توجد تخفيضات حالياً',
                                fr: 'Aucune promotion pour le moment',
                                en: 'No deals right now'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _tr(context,
                                ar: 'يمكنك تصفح الأحدث أو العودة للرئيسية.',
                                fr: 'Vous pouvez voir les nouveautés ou revenir à l\'accueil.',
                                en: 'You can browse newest or go back home.'),
                            style: TextStyle(
                                color: cs.onSurface.withOpacity(0.70),
                                fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => context.go('/home'),
                            icon: const Icon(Icons.home_rounded),
                            label: Text(_tr(context,
                                ar: 'العودة للرئيسية',
                                fr: 'Accueil',
                                en: 'Home')),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final w = MediaQuery.sizeOf(context).width;
                final cols = _colsFor(w);
                final aspect = _aspectFor(cols);

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: aspect,
                  ),
                  itemCount: deals.length,
                  itemBuilder: (context, i) {
                    final p = deals[i];
                    return ProductCard(
                      product: p,
                      variant: ProductCardVariant.grid,
                      onTap: () => context.push('/product/${p.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
