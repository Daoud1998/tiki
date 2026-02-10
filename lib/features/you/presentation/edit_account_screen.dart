import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tiki/app/localization/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tiki/core/data/ma_catalog.dart' show L10n3, maWilayas;
import 'package:tiki/core/state/auth_state.dart' as auth;

import '../../kyc/data/kyc_settings_repository.dart';
import '../../kyc/domain/kyc_models.dart';

/// Edit account screen (Firestore-backed profile via AuthController.updateProfile):
/// - Works for Phone OTP accounts (no in-app password)
/// - Saves displayName + optional email to Firestore users/{uid}
///
/// Mauritania-first additions:
/// - Optional wilaya preference saved to users/{uid}.wilayaId
/// - Clear explanation why phone number isn't editable + support shortcut
class EditAccountScreen extends ConsumerStatefulWidget {
  const EditAccountScreen({super.key});

  @override
  ConsumerState<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends ConsumerState<EditAccountScreen> {
  final _nameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  bool _prefilled = false;

  bool _saving = false;

  // Extra profile fields stored directly in Firestore.
  bool _extraLoaded = false;
  bool _extraLoading = false;
  String? _wilayaId;

  static const _nouakchott =
      L10n3(ar: 'نواكشوط', fr: 'Nouakchott', en: 'Nouakchott');

  Future<void> _openHelpChangeNumber(AppStrings s) async {
    // Prefer the admin-controlled WhatsApp number from `app_settings/kyc`.
    final uiAsync = ref.read(kycVerificationUiSettingsProvider);
    final ui = uiAsync.asData?.value ?? KycVerificationUiSettings.defaults();

    // If WhatsApp verification is disabled by Admin, fallback to the support page.
    if (!ui.allowWhatsApp) {
      if (mounted) context.go('/you/support');
      return;
    }

    final a = ref.read(auth.authControllerProvider);

    final uid = (a.userId ?? '').trim();
    final name = (a.name ?? _nameCtl.text).trim();
    final phoneNow = (a.phoneE164 ?? '').trim();

    final message = s.isAr
        ? 'السلام عليكم، أريد تغيير رقم الهاتف لحسابي في تيكي.\n'
            'UID: $uid\n'
            'الاسم: $name\n'
            'رقمي الحالي: $phoneNow\n'
            'الرقم الجديد: (اكتب الرقم هنا)\n'
            'شكراً.'
        : s.isFr
            ? 'Bonjour, je souhaite changer le numéro de téléphone de mon compte Tikki.\n'
                'UID: $uid\n'
                'Nom: $name\n'
                'Numéro actuel: $phoneNow\n'
                'Nouveau numéro: (écrivez le numéro ici)\n'
                'Merci.'
            : 'Hi, I want to change the phone number for my Tikki account.\n'
                'UID: $uid\n'
                'Name: $name\n'
                'Current phone: $phoneNow\n'
                'New phone: (type the number here)\n'
                'Thanks.';

    final phone = ui.whatsAppNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final digits = phone.replaceAll('+', '').trim();
    if (digits.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.isAr
                ? 'رقم واتساب الدعم غير مضبوط'
                : s.isFr
                    ? 'Numéro WhatsApp du support manquant'
                    : 'Support WhatsApp number is missing'),
          ),
        );
        context.go('/you/support');
      }
      return;
    }

    final uri =
        Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.isAr
                ? 'تعذر فتح واتساب'
                : s.isFr
                    ? "Impossible d'ouvrir WhatsApp"
                    : 'Cannot open WhatsApp'),
          ),
        );
        context.go('/you/support');
      }
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  void _prefill(auth.AuthState a) {
    if (_prefilled) return;
    _prefilled = true;
    _nameCtl.text = (a.name ?? '').trim();
    _emailCtl.text = (a.email ?? '').trim();
  }

  Future<void> _loadExtra(String uid) async {
    if (_extraLoaded || _extraLoading) return;
    _extraLoading = true;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!snap.exists) {
        _extraLoaded = true;
        return;
      }
      final data = snap.data() ?? <String, dynamic>{};

      // Accept a few legacy keys if any exist.
      final wid =
          (data['wilayaId'] ?? data['wilaya_id'] ?? data['wilaya'] ?? '')
              .toString()
              .trim();
      if (wid.isNotEmpty) {
        _wilayaId = wid;
      }

      _extraLoaded = true;
    } catch (_) {
      // Non-fatal.
      _extraLoaded = true;
    } finally {
      _extraLoading = false;
      if (mounted) setState(() {});
    }
  }

  List<_WilayaOption> _wilayaOptions(BuildContext context) {
    final locale = Localizations.localeOf(context);

    final out = <_WilayaOption>[
      _WilayaOption('nouakchott', _nouakchott.ofLocale(locale)),
    ];

    for (final w in maWilayas) {
      // Collapse Nouakchott sub-wilayas into one umbrella.
      if (w.id.startsWith('nouakchott_')) continue;
      out.add(_WilayaOption(w.id, w.name.ofLocale(locale)));
    }

    return out;
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final a = ref.read(auth.authControllerProvider);

    if (!a.isSignedIn) {
      context.push('/auth?next=${Uri.encodeComponent('/account/edit')}');
      return;
    }

    final name = _nameCtl.text.trim();
    final email = _emailCtl.text.trim(); // optional

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isAr
                ? 'أدخل الاسم'
                : s.isFr
                    ? 'Entrez le nom'
                    : 'Enter a name',
          ),
        ),
      );
      return;
    }

    if (_saving) return;
    setState(() => _saving = true);

    // Pass '' to clear email in Firestore; pass a value to set.
    final err =
        await ref.read(auth.authControllerProvider.notifier).updateProfile(
              name: name,
              email: email.isEmpty ? '' : email,
            );

    if (!mounted) return;

    if (err == null) {
      // Save wilaya preference directly in Firestore.
      try {
        final uid = (a.userId ?? FirebaseAuth.instance.currentUser?.uid);
        if (uid != null && uid.isNotEmpty) {
          final refDoc =
              FirebaseFirestore.instance.collection('users').doc(uid);
          await refDoc.set(
            {
              'wilayaId': (_wilayaId ?? '').trim().isEmpty
                  ? FieldValue.delete()
                  : (_wilayaId ?? '').trim(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      } catch (_) {
        // Ignore; not critical for account save.
      }
    }

    setState(() => _saving = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isAr
                ? 'تعذر حفظ الحساب'
                : s.isFr
                    ? 'Impossible d’enregistrer'
                    : 'Could not save',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          s.isAr
              ? 'تم حفظ الحساب ✅'
              : s.isFr
                  ? 'Enregistré ✅'
                  : 'Saved ✅',
        ),
      ),
    );

    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go('/you');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final a = ref.watch(auth.authControllerProvider);

    if (a.isSignedIn) {
      _prefill(a);

      // Load extra profile fields (wilaya) once.
      final uid =
          ((a.userId ?? FirebaseAuth.instance.currentUser?.uid) ?? '').trim();
      if (uid.isNotEmpty && !_extraLoaded && !_extraLoading) {
        // Avoid setState during build.
        Future.microtask(() => _loadExtra(uid));
      }
    }

    final phone = (a.phoneE164 ?? '').trim();
    String ltr(String v) => '\u2066$v\u2069';

    final wilayaOptions = _wilayaOptions(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.isAr
              ? 'تعديل الحساب'
              : s.isFr
                  ? 'Modifier le compte'
                  : 'Edit account',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        children: [
          if (!a.isSignedIn)
            _GuestNote(
              title: s.isAr
                  ? 'أنت الآن زائر'
                  : s.isFr
                      ? 'Vous êtes invité'
                      : 'You are a guest',
              subtitle: s.isAr
                  ? 'سجّل الدخول لتعديل حسابك وحفظ بياناتك.'
                  : s.isFr
                      ? 'Connectez-vous pour modifier et sauvegarder.'
                      : 'Sign in to edit and save your account.',
              onTap: () => context
                  .push('/auth?next=${Uri.encodeComponent('/account/edit')}'),
              buttonText: s.isAr
                  ? 'تسجيل الدخول'
                  : s.isFr
                      ? 'Connexion'
                      : 'Sign in',
            ),
          const SizedBox(height: 12),
          _Field(
            label: s.isAr
                ? 'الاسم'
                : s.isFr
                    ? 'Nom'
                    : 'Name',
            controller: _nameCtl,
            enabled: a.isSignedIn && !_saving,
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 12),
          _Field(
            label: s.isAr
                ? 'البريد (اختياري)'
                : s.isFr
                    ? 'Email (optionnel)'
                    : 'Email (optional)',
            controller: _emailCtl,
            enabled: a.isSignedIn && !_saving,
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),

          // Optional wilaya preference
          DropdownButtonFormField<String>(
            value: (_wilayaId ?? '').trim().isEmpty ? null : _wilayaId,
            items: wilayaOptions
                .map(
                  (o) => DropdownMenuItem<String>(
                    value: o.id,
                    child: Text(o.label),
                  ),
                )
                .toList(growable: false),
            onChanged: a.isSignedIn && !_saving
                ? (v) => setState(() => _wilayaId = v)
                : null,
            decoration: InputDecoration(
              labelText: s.isAr
                  ? 'الولاية (اختياري)'
                  : s.isFr
                      ? 'Wilaya (optionnel)'
                      : 'Wilaya (optional)',
              prefixIcon: const Icon(Icons.location_on_outlined),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),

          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.phone_outlined),
            title: Text(
              s.isAr
                  ? 'الهاتف'
                  : s.isFr
                      ? 'Téléphone'
                      : 'Phone',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ltr(phone.isEmpty ? '—' : phone)),
                const SizedBox(height: 6),
                Text(
                  s.isAr
                      ? 'تغيير رقم الهاتف يحتاج تحقق جديد لحماية الحساب.'
                      : s.isFr
                          ? 'Changer de numéro nécessite une nouvelle vérification pour protéger le compte.'
                          : 'Changing phone requires re-verification to protect the account.',
                  style: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onSurface.withAlpha(170),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: a.isSignedIn
                ? Text(
                    s.isAr
                        ? 'غير قابل للتعديل'
                        : s.isFr
                            ? 'Non modifiable'
                            : 'Not editable',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(150),
                    ),
                  )
                : null,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _openHelpChangeNumber(s),
              icon: const Icon(Icons.support_agent_outlined),
              label: Text(
                s.isAr
                    ? 'مساعدة / تغيير الرقم'
                    : s.isFr
                        ? 'Aide / changer de numéro'
                        : 'Help / change number',
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Password note (Phone OTP accounts have no in-app password).
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withAlpha(110),
              border: Border.all(
                color:
                    Theme.of(context).colorScheme.outlineVariant.withAlpha(150),
              ),
            ),
            child: Text(
              s.isAr
                  ? 'ملاحظة: هذا الحساب يستخدم تسجيل الدخول عبر الهاتف (OTP)، لذلك لا توجد كلمة مرور داخل التطبيق.'
                  : s.isFr
                      ? "Note: ce compte utilise l’OTP par téléphone, donc il n’y a pas de mot de passe dans l’application."
                      : 'Note: This account uses phone OTP, so there is no in-app password.',
              style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withAlpha(190)),
            ),
          ),

          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: a.isSignedIn && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              s.isAr
                  ? 'حفظ'
                  : s.isFr
                      ? 'Enregistrer'
                      : 'Save',
            ),
          ),
        ],
      ),
    );
  }
}

class _WilayaOption {
  const _WilayaOption(this.id, this.label);
  final String id;
  final String label;
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: cs.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _GuestNote extends StatelessWidget {
  const _GuestNote({
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withAlpha(160)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_outline_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: cs.onSurface.withAlpha(180)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(onPressed: onTap, child: Text(buttonText)),
        ],
      ),
    );
  }
}
