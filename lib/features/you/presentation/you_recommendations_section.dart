import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state/likes_controller.dart';
import '../../../core/state/recently_viewed_controller.dart';
import '../../../core/widgets/product_card.dart';
import '../../product/domain/app_product.dart';
import '../../product/state/products_providers.dart';


/// "قد تعجبك" section for You page.
///
/// - Uses local mock data (offline MVP).
/// - Seeds recommendations from Recently Viewed first, then Likes.
/// - Ranks by same wilaya, then same moughataa, then price closeness, then newest.
/// - Excludes items already in likes/recent to avoid repetition.
class YouRecommendationsSection extends ConsumerWidget {
  const YouRecommendationsSection({
    super.key,
    this.maxItems = 8,
  });

  final int maxItems;

@override
Widget build(BuildContext context, WidgetRef ref) {
  final recentIds = ref.watch(recentlyViewedProvider);
  final likedIds = ref.watch(likesProvider);

  final all = ref.watch(productsFeedProvider).asData?.value ?? const <AppProduct>[];
  if (all.isEmpty) return const SizedBox.shrink();

  // Build seed list: recently viewed first, then likes.
  final seedIds = <String>[
    ...recentIds,
    ...likedIds.where((id) => !recentIds.contains(id)),
  ];

  // Pick the first seed product to guide ranking (wilaya/moughataa/price).
  final byId = <String, AppProduct>{for (final p in all) p.id: p};
  final seed = seedIds.isEmpty ? null : byId[seedIds.first];

  // Exclude already seen/liked items.
  final excluded = <String>{...recentIds, ...likedIds};

  final candidates = all.where((p) => !excluded.contains(p.id)).toList();
  if (candidates.isEmpty) return const SizedBox.shrink();

  // Ranking heuristic.
  if (seed != null) {
    candidates.sort((a, b) {
      final aSameWilaya = a.wilaya == seed.wilaya;
      final bSameWilaya = b.wilaya == seed.wilaya;
      final c1 = (bSameWilaya ? 1 : 0) - (aSameWilaya ? 1 : 0);
      if (c1 != 0) return c1;

      final aSameMoughataa = a.moughataa == seed.moughataa;
      final bSameMoughataa = b.moughataa == seed.moughataa;
      final c2 = (bSameMoughataa ? 1 : 0) - (aSameMoughataa ? 1 : 0);
      if (c2 != 0) return c2;

      final diffA = (a.price - seed.price).abs();
      final diffB = (b.price - seed.price).abs();
      final c3 = diffA - diffB;
      if (c3 != 0) return c3;

      return b.publishedAt.compareTo(a.publishedAt);
    });
  } else {
    candidates.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  }

  final items = candidates.take(maxItems).toList();
  if (items.isEmpty) return const SizedBox.shrink();

  final title = _tr(
    context,
    ar: 'قد تعجبك',
    fr: 'Recommandés pour vous',
    en: 'You may like',
  );

  final seeMore = _tr(
    context,
    ar: 'عرض المزيد',
    fr: 'Voir plus',
    en: 'See more',
  );

  // Build a "See more" route that feels relevant.
  final wilaya = seed?.wilaya;
  final moughataa = seed?.moughataa;

  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                final q = <String, String>{};
                if (wilaya != null && wilaya.isNotEmpty) q['wilaya'] = wilaya;
                if (moughataa != null && moughataa.isNotEmpty) {
                  q['moughataa'] = moughataa;
                }

                final uri = Uri(
                    path: '/search', queryParameters: q.isEmpty ? null : q);
                context.push(uri.toString());
              },
              child: Text(seeMore),
            )
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 270,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = items[i];
              return SizedBox(
                width: 172,
                child: ProductCard(
                  product: p,
                  variant: ProductCardVariant.trending,
                  showMeta: false,
                  onTap: () => context.push('/product/${p.id}'),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

  static String _tr(
    BuildContext c, {
    required String ar,
    required String fr,
    required String en,
  }) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }
}