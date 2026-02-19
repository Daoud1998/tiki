import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/localization/l10n.dart';
import '../../../app/state/app_setings.dart';
import '../../../core/state/admin_state.dart';
import '../../../core/state/auth_state.dart' as auth;
import '../../../core/state/notifications_controller.dart';
import '../../../core/state/seller_phone_search_state.dart';
import '../../../core/utils/name_utils.dart';
import '../../product/state/products_providers.dart';

/// Whether push notifications are enabled for the signed-in user.
///
/// Stored in Firestore at: /users/{uid}.notificationsEnabled
/// Defaults to `true` when missing.
final notificationsEnabledProvider =
    StreamProvider.family<bool, String>((ref, uid) {
  final id = uid.trim();
  if (id.isEmpty) {
    return Stream<bool>.value(true);
  }
  final doc = FirebaseFirestore.instance.collection('users').doc(id);
  return doc.snapshots().map((snap) {
    final data = snap.data();
    final v = data == null ? null : data['notificationsEnabled'];
    return v is bool ? v : true;
  }).handleError((_) => true);
});

void _safeBack(BuildContext context) {
  // Settings can be opened with context.go(), so there may be nothing to pop.
  final router = GoRouter.of(context);

  try {
    if (router.canPop()) {
      router.pop();
      return;
    }
  } catch (_) {}

  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return;
  }

  // Fallback to a known shell route. Avoid '/' because this app
  // uses /home as the main entry inside the ShellRoute.
  const candidates = <String>[
    '/you',
    '/home',
    '/categories',
  ];

  for (final path in candidates) {
    try {
      router.go(path);
      return;
    } catch (_) {
      // ignore and try next
    }
  }
}

String _pick3(AppStrings s,
    {required String ar, required String fr, required String en}) {
  if (s.isFr) return fr;
  if (s.isAr) return ar;
  return en;
}

@immutable
class _PickResult<T> {
  final bool picked;
  final T value;
  const _PickResult(this.picked, this.value);
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final localeOverride = ref.watch(localeOverrideProvider);
    final authState = ref.watch(auth.authControllerProvider);
    final isAdmin = ref.watch(isAdminProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );

    final uid = (authState.userId ?? '').trim();
    final notifEnabledAsync = (authState.isSignedIn && uid.isNotEmpty)
        ? ref.watch(notificationsEnabledProvider(uid))
        : const AsyncValue<bool>.data(true);
    final notifEnabled = notifEnabledAsync.maybeWhen(
      data: (v) => v,
      orElse: () => true,
    );

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final chevron =
        isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded;

    final langLabel = switch (localeOverride?.languageCode) {
      null => _pick3(s,
          ar: 'تلقائي (لغة الجهاز)',
          fr: 'Auto (langue du téléphone)',
          en: 'Auto (device)'),
      'ar' => 'العربية',
      'fr' => 'Français',
      'en' => 'English',
      _ => _pick3(s,
          ar: 'تلقائي (لغة الجهاز)',
          fr: 'Auto (langue du téléphone)',
          en: 'Auto (device)'),
    };

    final themeLabel = switch (themeMode) {
      ThemeMode.system => _pick3(s,
          ar: 'تلقائي (حسب الجهاز)', fr: 'Auto (système)', en: 'Auto (system)'),
      ThemeMode.light => _pick3(s, ar: 'فاتح', fr: 'Clair', en: 'Light'),
      ThemeMode.dark => _pick3(s, ar: 'داكن', fr: 'Sombre', en: 'Dark'),
    };

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => _safeBack(context)),
        title: Text(s.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _AccountCard(authState: authState),
          const SizedBox(height: 14),
          _GroupCard(
            title: _pick3(s,
                ar: 'التفضيلات', fr: 'Préférences', en: 'Preferences'),
            children: [
              _SettingTile(
                icon: Icons.language_rounded,
                title: _pick3(s, ar: 'اللغة', fr: 'Langue', en: 'Language'),
                subtitle: langLabel,
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
                onTap: () async {
                  final picked =
                      await _showLocalePicker(context, s, localeOverride);
                  if (!picked.picked) return;

                  // Apply without using BuildContext after async gap.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref
                        .read(localeOverrideProvider.notifier)
                        .setLocaleOverride(picked.value);
                  });
                },
              ),
              const _InnerDivider(),
              _SettingTile(
                icon: Icons.dark_mode_rounded,
                title:
                    _pick3(s, ar: 'المظهر', fr: 'Apparence', en: 'Appearance'),
                subtitle: themeLabel,
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
                onTap: () async {
                  final picked = await _showThemePicker(context, s, themeMode);
                  if (!picked.picked) return;

                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(picked.value);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _GroupCard(
            title: _pick3(s,
                ar: 'التنبيهات', fr: 'Notifications', en: 'Notifications'),
            children: [
              if (authState.isSignedIn && uid.isNotEmpty) ...[
                _SwitchTile(
                  icon: Icons.notifications_active_rounded,
                  title: _pick3(s,
                      ar: 'تفعيل الإشعارات',
                      fr: 'Activer les notifications',
                      en: 'Enable notifications'),
                  subtitle: _pick3(s,
                      ar: 'يمكنك إيقافها من هنا دون الذهاب لإعدادات الهاتف',
                      fr: "Désactivez-les ici sans aller aux réglages du téléphone",
                      en: 'Turn them off here (no need for phone settings)'),
                  value: notifEnabled,
                  onChanged: (v) async {
                    // Persist preference (bootstrap.dart reacts and applies FCM changes).
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .set(
                      {
                        'notificationsEnabled': v,
                        'notificationsEnabledAt': FieldValue.serverTimestamp(),
                      },
                      SetOptions(merge: true),
                    );
                  },
                ),
                const _InnerDivider(),
              ],
              _SettingTile(
                icon: Icons.notifications_none_rounded,
                title: _pick3(s,
                    ar: 'الإشعارات', fr: 'Notifications', en: 'Notifications'),
                subtitle: _pick3(s,
                    ar: 'داخل التطبيق', fr: 'Dans l’app', en: 'In-app'),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
                onTap: () {
                  // IMPORTANT: This app uses go_router (Navigator 2.0).
                  // Using Navigator.push here can crash with:
                  // "!keyReservation.contains(key)".
                  context.push('/notifications');
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _GroupCard(
            title: _pick3(s,
                ar: 'الخصوصية والأمان',
                fr: 'Confidentialité & sécurité',
                en: 'Privacy & security'),
            children: [
              _SettingTile(
                icon: Icons.block_rounded,
                title: _pick3(s, ar: 'المحظورون', fr: 'Bloqués', en: 'Blocked'),
                subtitle: _pick3(s,
                    ar: 'إدارة الباعة المحظورين',
                    fr: 'Gérer les vendeurs bloqués',
                    en: 'Manage blocked sellers'),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
                onTap: () => context.push('/you/blocked'),
              ),
              if (authState.isSignedIn) ...[
                const _InnerDivider(),
                _SwitchTile(
                  icon: Icons.manage_search_rounded,
                  title: _pick3(s,
                      ar: 'إظهار متجري في البحث برقم الهاتف',
                      fr: 'Trouver mon magasin par téléphone',
                      en: 'Find my store by phone'),
                  subtitle: _pick3(s,
                      ar: 'إذا أوقفته، لن تظهر منتجاتك عند البحث برقمك',
                      fr: 'Si désactivé, vos produits ne s\’afficheront pas via votre numéro',
                      en: "If off, your listings won't appear when someone searches your number"),
                  value: ref.watch(sellerPhoneSearchEnabledProvider),
                  onChanged: (v) async {
                    await ref
                        .read(sellerPhoneSearchEnabledProvider.notifier)
                        .setEnabled(v);

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_pick3(s,
                            ar: 'تم حفظ الإعداد. ستُطبّق على نتائج البحث القادمة.',
                            fr: 'Paramètre enregistré. Il sera appliqué aux prochaines recherches.',
                            en: 'Saved. It will apply to future searches.')),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _GroupCard(
            title: _pick3(s,
                ar: 'المساعدة والمحتوى',
                fr: 'Aide & contenu',
                en: 'Help & content'),
            children: [
              _SettingTile(
                icon: Icons.info_rounded,
                title: _pick3(s, ar: 'عن Tki', fr: 'À propos', en: 'About'),
                subtitle: _pick3(s,
                    ar: 'تعرف على التطبيق',
                    fr: 'Découvrir l’app',
                    en: 'Learn about the app'),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
                onTap: () => context.push('/content/about'),
              ),
              const _InnerDivider(),
              _SettingTile(
                icon: Icons.verified_user_rounded,
                title: _pick3(s,
                    ar: 'السياسات والشروط',
                    fr: 'Politiques & conditions',
                    en: 'Policies & terms'),
                subtitle: _pick3(s,
                    ar: 'الخصوصية، الشروط، الإرشادات',
                    fr: 'Confidentialité, conditions…',
                    en: 'Privacy, terms…'),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
                onTap: () => context.push('/content/policies'),
              ),
              const _InnerDivider(),
              _SettingTile(
                icon: Icons.support_agent_rounded,
                title: _pick3(s, ar: 'الدعم', fr: 'Support', en: 'Support'),
                subtitle: _pick3(s,
                    ar: 'واتساب ومساعدة',
                    fr: 'WhatsApp & aide',
                    en: 'WhatsApp & help'),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
                onTap: () => context.push('/you/support'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<_PickResult<Locale?>> _showLocalePicker(
    BuildContext context, AppStrings s, Locale? current) async {
  final result = await showModalBottomSheet<_PickResult<Locale?>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final isRtl = Directionality.of(ctx) == TextDirection.rtl;
      final closeIcon = isRtl ? Icons.close_rounded : Icons.close_rounded;

      final options = <(Locale?, String)>[
        (
          null,
          _pick3(s,
              ar: 'تلقائي (لغة الجهاز)',
              fr: 'Auto (langue du téléphone)',
              en: 'Auto (device)')
        ),
        (const Locale('ar'), 'العربية'),
        (const Locale('fr'), 'Français'),
        (const Locale('en'), 'English'),
      ];

      bool isSelected(Locale? v) {
        if (v == null && current == null) return true;
        if (v == null || current == null) return false;
        return v.languageCode == current.languageCode;
      }

      return _BottomSheetShell(
        title: _pick3(s,
            ar: 'اختر اللغة', fr: 'Choisir la langue', en: 'Choose language'),
        closeIcon: closeIcon,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: options.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final value = options[index].$1;
            final label = options[index].$2;

            return ListTile(
              title: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Icon(
                isSelected(value)
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: isSelected(value)
                    ? Theme.of(ctx).colorScheme.primary
                    : Colors.black38,
              ),
              onTap: () =>
                  Navigator.of(ctx).pop(_PickResult<Locale?>(true, value)),
            );
          },
        ),
      );
    },
  );

  return result ?? const _PickResult<Locale?>(false, null);
}

Future<_PickResult<ThemeMode>> _showThemePicker(
    BuildContext context, AppStrings s, ThemeMode current) async {
  final result = await showModalBottomSheet<_PickResult<ThemeMode>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final isRtl = Directionality.of(ctx) == TextDirection.rtl;
      final closeIcon = isRtl ? Icons.close_rounded : Icons.close_rounded;

      final options = <(ThemeMode, String)>[
        (
          ThemeMode.system,
          _pick3(s,
              ar: 'تلقائي (حسب الجهاز)',
              fr: 'Auto (système)',
              en: 'Auto (system)')
        ),
        (ThemeMode.light, _pick3(s, ar: 'فاتح', fr: 'Clair', en: 'Light')),
        (ThemeMode.dark, _pick3(s, ar: 'داكن', fr: 'Sombre', en: 'Dark')),
      ];

      bool isSelected(ThemeMode v) => v == current;

      return _BottomSheetShell(
        title: _pick3(s,
            ar: 'اختر المظهر',
            fr: "Choisir l’apparence",
            en: 'Choose appearance'),
        closeIcon: closeIcon,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: options.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final value = options[index].$1;
            final label = options[index].$2;

            return ListTile(
              title: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Icon(
                isSelected(value)
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: isSelected(value)
                    ? Theme.of(ctx).colorScheme.primary
                    : Colors.black38,
              ),
              onTap: () =>
                  Navigator.of(ctx).pop(_PickResult<ThemeMode>(true, value)),
            );
          },
        ),
      );
    },
  );

  return result ?? _PickResult<ThemeMode>(false, current);
}

class _BottomSheetShell extends StatelessWidget {
  final String title;
  final IconData closeIcon;
  final Widget child;

  const _BottomSheetShell({
    required this.title,
    required this.closeIcon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(closeIcon),
                  ),
                ],
              ),
            ),
            Flexible(child: child),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _GroupCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 6),
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          ...children,
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.65),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.65),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _InnerDivider extends StatelessWidget {
  const _InnerDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(62, 0, 12, 0),
      child: Divider(
        height: 1,
        color: Theme.of(context).dividerColor.withOpacity(0.35),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;

  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.authState});
  final auth.AuthState authState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final isSignedIn = authState.isSignedIn;

    final displayName = isSignedIn
        ? NameUtils.firstName(
            authState.name,
            fallback: s.isAr
                ? 'حساب'
                : s.isFr
                    ? 'Compte'
                    : 'Account',
          )
        : (s.isAr
            ? 'زائر'
            : s.isFr
                ? 'Invité'
                : 'Guest');

    final subtitle = isSignedIn
        ? (authState.phoneE164 ?? authState.email ?? '')
        : (s.isAr
            ? 'سجّل لتزامن الإعجابات'
            : s.isFr
                ? 'Connectez-vous pour synchroniser'
                : 'Sign in to sync likes');

    final initial = (displayName.trim().isEmpty ? 'T' : displayName.trim()[0])
        .toUpperCase();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor:
                Theme.of(context).colorScheme.primary.withOpacity(0.12),
            child: Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.primary,
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
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.65),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (isSignedIn) ...[
            OutlinedButton.icon(
              onPressed: () => context.push('/account/edit'),
              icon: const Icon(Icons.manage_accounts_outlined),
              label: Text(s.isAr
                  ? 'تعديل'
                  : s.isFr
                      ? 'Modifier'
                      : 'Edit'),
            ),
            const SizedBox(width: 10),
          ],
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
                final t = DateTime.now().millisecondsSinceEpoch.toString();
                context.go('/home?r=logout_$t');
              }
            },
            child: Text(isSignedIn
                ? (s.isAr
                    ? 'خروج'
                    : s.isFr
                        ? 'Sortir'
                        : 'Sign out')
                : (s.isAr
                    ? 'تسجيل'
                    : s.isFr
                        ? 'Connexion'
                        : 'Sign in')),
          ),
        ],
      ),
    );
  }
}
