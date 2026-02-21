import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/state/auth_state.dart' as auth;
import '../features/notifications/presentation/notifications_controller.dart'
    as notif;
import '../features/auth/presentation/phone_login_screen.dart';
import '../features/home/presentation/home_screen.dart';
import 'localization/l10n.dart';

// Screens
import '../features/splash/presentation/splash_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';

import '../features/categories/presentation/categories_screen.dart';
import '../features/search/presentation/search_results_screen.dart';
import '../features/product/presentation/product_details_screen.dart';
import '../features/publish/presentation/publish_drafts_screen.dart';
import '../features/publish/presentation/publish_wizard_screen.dart';
import '../features/legal/presentation/legal_document_screen.dart';
import '../features/you/presentation/you_screen.dart';
import '../features/you/presentation/settings_screen.dart';
import '../features/you/presentation/edit_account_screen.dart';
import '../features/you/presentation/my_listings_screen.dart';
import '../features/you/presentation/blocked_sellers_screen.dart';
import '../features/you/presentation/support_screen.dart';
import '../features/support/presentation/support_chat_screen.dart';
import '../features/receipts/presentation/my_receipts_screen.dart';
import '../features/receipts/presentation/receipt_details_screen.dart';
import '../features/seller/presentation/seller_products_screen.dart';
import '../features/discounts/presentation/discounts_screen.dart';
import '../features/most_viewed/presentation/most_viewed_screen.dart';

// Content (Temu-style tiles)
import '../features/content/presentation/about_tiki_screen.dart';
import '../features/content/presentation/policies_hub_screen.dart';
import '../features/content/presentation/policy_article_screen.dart';

import '../features/kyc/presentation/verification_screen.dart';
import '../features/kyc/presentation/kyc_submit_screen.dart';

/// Navigator keys
///
/// ✅ Fixes crashes when navigating from root pages (like /notifications)
/// into "detail" pages (like /product/:id) while using a ShellRoute.
///
/// Important go_router rule:
/// - Routes INSIDE a ShellRoute must NOT use a different parentNavigatorKey.
/// - If you want a route to be shown on the ROOT navigator, define it as a
///   TOP-LEVEL route (outside ShellRoute) and set parentNavigatorKey to root.
final _rootNavKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');
final _shellNavKey = GlobalKey<NavigatorState>(debugLabel: 'shellNav');

final appRouterProvider = Provider<GoRouter>((ref) {
  final _refresh = ValueNotifier<int>(0);
  ref.onDispose(_refresh.dispose);

  ref.listen<auth.AuthState>(
    auth.authControllerProvider,
    (_, __) => _refresh.value++,
  );
  return GoRouter(
    navigatorKey: _rootNavKey,
    refreshListenable: _refresh,
    initialLocation: '/home?r=boot',
    errorBuilder: (context, state) => _RouteErrorScreen(
      uri: state.uri.toString(),
      message: state.error?.toString(),
    ),
    redirect: (context, state) {
      final authState = ref.read(auth.authControllerProvider);
      final loc = state.uri.toString();
      final isAuth = state.matchedLocation == '/auth';

      final requiresAuth = state.matchedLocation.startsWith('/publish') ||
          state.matchedLocation.startsWith('/you/listings') ||
          state.matchedLocation == '/account/edit' ||
          state.matchedLocation.startsWith('/you/verify/submit') ||
          state.matchedLocation.startsWith('/admin');

      if (requiresAuth && !authState.isSignedIn) {
        final next = Uri.encodeComponent(loc);
        return '/auth?next=$next';
      }

      if (isAuth && authState.isSignedIn) {
        final next = state.uri.queryParameters['next'];
        if (next != null && next.isNotEmpty) return Uri.decodeComponent(next);
        return '/home?r=login';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/home'),

      // Alias routes: some parts of the app still navigate to /account
      // (older deep-links / bottom-nav). Redirect them to the current /you routes.
      GoRoute(path: '/account', redirect: (_, __) => '/you'),
      GoRoute(path: '/account/support', redirect: (_, __) => '/you/support'),
      GoRoute(path: '/account/verify', redirect: (_, __) => '/you/verify'),
      GoRoute(
          path: '/account/verify/submit',
          redirect: (_, __) => '/you/verify/submit'),
      GoRoute(path: '/account/listings', redirect: (_, __) => '/you/listings'),

      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const PhoneLoginScreen(),
      ),

      GoRoute(
        path: '/legal/:doc',
        builder: (context, state) {
          final doc = state.pathParameters['doc'] ?? 'terms';
          return LegalDocumentScreen(docId: doc);
        },
      ),

      // Temu-style content pages
      GoRoute(
        path: '/content/about',
        builder: (context, state) => const AboutTikiScreen(),
      ),
      GoRoute(
        path: '/content/policies',
        builder: (context, state) => const PoliciesHubScreen(),
      ),
      GoRoute(
        path: '/content/policies/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? 'terms';
          return PolicyArticleScreen(articleId: id);
        },
      ),

      // Root-level pages (outside ShellRoute)
      GoRoute(
        path: '/account/edit',
        builder: (context, state) => const EditAccountScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/promo-ads',
        redirect: (context, state) => '/you/support',
      ),
      GoRoute(
        path: '/support-chat',
        builder: (context, state) => const SupportChatScreen(),
      ),

      // ✅ Detail pages on ROOT navigator (safe to open from notifications)
      GoRoute(
        path: '/product/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ProductDetailsScreen(productId: id);
        },
      ),
      GoRoute(
        path: '/seller/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final qp = state.uri.queryParameters;
          return SellerProductsScreen(
            sellerId: id,
            sellerName: qp['name'],
          );
        },
      ),

      // Bottom navigation Shell (tabs)
      ShellRoute(
        navigatorKey: _shellNavKey,
        builder: (context, state, child) => _MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) {
              final qp = state.uri.queryParameters;
              return HomeScreen(
                refreshToken: qp['r'],
                focusId: qp['focus'],
              );
            },
          ),
          GoRoute(
            path: '/categories',
            builder: (context, state) => const CategoriesScreen(),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) {
              final qp = state.uri.queryParameters;
              return SearchResultsScreen(
                wilaya: qp['wilaya'],
                moughataa: qp['moughataa'],
                excludedId: qp['exclude'],
                initialQuery: qp['q'],
                phone: qp['phone'],
                categoryId: qp['cat'],
                subCategoryId: qp['sub'],
              );
            },
          ),
          GoRoute(
            path: '/publish',
            builder: (context, state) =>
                PublishDraftsScreen(extra: state.extra),
            routes: [
              GoRoute(
                path: 'wizard/:draftId',
                builder: (context, state) {
                  final draftId = state.pathParameters['draftId']!;
                  return PublishWizardScreen(draftId: draftId);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/you',
            builder: (context, state) => const YouScreen(),
          ),
          GoRoute(
            path: '/you/verify',
            builder: (context, state) => const VerificationScreen(),
            routes: [
              GoRoute(
                path: 'submit',
                builder: (context, state) => const KycSubmitScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/you/listings',
            builder: (context, state) => const MyListingsScreen(),
          ),
          GoRoute(
            path: '/you/blocked',
            builder: (context, state) => const BlockedSellersScreen(),
          ),
          GoRoute(
            path: '/you/receipts',
            builder: (context, state) => const MyReceiptsScreen(),
          ),
          GoRoute(
            path: '/you/receipts/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ReceiptDetailsScreen(receiptId: id);
            },
          ),
          GoRoute(
            path: '/you/support',
            builder: (context, state) => const SupportScreen(),
          ),
          GoRoute(
            path: '/discounts',
            builder: (context, state) => const DiscountsScreen(),
          ),
          GoRoute(
            path: '/most-viewed',
            builder: (context, state) => const MostViewedScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

class _MainScaffold extends StatefulWidget {
  const _MainScaffold({required this.child});
  final Widget child;

  @override
  State<_MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<_MainScaffold> {
  int _indexFromLocation(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/discounts')) return 0;
    if (location.startsWith('/most-viewed')) return 0;
    if (location.startsWith('/categories')) return 1;
    if (location.startsWith('/publish')) return 2;
    if (location.startsWith('/you') || location.startsWith('/settings'))
      return 3;
    if (location.startsWith('/search')) return 0;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        final t = DateTime.now().millisecondsSinceEpoch.toString();
        context.go('/home?r=$t');
        break;
      case 1:
        context.go('/categories');
        break;
      case 2:
        context.go('/publish');
        break;
      case 3:
        context.go('/you');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location =
        GoRouter.of(context).routerDelegate.currentConfiguration.uri.toString();
    final current = _indexFromLocation(location);
    final s = AppStrings.of(context);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: current,
        onDestinationSelected: (i) => _onTap(context, i),
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: s.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.manage_search),
            selectedIcon: const Icon(Icons.manage_search),
            label: s.navCategories,
          ),
          NavigationDestination(
            icon: const Icon(Icons.add_circle_outline),
            selectedIcon: const Icon(Icons.add_circle),
            label: s.navPublish,
          ),
          NavigationDestination(
            icon: Consumer(
              builder: (context, ref, _) {
                // Keep the badge in sync with the Notifications screen.
                final unread = ref.watch(
                  notif.notificationsControllerProvider
                      .select((s) => s.unreadCount),
                );
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.person_outline),
                    if (unread > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onError,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            selectedIcon: Consumer(
              builder: (context, ref, _) {
                final unread = ref.watch(
                  notif.notificationsControllerProvider
                      .select((s) => s.unreadCount),
                );
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.person_rounded),
                    if (unread > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onError,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            label: s.navYou,
          ),
        ],
      ),
    );
  }
}

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({required this.uri, this.message});
  final String uri;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).appName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 56),
              const SizedBox(height: 12),
              Text(
                AppStrings.of(context).pageNotFound,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(uri, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(message!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.home_rounded),
                label: Text(AppStrings.of(context).backHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
