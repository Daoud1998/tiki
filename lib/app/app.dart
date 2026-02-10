import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notifications/presentation/notifications_controller.dart';
import '../features/notifications/presentation/inbox_watcher.dart';
import '../features/receipts/presentation/receipts_controller.dart';
import '../features/receipts/services/renewal_reminders.dart';
import 'localization/l10n.dart';
import 'router.dart';
import 'state/app_setings.dart';
import 'theme/app_theme.dart';
import '../core/local_db/local_products_cache.dart';

class TikiApp extends ConsumerStatefulWidget {
  const TikiApp({super.key});

  static const supportedLocales = <Locale>[
    Locale('ar'),
    Locale('fr'),
    Locale('en'),
  ];

  @override
  ConsumerState<TikiApp> createState() => _TikiAppState();
}

class _TikiAppState extends ConsumerState<TikiApp> {
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Run once, after the first frame.
    if (_didInit) return;
    _didInit = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Load receipts early so we can emit renewal reminders even if the user
      // doesn't open the listings screen.
      final receiptsCtrl = ref.read(receiptsControllerProvider.notifier);
      await receiptsCtrl.load();
      await receiptsCtrl.expireIfNeeded();

      final receipts = ref.read(receiptsControllerProvider);
      final nCtrl = ref.read(notificationsControllerProvider.notifier);
      ReceiptsRenewalReminders.run(receipts, nCtrl);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Start Firestore → SQLite sync for fast local search.
    ref.watch(localProductsSyncProvider);
    // Start realtime in-app notifications (user_inbox watcher).
    ref.watch(inboxWatcherProvider);
    final themeMode = ref.watch(themeModeProvider);
    final localeOverride = ref.watch(localeOverrideProvider);
    final router = ref.watch(appRouterProvider);

    final platformLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final effectiveLocale = localeOverride ?? platformLocale;
    final isArabic = effectiveLocale.languageCode.toLowerCase() == 'ar';

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Tiki',
      theme: AppTheme.light(isArabic: isArabic),
      darkTheme: AppTheme.dark(isArabic: isArabic),
      themeMode: themeMode,
      supportedLocales: TikiApp.supportedLocales,
      locale: localeOverride,
      localeResolutionCallback: (device, supported) {
        final d = device ?? const Locale('ar');
        for (final s in supported) {
          if (s.languageCode.toLowerCase() == d.languageCode.toLowerCase()) {
            return s;
          }
        }
        // Default: Arabic (Mauritania-first)
        return const Locale('ar');
      },
      builder: (context, child) {
        final loc = Localizations.localeOf(context);
        final isRtl = loc.languageCode.toLowerCase() == 'ar';
        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
