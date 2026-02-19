import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/local_store.dart';
import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/search_lang_bar.dart';
import '../../product/domain/app_product.dart';
import '../../product/state/products_providers.dart';

/// Most viewed products (device-local view counts).
///
/// Uses Firestore feed for products (no mock data).
class MostViewedScreen extends ConsumerWidget {
  const MostViewedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final store = ref.watch(localStoreProvider);

    int viewsOf(AppProduct p) => store.getProductViewCount(p.id);

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
                    ar: 'حدث خطأ في تحميل المنتجات',
                    fr: 'Erreur de chargement',
                    en: 'Failed to load products'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withAlpha((0.75 * 255).round()),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (items) {
            final all = List<AppProduct>.from(items)
              ..sort((a, b) => viewsOf(b).compareTo(viewsOf(a)));

            final nonZero = all.where((p) => viewsOf(p) > 0).toList(growable: false);
            final list = (nonZero.isEmpty ? all : nonZero);

            final top = list.take(12).toList(growable: false);
            final gridRatio = _gridRatio(context);

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
                          child: TkiiSearchLangBar(
                            hint: _tr(context,
                                ar: 'ابحث داخل الأكثر مشاهدة',
                                fr: 'Rechercher dans les plus vus',
                                en: 'Search most viewed'),
                            onSearchTap: () => context.go('/search'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (list.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _tr(context,
                              ar: 'لا توجد مشاهدات بعد',
                              fr: 'Aucune vue pour le moment',
                              en: 'No views yet'),
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
                      child: Text(
                        _tr(context,
                            ar: 'الأكثر مشاهدة', fr: 'Les plus vus', en: 'Most viewed'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 292,
                      child: ListView.separated(
                        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 0),
                        scrollDirection: Axis.horizontal,
                        itemCount: top.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final p = top[i];
                          final v = viewsOf(p);
                          return SizedBox(
                            width: 240,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ProductCard(
                                    product: p,
                                    variant: ProductCardVariant.trending,
                                    onTap: () => context.push('/product/${p.id}'),
                                  ),
                                ),
                                PositionedDirectional(
                                  top: 10,
                                  start: 10,
                                  child: _ViewBadge(views: v),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
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
                          final p = list[i];
                          final v = viewsOf(p);
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: ProductCard(
                                  product: p,
                                  variant: ProductCardVariant.grid,
                                  compact: true,
                                  showMeta: false,
                                  onTap: () => context.push('/product/${p.id}'),
                                ),
                              ),
                              PositionedDirectional(
                                top: 10,
                                start: 10,
                                child: _ViewBadge(views: v),
                              ),
                            ],
                          );
                        },
                        childCount: list.length,
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

class _ViewBadge extends StatelessWidget {
  const _ViewBadge({required this.views});

  final int views;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.remove_red_eye_outlined, size: 16),
          const SizedBox(width: 6),
          Text(
            views.toString(),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
