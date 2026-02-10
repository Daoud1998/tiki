import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:tiki/core/state/auth_state.dart' as auth;
import 'package:tiki/core/utils/name_utils.dart';

import '../../../core/state/likes_controller.dart';
import '../../../core/state/recently_viewed_controller.dart';
import '../../../core/widgets/product_card.dart';
import 'package:tiki/features/product/domain/app_product.dart';
import 'package:tiki/features/product/state/products_providers.dart';
import 'package:tiki/features/notifications/presentation/notifications_controller.dart';

class YouScreen extends ConsumerStatefulWidget {
  const YouScreen({super.key});

  @override
  ConsumerState<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends ConsumerState<YouScreen> {
  Future<void> _refresh() async {
    // In mock mode, we just rebuild and refresh light providers.
    ref.invalidate(notificationsUnreadCountProvider);
    ref.invalidate(productsFeedProvider);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final authState = ref.watch(auth.authControllerProvider);

    final likedIds = ref.watch(likesProvider); // Set<String>
    final recentIds = ref.watch(recentlyViewedProvider); // List<String>
    final unread = ref.watch(notificationsUnreadCountProvider);

    if (kDebugMode) {
      debugPrint('[YouScreen] unread notifications = $unread');
    }
    final allProducts =
        ref.watch(productsFeedProvider).asData?.value ?? const <AppProduct>[];
    final likedProducts = _idsToProducts(likedIds, allProducts);
    final recentProducts = _idsToProducts(recentIds, allProducts);
    final recommend = _buildRecommendations(
        likedIds: likedIds, recentIds: recentIds, allProducts: allProducts);
    final hasPersonalSignal = likedIds.isNotEmpty || recentIds.isNotEmpty;
    final recTitle = hasPersonalSignal
        ? _tr(context,
            ar: 'قد يعجبك', fr: 'Vous aimerez peut-être', en: 'You may like')
        : _tr(context, ar: 'الأحدث', fr: 'Nouveautés', en: 'Newest');

    final recHint = hasPersonalSignal
        ? _tr(context,
            ar: 'حسب الإعجابات والمحفوظات',
            fr: 'Basé sur vos favoris & vues',
            en: 'Based on likes & views')
        : _tr(context,
            ar: 'عناصر جديدة من السوق',
            fr: 'Nouveaux articles du marché',
            en: 'Fresh items from the market');

    final title = authState.isSignedIn
        ? NameUtils.firstName(
            authState.name,
            fallback: _tr(context, ar: 'حسابي', fr: 'Compte', en: 'Account'),
          )
        : _tr(context, ar: 'زائر', fr: 'Invité', en: 'Guest');

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          _NotifActionButton(
            count: unread,
            tooltip: _tr(context,
                ar: 'الإشعارات', fr: 'Notifications', en: 'Notifications'),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            tooltip: _tr(context, ar: 'مشاركة', fr: 'Partager', en: 'Share'),
            onPressed: () {
              const link = 'https://tiki.app';
              Share.share(link, subject: 'TIKI');
            },
            icon: const Icon(Icons.share_rounded),
          ),
          IconButton(
            tooltip: _tr(context, ar: 'الدعم', fr: 'Support', en: 'Support'),
            onPressed: () => context.push('/you/support'),
            icon: const Icon(Icons.headset_mic_rounded),
          ),
          IconButton(
            tooltip:
                _tr(context, ar: 'الإعدادات', fr: 'Paramètres', en: 'Settings'),
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: _AccountCard(authState: authState),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            if (!authState.isSignedIn)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                sliver: SliverToBoxAdapter(
                  child: _GuestSignupBanner(
                    onTap: () => context.push('/auth'),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            // Tiles (scrollable now)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    _Tile(
                      icon: Icons.verified_outlined,
                      title: _tr(context,
                          ar: 'موثّق تيكي',
                          fr: 'Tikki Vérifié',
                          en: 'Tikki Verified'),
                      subtitle: _tr(context,
                          ar: 'توثيق الحساب وزيادة الثقة',
                          fr: 'Vérification du compte',
                          en: 'Account verification'),
                      onTap: () => context.push(
                        authState.isSignedIn
                            ? '/you/verify'
                            : '/auth?next=%2Fyou%2Fverify',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Tile(
                      icon: Icons.storefront_rounded,
                      title: _tr(context,
                          ar: 'إعلاناتي',
                          fr: 'Mes annonces',
                          en: 'My listings'),
                      subtitle: _tr(context,
                          ar: 'تعديل / بيع / حذف',
                          fr: 'Modifier / Vendu / Supprimer',
                          en: 'Edit / Sold / Delete'),
                      onTap: () => context.push('/you/listings'),
                    ),
                    const SizedBox(height: 8),
_Tile(
                      icon: Icons.chat_bubble_rounded,
                      title: _tr(context,
                          ar: 'الدعم داخل التطبيق',
                          fr: 'Chat support',
                          en: 'In-app support'),
                      subtitle: _tr(context,
                          ar: 'مراسلة الإدارة مباشرة',
                          fr: 'Écrivez au support',
                          en: 'Message the support team'),
                      onTap: () {
                        if (!authState.isSignedIn) {
                          context.push('/auth');
                          return;
                        }
                        // Open as a full-screen route (outside the bottom nav shell).
                        context.push('/support-chat');
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // Likes
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: _SectionTitle(
                    _tr(context, ar: 'الإعجابات', fr: 'Favoris', en: 'Likes')),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: likedProducts.isEmpty
                    ? _EmptyLine(_tr(context,
                        ar: 'لا توجد عناصر في المفضلة بعد',
                        fr: 'Aucun favori pour le moment',
                        en: 'No likes yet'))
                    : _HorizontalProducts(products: likedProducts),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // Recently viewed
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: _SectionTitle(_tr(context,
                          ar: 'المحفوظات',
                          fr: 'Récemment consultés',
                          en: 'Recently viewed')),
                    ),
                    if (recentIds.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            ref.read(recentlyViewedProvider.notifier).clear(),
                        child: Text(_tr(context,
                            ar: 'مسح', fr: 'Effacer', en: 'Clear')),
                      ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: recentProducts.isEmpty
                    ? _EmptyLine(_tr(context,
                        ar: 'لا توجد محفوظات بعد',
                        fr: 'Aucun historique pour le moment',
                        en: 'No history yet'))
                    : _HorizontalProducts(products: recentProducts),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // Recommendations
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(recTitle),
                    const SizedBox(height: 4),
                    Text(
                      recHint,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final p = recommend[i];
                    return ProductCard(
                      product: p,
                      variant: ProductCardVariant.compact,
                      showMeta: true,
                      onTap: () => context.push('/product/${p.id}'),
                    );
                  },
                  childCount: recommend.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.90,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  List<AppProduct> _idsToProducts(Iterable<String> ids, List<AppProduct> all) {
    final byId = <String, AppProduct>{for (final p in all) p.id: p};
    final out = <AppProduct>[];
    for (final id in ids) {
      final p = byId[id.trim()];
      if (p != null) out.add(p);
    }
    return out;
  }

  List<AppProduct> _buildRecommendations({
    required Set<String> likedIds,
    required List<String> recentIds,
    required List<AppProduct> allProducts,
  }) {
    if (allProducts.isEmpty) return const [];

    // Seed: most recent viewed, else first liked, else newest product.
    AppProduct? seed;
    final byId = <String, AppProduct>{for (final p in allProducts) p.id: p};

    for (final id in recentIds) {
      seed = byId[id];
      if (seed != null) break;
    }
    seed ??= likedIds.isNotEmpty ? byId[likedIds.first] : null;
    seed ??= allProducts.first;

    final excluded = <String>{...likedIds, ...recentIds, seed!.id};

    final candidates =
        allProducts.where((p) => !excluded.contains(p.id)).toList();

    // If the catalog is small, exclusions may remove everything.
    if (candidates.isEmpty) {
      return allProducts
          .where((p) => p.id != seed!.id)
          .take(6)
          .toList(growable: false);
    }

    double score(AppProduct p) {
      final sameWilaya = (p.wilaya == seed!.wilaya) ? 1 : 0;
      final sameMoughataa = (p.moughataa == seed!.moughataa) ? 1 : 0;

      final priceDiff = (p.price - seed!.price).abs().toDouble();
      final priceScore = -priceDiff / 5000.0; // gentle

      final recencyHours =
          DateTime.now().difference(p.publishedAt).inHours.toDouble();
      final recencyScore = -recencyHours / 72.0; // prefer newer

      // Weights tuned for Mauritania: location first, then price, then recency.
      return (sameWilaya * 2.0) +
          (sameMoughataa * 3.0) +
          priceScore +
          recencyScore;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));

    return candidates.take(6).toList(growable: false);
  }

  String _tr(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    return en;
  }
}

class _NotifActionButton extends StatelessWidget {
  const _NotifActionButton({
    required this.count,
    required this.tooltip,
    required this.onPressed,
  });

  final int count;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded),
          if (count > 0)
            PositionedDirectional(
              end: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.surface, width: 2),
                ),
                constraints: const BoxConstraints(minWidth: 18),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onError,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.authState});
  final auth.AuthState authState;

  String _tr(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    return en;
  }

  String _ltr(String s) => '\u2066$s\u2069';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSignedIn = authState.isSignedIn;
    final s = Theme.of(context);

    final rawName = (authState.name ?? '').trim();
    final nameLooksId = RegExp(r'^\d{5,}$').hasMatch(rawName);

    final displayName = isSignedIn
        ? (nameLooksId
            ? _tr(context, ar: 'حساب', fr: 'Compte', en: 'Account')
            : NameUtils.firstName(
                rawName,
                fallback: _tr(context, ar: 'حساب', fr: 'Compte', en: 'Account'),
              ))
        : _tr(context, ar: 'زائر', fr: 'Invité', en: 'Guest');

    final subtitle = isSignedIn
        ? _ltr((authState.phoneE164 ?? authState.email ?? '').trim().isEmpty
            ? '—'
            : (authState.phoneE164 ?? authState.email ?? ''))
        : _tr(context,
            ar: 'سجّل لتزامن الإعجابات',
            fr: 'Connectez-vous pour synchroniser',
            en: 'Sign in to sync likes');

    final initial = (displayName.trim().isEmpty ? 'T' : displayName.trim()[0])
        .toUpperCase();

    final VoidCallback onTap = () {
      if (isSignedIn) {
        context.push('/account/edit');
      } else {
        context.push('/auth?next=${Uri.encodeComponent('/account/edit')}');
      }
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: s.colorScheme.surface,
          border: Border.all(color: s.dividerColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: s.colorScheme.primary.withValues(alpha: 0.12),
              child: Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: s.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: s.colorScheme.onSurface.withValues(alpha: 0.65),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: () async {
                if (!isSignedIn) {
                  context.push('/auth');
                  return;
                }
                await ref.read(auth.authControllerProvider.notifier).signOut();
                // Refresh product feed & notifications immediately after logout.
                ref.invalidate(notificationsUnreadCountProvider);
                ref.invalidate(productsFeedProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_tr(context,
                          ar: 'تم تسجيل الخروج',
                          fr: 'Déconnecté',
                          en: 'Signed out')),
                    ),
                  );
                  final t = DateTime.now().millisecondsSinceEpoch.toString();
                  context.go('/home?r=logout_$t');
                }
              },
              child: Text(isSignedIn
                  ? _tr(context, ar: 'خروج', fr: 'Sortir', en: 'Sign out')
                  : _tr(context, ar: 'تسجيل', fr: 'Connexion', en: 'Sign in')),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestSignupBanner extends StatelessWidget {
  const _GuestSignupBanner({required this.onTap});
  final VoidCallback onTap;

  String _tr(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    return en;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
        color: cs.surface,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: cs.primary.withValues(alpha: 0.10),
            ),
            child: Icon(Icons.card_giftcard_rounded, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(context,
                      ar: 'سجّل لتستفيد من عروض تيكي',
                      fr: "Inscrivez-vous pour profiter des offres",
                      en: 'Sign up to get Tikki deals'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  _tr(context,
                      ar: '• دخول السحب  • مزامنة المفضلة  • لا فقدان للبيانات',
                      fr: '• Tirages  • Favoris synchronisés  • Données sauvegardées',
                      en: '• Draws  • Sync likes  • No data loss'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.70),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child:
                Text(_tr(context, ar: 'تسجيل', fr: 'Connexion', en: 'Sign up')),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badgeCount,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int? badgeCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Keep the chevron direction consistent (like the Ads list), even if some
    // route accidentally ends up with a wrong Directionality.
    final dir = Directionality.maybeOf(context);
    String? lang;
    try {
      lang = Localizations.localeOf(context).languageCode.toLowerCase();
    } catch (_) {
      lang = null;
    }
    final isRtl = dir == TextDirection.rtl ||
        (lang != null && const {'ar', 'fa', 'ur', 'he'}.contains(lang));
    final chevron = Icon(
      Icons.chevron_right_rounded,
      color: cs.onSurface.withValues(alpha: 0.55),
    );

    final int count = badgeCount ?? 0;
    final bool showBadge = count > 0;

    Widget badgePill() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.surface, width: 2),
        ),
        constraints: const BoxConstraints(minWidth: 18),
        child: Text(
          count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onError,
            fontWeight: FontWeight.w900,
            fontSize: 10,
            height: 1,
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: cs.primary),
                ),
                if (showBadge)
                  PositionedDirectional(
                    end: -2,
                    top: -2,
                    child: badgePill(),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            chevron,
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _HorizontalProducts extends StatelessWidget {
  const _HorizontalProducts({required this.products});
  final List<AppProduct> products;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 270,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final p = products[i];
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
    );
  }
}
