import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/l10n.dart';
import '../../../core/data/ma_catalog.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/widgets/dir_chevrons.dart';
import '../../../core/widgets/search_lang_bar.dart';
import '../../../core/widgets/product_card.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/mocks/promo_moderation.dart';
import 'package:tiki/features/product/domain/app_product.dart';
import 'package:tiki/features/product/state/products_providers.dart';

/// Safe navigation helper: uses GoRouter and falls back to a SnackBar
/// instead of throwing if the route doesn't exist yet.
void safePush(BuildContext context, String location, {String? fallbackTitle}) {
  try {
    context.push(location);
  } catch (_) {
    if (!context.mounted) return;
    final unavailable = context.tr('common.unavailable_feature');
    final msg = (fallbackTitle == null || fallbackTitle.trim().isEmpty)
        ? unavailable
        : '$fallbackTitle • $unavailable';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  int _selectedMain = -1;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.sizeOf(context).width;

    final auth = ref.watch(authControllerProvider);
    final isGuest = !auth.isSignedIn;

    final store = ref.watch(localStoreProvider);
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    final hot = store.getHotSearchCounts(lang);
    final trendingTerms = (hot.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => e.key)
        .where((e) => e.trim().isNotEmpty)
        .take(8)
        .toList();

    final selectedCategoryId =
        (_selectedMain >= 0 && _selectedMain < maCategories.length)
            ? maCategories[_selectedMain].id
            : null;

    int colsFor(double width) {
      if (width >= 950) return 6;
      if (width >= 760) return 5;
      if (width >= 520) return 4;
      return 3;
    }

    // Smaller ratio => taller tiles => avoids tiny overflows for long Arabic labels.
    double aspectFor(int cols) {
      if (cols >= 6) return 0.88;
      if (cols == 5) return 0.86;
      if (cols == 4) return 0.84;
      return 0.92;
    }

    final cols = colsFor(w);
    final aspect = aspectFor(cols);

    return Scaffold(
        body: SafeArea(
            child: Column(children: [
      TikkiSearchLangBar(
        hint: s.searchHint,
        onSearchTap: () => context.push('/search'),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async {
            // Stage A: local refresh only (no network). Keeps UX familiar.
            await Future.delayed(const Duration(milliseconds: 350));
            if (mounted) setState(() {});
          },
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverToBoxAdapter(child: _TikkiPromoBanner()),
              ),
              if (isGuest)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  sliver: SliverToBoxAdapter(
                    child: _GuestSignupBanner(
                      onTap: () => safePush(context, '/auth',
                          fallbackTitle: context.tr('auth.sign_in_short')),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('categories.title'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('categories.pick_category_then_sub'),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final cat = maCategories[i];
                      final selected = i == _selectedMain;
                      return _MainCatTile(
                        title: cat.name.of(context),
                        icon: _iconForMain(cat.id),
                        accent: _accentForMain(cat.id, cs),
                        selected: selected,
                        onTap: () {
                          setState(() => _selectedMain = i);
                          _showSubPicker(context, cat);
                        },
                      );
                    },
                    childCount: maCategories.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: aspect,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                sliver: SliverToBoxAdapter(
                  child: _TrendingChips(
                    terms: trendingTerms,
                    onQuery: (q) =>
                        safePush(context, '/search?q=$q', fallbackTitle: q),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                sliver: SliverToBoxAdapter(
                  child: _QuickPublishRow(
                    onTapPublish: (route, title) =>
                        safePush(context, route, fallbackTitle: title),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 22),
                sliver: SliverToBoxAdapter(
                  child: _CategoryProductShelves(
                    selectedCategoryId: selectedCategoryId,
                  ),
                ),
              ),
            ],
          ),
        ),
      )
    ])));
  }

  void _showSubPicker(BuildContext context, CategoryNode cat) {
    final cs = Theme.of(context).colorScheme;
    final router = GoRouter.of(context);
    final subs = cat.sub;
    final w = MediaQuery.sizeOf(context).width;

    int colsFor(double width) {
      if (width >= 950) return 6;
      if (width >= 760) return 5;
      if (width >= 520) return 4;
      return 3;
    }

    double aspectFor(int cols) {
      if (cols >= 6) return 0.84;
      if (cols == 5) return 0.82;
      if (cols == 4) return 0.80;
      return 0.86;
    }

    final cols = colsFor(w);
    final aspect = aspectFor(cols);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Consumer(builder: (context, ref, _) {
          final products = ref.watch(productsFeedProvider).asData?.value ?? const <AppProduct>[];

        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: ctx.tr('common.close'),
                    ),
                    Expanded(
                      child: Text(
                        cat.name.of(ctx),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  ctx.tr('categories.choose_subcategory'),
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.70)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: aspect,
                    ),
                    itemCount: subs.length,
                    itemBuilder: (context, i) {
                      final sub = subs[i];
                      final thumb = _thumbFor(products, cat.id, sub.id);
                      return _SubTile(
                        title: sub.name.of(ctx),
                        imageUrl: thumb,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          final url = '/search?cat=${cat.id}&sub=${sub.id}';
                          Future.microtask(() => router.push(url));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
        });
      },
    );
  }

  String? _thumbFor(Iterable<AppProduct> products, String catId, String subId) {
    for (final p in products) {
      if ((p.category ?? '').trim() != catId) continue;
      final pid = resolveSubCategoryIdAny(p.subCategory);
      final match = (subId == kOtherSubcategoryId)
          ? isOtherSubcategoryValue(pid)
          : ((pid ?? '').trim() == subId);
      if (!match) continue;
      final imgs = p.images;
      if (imgs.isNotEmpty) return imgs.first;
    }
    return null;
  }
}

// -----------------------------------------------------------------------------
// Promo banner (top carousel)
// -----------------------------------------------------------------------------

class _PromoSlide {
  const _PromoSlide(
      {required this.icon,
      required this.ar,
      required this.fr,
      required this.en,
      required this.route});

  final IconData icon;
  final String ar;
  final String fr;
  final String en;
  final String route;
}

const List<_PromoSlide> _promoSlides = <_PromoSlide>[
  _PromoSlide(
    icon: Icons.local_fire_department_outlined,
    ar: 'عروض اليوم',
    fr: "Offres du jour",
    en: 'Today\'s deals',
    route: '/discounts',
  ),
  _PromoSlide(
    icon: Icons.workspace_premium_outlined,
    ar: 'عروض VIP',
    fr: 'Offres VIP',
    en: 'VIP deals',
    route: '/home',
  ),
  _PromoSlide(
    icon: Icons.trending_up_outlined,
    ar: 'الأكثر مشاهدة',
    fr: 'Les plus vus',
    en: 'Most viewed',
    route: '/most-viewed',
  ),
  _PromoSlide(
    icon: Icons.add_circle_outline,
    ar: 'أضف إعلانك هنا',
    fr: 'Publier une annonce',
    en: 'Publish your ad',
    route: '/publish',
  ),
];

class _TikkiPromoBanner extends StatefulWidget {
  const _TikkiPromoBanner();

  @override
  State<_TikkiPromoBanner> createState() => _TikkiPromoBannerState();
}

class _TikkiPromoBannerState extends State<_TikkiPromoBanner> {
  late final PageController _ctl;
  Timer? _timer;
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _ctl = PageController();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _promoSlides.isEmpty) return;
      final next = (_idx + 1) % _promoSlides.length;
      _idx = next;
      _ctl.animateToPage(next,
          duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
        color: cs.surface,
      ),
      clipBehavior: Clip.antiAlias,
      child: PageView.builder(
        controller: _ctl,
        itemCount: _promoSlides.length,
        itemBuilder: (context, i) {
          final s = _promoSlides[i];
          final title = L10n3(ar: s.ar, fr: s.fr, en: s.en).of(context);
          return InkWell(
            onTap: () => safePush(context, s.route, fallbackTitle: title),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(s.icon, size: 20, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Category tiles + helpers
// -----------------------------------------------------------------------------

IconData _iconForMain(String id) {
  switch (id) {
    case 'electronics':
      return Icons.smartphone_outlined;
    case 'vehicles':
      return Icons.directions_car_outlined;
    case 'real_estate':
      return Icons.home_work_outlined;
    case 'home':
      return Icons.chair_outlined;
    case 'fashion':
      return Icons.checkroom_outlined;
    case 'beauty':
      return Icons.face_retouching_natural_outlined;
    case 'kids':
      return Icons.toys_outlined;
    case 'sports_hobbies':
      return Icons.sports_soccer_outlined;
    case 'tools_equipment':
      return Icons.handyman_outlined;
    case 'books_stationery':
      return Icons.menu_book_outlined;
    case 'agri_livestock':
      return Icons.agriculture_outlined;
    case 'services':
      return Icons.miscellaneous_services_outlined;
    case 'jobs':
      return Icons.work_outline;
    default:
      return Icons.category_outlined;
  }
}

Color _accentForMain(String id, ColorScheme cs) {
  // Subtle “pastel” accents per category.
  switch (id) {
    case 'electronics':
      return cs.primary.withValues(alpha: 0.10);
    case 'vehicles':
      return cs.secondary.withValues(alpha: 0.10);
    case 'real_estate':
      return Colors.green.withValues(alpha: 0.10);
    case 'fashion':
      return Colors.pink.withValues(alpha: 0.10);
    case 'home':
      return Colors.orange.withValues(alpha: 0.10);
    case 'services':
      return Colors.purple.withValues(alpha: 0.10);
    default:
      return cs.surfaceContainerHighest.withValues(alpha: 0.55);
  }
}

class _MainCatTile extends StatelessWidget {
  const _MainCatTile({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.selected,
    required this.accent,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.06) : cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.42)
                : cs.outline.withValues(alpha: 0.22),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 22, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 12, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubTile extends StatelessWidget {
  const _SubTile({required this.title, required this.onTap, this.imageUrl});

  final String title;
  final VoidCallback onTap;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withValues(alpha: 0.30)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: imageUrl == null
                  ? Container(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      child: Icon(Icons.image_outlined,
                          color: cs.onSurface.withValues(alpha: 0.35)),
                    )
                  : CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          color: cs.surfaceContainerHighest
                              .withValues(alpha: 0.55)),
                      errorWidget: (_, __, ___) => Container(
                        color:
                            cs.surfaceContainerHighest.withValues(alpha: 0.55),
                        child: Icon(Icons.image_not_supported_outlined,
                            color: cs.onSurface.withValues(alpha: 0.35)),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 12, height: 1.15),
                textAlign: TextAlign.start,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Guest signup banner
// -----------------------------------------------------------------------------

class _GuestSignupBanner extends StatelessWidget {
  const _GuestSignupBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final title = context.tr('categories.guest_banner_title');
    final subtitle = context.tr('categories.guest_banner_subtitle');
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
          color: cs.primary.withValues(alpha: 0.06),
        ),
        child: Row(
          children: [
            Icon(Icons.person_add_alt_1_outlined, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.70))),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurface.withValues(alpha: 0.55),
            )
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Trending chips + Quick publish
// -----------------------------------------------------------------------------

class _TrendingChips extends StatelessWidget {
  const _TrendingChips({required this.onQuery, required this.terms});

  final void Function(String q) onQuery;
  final List<String> terms;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final title = const L10n3(
            ar: 'الأكثر بحثًا في موريتانيا',
            fr: 'Tendances en Mauritanie',
            en: 'Trending in Mauritania')
        .of(context);

    // Fallback (when the device has no history yet)
    final fallback = <String>[
      const L10n3(ar: 'تويوتا', fr: 'Toyota', en: 'Toyota').of(context),
      const L10n3(ar: 'آيفون', fr: 'iPhone', en: 'iPhone').of(context),
      const L10n3(
              ar: 'كراء شقة', fr: 'Location appartement', en: 'Apartment rent')
          .of(context),
      const L10n3(ar: 'خروف', fr: 'Mouton', en: 'Sheep').of(context),
      const L10n3(ar: 'مواد البناء', fr: 'Matériaux', en: 'Building materials')
          .of(context),
    ];

    final items = (terms.isNotEmpty ? terms : fallback)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(10)
        .toList();

    if (items.isEmpty) return const SizedBox.shrink();

    InputChip chip(String label) {
      return InputChip(
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onPressed: () => onQuery(label),
        backgroundColor: cs.surface,
        side: BorderSide(color: cs.outline.withValues(alpha: 0.24)),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(fontWeight: FontWeight.w800),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items.map(chip).toList(),
        ),
      ],
    );
  }
}

class _QuickPublishRow extends StatelessWidget {
  const _QuickPublishRow({required this.onTapPublish});

  final void Function(String route, String title) onTapPublish;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final title = const L10n3(
            ar: 'نشر سريع', fr: 'Publication rapide', en: 'Quick publish')
        .of(context);

    Widget btn(
        {required String label,
        required IconData icon,
        required String route}) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTapPublish(route, label),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
            color: cs.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: cs.onSurface.withValues(alpha: 0.55)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            btn(
              label: const L10n3(ar: 'سيارة', fr: 'Voiture', en: 'Car')
                  .of(context),
              icon: Icons.directions_car_outlined,
              route: '/publish',
            ),
            btn(
              label: const L10n3(ar: 'هاتف', fr: 'Téléphone', en: 'Phone')
                  .of(context),
              icon: Icons.smartphone_outlined,
              route: '/publish',
            ),
            btn(
              label:
                  const L10n3(ar: 'عقار', fr: 'Immobilier', en: 'Real estate')
                      .of(context),
              icon: Icons.home_work_outlined,
              route: '/publish',
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Product shelves (to keep Categories lively 🎯)
// -----------------------------------------------------------------------------

class _CategoryProductShelves extends ConsumerWidget {
  const _CategoryProductShelves({required this.selectedCategoryId});

  final String? selectedCategoryId;

  AppProduct? _byId(List<AppProduct> all, String id) {
    final needle = id.trim();
    if (needle.isEmpty) return null;
    for (final p in all) {
      if (p.id == needle) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final store = ref.watch(localStoreProvider);

    final allAsync = ref.watch(productsFeedProvider);

    return allAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (all) {
        final recentIds = store.getRecentlyViewedIds();
        final recent = <AppProduct>[];
        for (final id in recentIds) {
          final p = _byId(all, id);
          if (p != null) recent.add(p);
          if (recent.length >= 10) break;
        }

        final catName = selectedCategoryId == null
            ? null
            : maCategories
                .where((c) => c.id == selectedCategoryId)
                .map((c) => c.name.of(context))
                .cast<String?>()
                .firstOrNull;

        final inCategory = selectedCategoryId == null
            ? <AppProduct>[]
            : all.where((p) => p.category == selectedCategoryId).toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

        final newest = all.toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

        final vipTop = all.where(PromoModeration.isVipTopActive).toList();
        final vipFeatured =
            all.where(PromoModeration.isVipFeaturedActive).toList();
        final vipBoost = all.where(PromoModeration.isVipBoostActive).toList();

        // De-duplicate across shelves so it feels "fresh".
        final used = <String>{};
        List<AppProduct> takeFresh(Iterable<AppProduct> src, int n) {
          final out = <AppProduct>[];
          for (final p in src) {
            if (out.length >= n) break;
            if (used.contains(p.id)) continue;
            used.add(p.id);
            out.add(p);
          }
          return out;
        }

        // Recommendations: prefer the most frequent recent category, else selectedCategoryId.
        String? seedCat;
        if (recent.isNotEmpty) {
          final counts = <String, int>{};
          for (final p in recent) {
            final c = (p.category ?? '').trim();
            if (c.isEmpty) continue;
            counts[c] = (counts[c] ?? 0) + 1;
          }
          if (counts.isNotEmpty) {
            final best = counts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            seedCat = best.first.key;
          }
        }
        seedCat ??= selectedCategoryId;

        final forYou = <AppProduct>[
          ...all.where((p) => seedCat != null && p.category == seedCat),
          ...vipTop,
          ...vipFeatured,
          ...vipBoost,
          ...newest,
        ];

        // --- Build shelves ---
        final children = <Widget>[];

        Widget gap([double h = 14]) => SizedBox(height: h);

        if (vipTop.isNotEmpty || vipFeatured.isNotEmpty || vipBoost.isNotEmpty) {
          final vip = <AppProduct>[
            ...vipTop,
            ...vipFeatured,
            ...vipBoost,
          ];
          children.add(_ProductShelf(
            title: const L10n3(ar: 'منتجات VIP', fr: 'Produits VIP', en: 'VIP picks')
                .of(context),
            products: takeFresh(vip, 10),
            subtitle: const L10n3(
              ar: 'تظهر هنا المنتجات المروّجة.',
              fr: 'Les promotions apparaissent ici.',
              en: 'Promoted items appear here.',
            ).of(context),
          ));
          children.add(gap());
        }

        if (recent.isNotEmpty) {
          children.add(_ProductShelf(
            title: const L10n3(
                    ar: 'شاهدت مؤخرًا', fr: 'Vu récemment', en: 'Recently viewed')
                .of(context),
            products: takeFresh(recent, 10),
          ));
          children.add(gap());
        }

        if (inCategory.isNotEmpty && catName != null) {
          children.add(_ProductShelf(
            title: const L10n3(
                    ar: 'من هذه الفئة',
                    fr: 'Dans cette catégorie',
                    en: 'In this category')
                .of(context),
            products: takeFresh(inCategory, 10),
            trailing: Text(
              catName,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.60),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ));
          children.add(gap());
        }

        children.add(_ProductShelf(
          title: const L10n3(ar: 'قد يعجبك', fr: 'Pour vous', en: 'For you')
              .of(context),
          products: takeFresh(forYou, 12),
          subtitle: const L10n3(
            ar: 'اقتراحات مبنية على تفاعلك داخل التطبيق.',
            fr: 'Suggestions basées sur votre activité.',
            en: 'Suggestions based on your activity.',
          ).of(context),
        ));
        children.add(gap());

        children.add(_ProductShelf(
          title: const L10n3(ar: 'جديد اليوم', fr: 'Nouveautés', en: 'New today')
              .of(context),
          products: takeFresh(newest, 12),
        ));

        if (children.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      },
    );
  }
}
class _ProductShelf extends StatelessWidget {
  const _ProductShelf({
    required this.title,
    required this.products,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final List<AppProduct> products;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w900)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 146,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = products[i];
              return SizedBox(
                width: 260,
                child: ProductCard(
                  product: p,
                  variant: ProductCardVariant.trending,
                  onTap: () => context.push('/product/${p.id}'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Tiny helper for firstOrNull without extra imports.
extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}