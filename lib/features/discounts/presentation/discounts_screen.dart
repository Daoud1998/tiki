import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/search_lang_bar.dart';
import '../../product/domain/app_product.dart';
import '../../product/state/products_providers.dart';

/// Discounts page.
/// - Shows discounted products only (oldPrice > price)
/// - Uses Firestore feed (no mock data)
class DiscountsScreen extends ConsumerWidget {
  const DiscountsScreen({super.key});

  bool _isDeal(AppProduct p) {
    final oldP = p.oldPrice;
    if (oldP == null) return false;
    if (p.price <= 0) return false;
    return oldP > p.price;
  }

  double _dealPct(AppProduct p) {
    final oldP = (p.oldPrice ?? 0).toDouble();
    if (oldP <= 0) return 0.0;
    final newP = p.price.toDouble();
    return ((oldP - newP) / oldP).clamp(0.0, 0.95);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final gridRatio = _gridRatio(context);

    final feed = ref.watch(productsFeedProvider);

    return Scaffold(
      body: SafeArea(
        child: feed.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _tr(context,
                    ar: 'حدث خطأ في تحميل التخفيضات',
                    fr: 'Erreur de chargement',
                    en: 'Failed to load discounts'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withAlpha((0.75 * 255).round()),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (items) {
            final deals = items.where(_isDeal).toList(growable: false)
              ..sort((a, b) => _dealPct(b).compareTo(_dealPct(a)));

            final trending = deals.take(12).toList(growable: false);

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 14, 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: _tr(context, ar: 'رجوع', fr: 'Retour', en: 'Back'),
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () {
                            final nav = Navigator.of(context);
                            if (nav.canPop()) {
                              nav.pop();
                            } else {
                              context.go('/home');
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TikkiSearchLangBar(
                            hint: _tr(context,
                                ar: 'ابحث داخل التخفيضات',
                                fr: 'Rechercher dans les promos',
                                en: 'Search discounts'),
                            onSearchTap: () => context.go('/search?deals=1'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (deals.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _tr(context,
                              ar: 'لا توجد تخفيضات حالياً',
                              fr: 'Aucune promo pour le moment',
                              en: 'No discounts right now'),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface.withAlpha((0.75 * 255).round()),
                          ),
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 14, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _tr(context,
                                  ar: 'رائج التخفيضات',
                                  fr: 'Promos populaires',
                                  en: 'Trending deals'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.push('/search?deals=1'),
                            child: Text(_tr(context, ar: 'بحث', fr: 'Rechercher', en: 'Search')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 292,
                      child: ListView.separated(
                        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 0),
                        scrollDirection: Axis.horizontal,
                        itemCount: trending.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final p = trending[i];
                          return SizedBox(
                            width: 240,
                            child: ProductCard(
                              product: p,
                              variant: ProductCardVariant.trending,
                              onTap: () => context.push('/product/${p.id}'),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 10),
                      child: Text(
                        _tr(context, ar: 'كل التخفيضات', fr: 'Toutes les promos', en: 'All discounts'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 14),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: gridRatio,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final p = deals[i];
                          return ProductCard(
                            product: p,
                            variant: ProductCardVariant.grid,
                            compact: true,
                            showMeta: false,
                            onTap: () => context.push('/product/${p.id}'),
                          );
                        },
                        childCount: deals.length,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  double _gridRatio(BuildContext context) {
    final t = MediaQuery.textScaleFactorOf(context).clamp(1.0, 1.3);
    final ratio = 0.60 / t;
    return ratio.clamp(0.50, 0.60);
  }

  String _tr(BuildContext c, {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }
}
