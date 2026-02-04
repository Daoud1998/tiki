import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tiki/core/state/auth_state.dart';
import 'package:tiki/core/data/country_codes.dart';

/// Auth screen:
/// - SMS OTP (Firebase Phone Auth)
/// - WhatsApp OTP (Cloud Functions + Custom Token) as fallback or alternative
/// - Signup stores profile to Firestore users/{uid}
/// - Third-party buttons are "coming soon"
class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _loginPhoneCtl = TextEditingController();
  final _signupNameCtl = TextEditingController();
  final _signupPhoneCtl = TextEditingController();
  final _signupEmailCtl = TextEditingController();

  String _country = '+222';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginPhoneCtl.dispose();
    _signupNameCtl.dispose();
    _signupPhoneCtl.dispose();
    _signupEmailCtl.dispose();
    super.dispose();
  }

  String tr({required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }

  String get _langCode {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'fr') return 'fr';
    if (code == 'en') return 'en';
    return 'ar';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toastWithAction(String msg,
      {required String actionLabel, required VoidCallback onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
  }

  String _normalizePhone(String raw, {required String country}) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith(country.replaceAll('+', ''))) {
      return '+$digits';
    }
    return '$country$digits';
  }

  Future<String?> _askOtpDialog({required String channel}) async {
    String otp = '';
    final viaWhatsApp = channel == 'whatsapp';

    return showDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final canVerify = otp.trim().length >= 4;

            return AlertDialog(
              title: Text(
                tr(ar: 'أدخل الرمز', fr: 'Entrez le code', en: 'Enter code'),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viaWhatsApp
                        ? tr(
                            ar: 'أرسلنا لك رمز تحقق عبر واتساب.',
                            fr: 'Nous avons envoyé un code via WhatsApp.',
                            en: 'We sent you a code via WhatsApp.',
                          )
                        : tr(
                            ar: 'أرسلنا لك رمز تحقق عبر SMS.',
                            fr: 'Nous avons envoyé un code par SMS.',
                            en: 'We sent you a code via SMS.',
                          ),
                    style: TextStyle(color: cs.onSurface.withAlpha(180)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onChanged: (v) => setLocal(() => otp = v),
                    decoration: InputDecoration(
                      hintText: tr(
                          ar: 'مثال: 123456',
                          fr: 'Ex: 123456',
                          en: 'e.g. 123456'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    viaWhatsApp
                        ? tr(
                            ar: 'تأكد من وصول رسالة واتساب، ثم أدخل الرمز هنا.',
                            fr: 'Vérifiez WhatsApp puis saisissez le code ici.',
                            en: 'Check WhatsApp then enter the code here.',
                          )
                        : tr(
                            ar: 'إن لم يصلك SMS يمكنك استخدام واتساب من الزر في الصفحة.',
                            fr: 'Si le SMS n’arrive pas, utilisez WhatsApp sur la page.',
                            en: 'If SMS fails, use WhatsApp button on the page.',
                          ),
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withAlpha(150)),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(null),
                  child: Text(tr(ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
                ),
                FilledButton(
                  onPressed: canVerify
                      ? () =>
                          Navigator.of(ctx, rootNavigator: true).pop(otp.trim())
                      : null,
                  child: Text(tr(ar: 'تحقق', fr: 'Vérifier', en: 'Verify')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _goNext() async {
    if (!mounted) return;

    if (context.canPop()) {
      context.pop(true);
      return;
    }

    final next = GoRouterState.of(context).uri.queryParameters['next'];
    if (next != null && next.isNotEmpty) {
      context.go(Uri.decodeComponent(next));
    } else {
      context.go('/you');
    }
  }

  void _continueAsGuest() {
    if (!mounted) return;
    // Stay guest and go home.
    context.go('/home');
  }

  String _otpErrorText(String key) {
    switch (key) {
      case 'otp_invalid':
        return tr(ar: 'رمز غير صحيح', fr: 'Code incorrect', en: 'Invalid code');
      case 'otp_expired':
        return tr(
            ar: 'انتهت صلاحية الرمز', fr: 'Code expiré', en: 'Code expired');
      case 'too_many_requests':
        return tr(
            ar: 'طلبات كثيرة جدًا، حاول لاحقًا',
            fr: 'Trop de demandes, réessayez',
            en: 'Too many requests, try later');
      case 'quota_exceeded':
        return tr(
            ar: 'تم تجاوز حد الرسائل اليومي',
            fr: 'Quota dépassé',
            en: 'SMS quota exceeded');
      case 'invalid_phone':
        return tr(
            ar: 'رقم غير صحيح', fr: 'Numéro invalide', en: 'Invalid number');
      case 'network':
        return tr(
            ar: 'تحقق من الإنترنت',
            fr: 'Vérifiez Internet',
            en: 'Check internet');
      case 'otp_not_requested':
        return tr(
            ar: 'اطلب الرمز أولاً',
            fr: 'Demandez le code d’abord',
            en: 'Request code first');
      case 'functions_not_configured':
        return tr(
          ar: 'واتساب غير مهيأ بعد (تأكد من إعداد Functions و .env)',
          fr: "WhatsApp n’est pas configuré (Functions/.env)",
          en: 'WhatsApp not configured (Functions/.env)',
        );
      default:
        return tr(ar: 'حدث خطأ', fr: 'Erreur', en: 'Something went wrong');
    }
  }

  String _sendOtpErrorText(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return tr(
            ar: 'رقم غير صحيح', fr: 'Numéro invalide', en: 'Invalid number');
      case 'too-many-requests':
        return tr(
            ar: 'طلبات كثيرة جدًا، حاول لاحقًا',
            fr: 'Trop de demandes, réessayez',
            en: 'Too many requests, try later');
      case 'quota-exceeded':
        return tr(
            ar: 'تم تجاوز حد الرسائل اليومي',
            fr: 'Quota dépassé',
            en: 'SMS quota exceeded');
      case 'operation-not-allowed':
        return tr(
            ar: 'فعّل تسجيل الدخول بالهاتف في Firebase',
            fr: "Activez l’authentification par téléphone sur Firebase",
            en: 'Enable Phone sign-in in Firebase');
      case 'captcha-check-failed':
        return tr(
            ar: 'تعذر التحقق (Captcha)، أعد المحاولة',
            fr: 'Échec du captcha, réessayez',
            en: 'Captcha failed, try again');
      case 'network-request-failed':
        return tr(
            ar: 'تحقق من الإنترنت',
            fr: 'Vérifiez Internet',
            en: 'Check internet');
      case 'invalid-app-credential':
      case 'app-not-authorized':
        return tr(
            ar: 'التطبيق غير مخوّل: تأكد من SHA وباقة التطبيق',
            fr: "App non autorisée: vérifiez SHA et package",
            en: 'App not authorized: check SHA & package name');
      default:
        return tr(
            ar: 'تعذر إرسال الرمز عبر SMS',
            fr: "Impossible d’envoyer le code par SMS",
            en: 'Failed to send SMS code');
    }
  }

  Future<void> _loginWithPhoneOtp() async {
    final phone = _normalizePhone(_loginPhoneCtl.text, country: _country);
    if (phone.isEmpty || phone.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
      _toast(
          tr(ar: 'رقم غير صحيح', fr: 'Numéro invalide', en: 'Invalid number'));
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);

    try {
      final status = await ref
          .read(authControllerProvider.notifier)
          .requestPhoneOtp(phone);

      if (!mounted) return;

      if (ref.read(authControllerProvider).isSignedIn || status == 'auto') {
        await _goNext();
        return;
      }

      _toast(tr(ar: 'تم إرسال الرمز', fr: 'Code envoyé', en: 'Code sent'));

      final entered = await _askOtpDialog(channel: 'sms');
      if (!mounted) return;
      if (entered == null || entered.isEmpty) return;

      final res = await ref.read(authControllerProvider.notifier).signInWithOtp(
            phoneE164: phone,
            code: entered,
          );

      if (!mounted) return;

      if (!res.ok) {
        _toast(_otpErrorText(res.message ?? 'unknown'));
        return;
      }

      await _goNext();
    } catch (e) {
      if (!mounted) return;

      if (e is FirebaseAuthException) {
        debugPrint('OTP send failed: ${e.code} ${e.message}');
        _toastWithAction(
          _sendOtpErrorText(e.code),
          actionLabel: tr(ar: 'واتساب', fr: 'WhatsApp', en: 'WhatsApp'),
          onAction: () => _loginWithWhatsAppOtp(),
        );
      } else {
        debugPrint('OTP send failed: $e');
        _toastWithAction(
          tr(
              ar: 'تعذر إرسال الرمز عبر SMS',
              fr: "Impossible d’envoyer le code",
              en: 'Failed to send code'),
          actionLabel: tr(ar: 'واتساب', fr: 'WhatsApp', en: 'WhatsApp'),
          onAction: () => _loginWithWhatsAppOtp(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithWhatsAppOtp() async {
    final phone = _normalizePhone(_loginPhoneCtl.text, country: _country);
    if (phone.isEmpty || phone.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
      _toast(
          tr(ar: 'رقم غير صحيح', fr: 'Numéro invalide', en: 'Invalid number'));
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);

    try {
      final send =
          await ref.read(authControllerProvider.notifier).requestWhatsAppOtp(
                phoneE164: phone,
                languageCode: _langCode,
              );

      if (!mounted) return;

      if (!send.ok) {
        _toast(_otpErrorText(send.message ?? 'unknown'));
        return;
      }

      _toast(tr(
          ar: 'تم إرسال الرمز عبر واتساب',
          fr: 'Code WhatsApp envoyé',
          en: 'WhatsApp code sent'));

      final entered = await _askOtpDialog(channel: 'whatsapp');
      if (!mounted) return;
      if (entered == null || entered.isEmpty) return;

      final res =
          await ref.read(authControllerProvider.notifier).signInWithWhatsAppOtp(
                phoneE164: phone,
                code: entered,
              );

      if (!mounted) return;

      if (!res.ok) {
        _toast(_otpErrorText(res.message ?? 'unknown'));
        return;
      }

      await _goNext();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signupWithPhoneOtp() async {
    final name = _signupNameCtl.text.trim();
    final phone = _normalizePhone(_signupPhoneCtl.text, country: _country);
    final email = _signupEmailCtl.text.trim();

    if (name.isEmpty) {
      _toast(
          tr(ar: 'أدخل اسمك', fr: 'Entrez votre nom', en: 'Enter your name'));
      return;
    }
    if (phone.isEmpty || phone.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
      _toast(
          tr(ar: 'رقم غير صحيح', fr: 'Numéro invalide', en: 'Invalid number'));
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);

    try {
      final status = await ref
          .read(authControllerProvider.notifier)
          .requestPhoneOtp(phone);

      if (!mounted) return;

      if (ref.read(authControllerProvider).isSignedIn || status == 'auto') {
        await ref.read(authControllerProvider.notifier).updateProfile(
              name: name,
              email: email.isEmpty ? null : email,
            );
        if (!mounted) return;
        await _goNext();
        return;
      }

      _toast(tr(ar: 'تم إرسال الرمز', fr: 'Code envoyé', en: 'Code sent'));

      final entered = await _askOtpDialog(channel: 'sms');
      if (!mounted) return;
      if (entered == null || entered.isEmpty) return;

      final res =
          await ref.read(authControllerProvider.notifier).createAccountWithOtp(
                name: name,
                phoneE164: phone,
                code: entered,
                email: email.isEmpty ? null : email,
              );

      if (!mounted) return;

      if (!res.ok) {
        _toast(_otpErrorText(res.message ?? 'unknown'));
        return;
      }

      await _goNext();
    } catch (e) {
      if (!mounted) return;

      if (e is FirebaseAuthException) {
        debugPrint('OTP send failed: ${e.code} ${e.message}');
        _toastWithAction(
          _sendOtpErrorText(e.code),
          actionLabel: tr(ar: 'واتساب', fr: 'WhatsApp', en: 'WhatsApp'),
          onAction: () => _signupWithWhatsAppOtp(),
        );
      } else {
        debugPrint('OTP send failed: $e');
        _toastWithAction(
          tr(
              ar: 'تعذر إرسال الرمز عبر SMS',
              fr: "Impossible d’envoyer le code",
              en: 'Failed to send code'),
          actionLabel: tr(ar: 'واتساب', fr: 'WhatsApp', en: 'WhatsApp'),
          onAction: () => _signupWithWhatsAppOtp(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signupWithWhatsAppOtp() async {
    final name = _signupNameCtl.text.trim();
    final phone = _normalizePhone(_signupPhoneCtl.text, country: _country);
    final email = _signupEmailCtl.text.trim();

    if (name.isEmpty) {
      _toast(
          tr(ar: 'أدخل اسمك', fr: 'Entrez votre nom', en: 'Enter your name'));
      return;
    }
    if (phone.isEmpty || phone.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
      _toast(
          tr(ar: 'رقم غير صحيح', fr: 'Numéro invalide', en: 'Invalid number'));
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);

    try {
      final send =
          await ref.read(authControllerProvider.notifier).requestWhatsAppOtp(
                phoneE164: phone,
                languageCode: _langCode,
              );

      if (!mounted) return;

      if (!send.ok) {
        _toast(_otpErrorText(send.message ?? 'unknown'));
        return;
      }

      _toast(tr(
          ar: 'تم إرسال الرمز عبر واتساب',
          fr: 'Code WhatsApp envoyé',
          en: 'WhatsApp code sent'));

      final entered = await _askOtpDialog(channel: 'whatsapp');
      if (!mounted) return;
      if (entered == null || entered.isEmpty) return;

      final res = await ref
          .read(authControllerProvider.notifier)
          .createAccountWithWhatsAppOtp(
            name: name,
            phoneE164: phone,
            code: entered,
            email: email.isEmpty ? null : email,
          );

      if (!mounted) return;

      if (!res.ok) {
        _toast(_otpErrorText(res.message ?? 'unknown'));
        return;
      }

      await _goNext();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _thirdParty(AuthProviderKind provider) async {
    final res =
        await ref.read(authControllerProvider.notifier).signInThirdPartyMock(
              provider: provider,
              displayName: provider.name,
            );

    if (!mounted) return;

    if (!res.ok) {
      _toast(tr(ar: 'قريبًا', fr: 'Bientôt', en: 'Coming soon'));
      return;
    }

    await _goNext();
  }

  Future<void> _openCountryPicker() async {
    const frequentIso2 = ['MR', 'FR', 'ES', 'DE', 'NL', 'BE'];
    final frequent =
        kCountryCodes.where((c) => frequentIso2.contains(c.iso2)).toList();
    final others =
        kCountryCodes.where((c) => !frequentIso2.contains(c.iso2)).toList();

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final locale = Localizations.localeOf(ctx);

        return SafeArea(
          child: ListView.separated(
            itemCount: frequent.length + 1 + others.length,
            separatorBuilder: (_, __) =>
                Divider(color: cs.outline.withAlpha(90)),
            itemBuilder: (ctx, i) {
              if (i < frequent.length) {
                final c = frequent[i];
                return ListTile(
                  title: Text('${c.flagEmoji} ${c.nameFor(locale)}'),
                  trailing: Text(c.dialCode),
                  onTap: () => Navigator.of(ctx).pop(c.dialCode),
                );
              }

              if (i == frequent.length) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    tr(
                        ar: 'دول أخرى',
                        fr: 'Autres pays',
                        en: 'Other countries'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withAlpha(200),
                    ),
                  ),
                );
              }

              final c = others[i - frequent.length - 1];
              return ListTile(
                title: Text('${c.flagEmoji} ${c.nameFor(locale)}'),
                trailing: Text(c.dialCode),
                onTap: () => Navigator.of(ctx).pop(c.dialCode),
              );
            },
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected != null && selected.isNotEmpty) {
      setState(() => _country = selected);
    }
  }

  Widget _countryChip(ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: _busy ? null : _openCountryPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outline.withAlpha(120)),
          color: cs.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_country, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Icon(Icons.expand_more,
                size: 18, color: cs.onSurface.withAlpha(180)),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: Theme.of(context).colorScheme.outline.withAlpha(110)),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: child,
    );
  }

  Widget _thirdPartyRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                _busy ? null : () => _thirdParty(AuthProviderKind.google),
            icon: const Icon(Icons.g_mobiledata),
            label: Text(tr(ar: 'Google', fr: 'Google', en: 'Google')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                _busy ? null : () => _thirdParty(AuthProviderKind.facebook),
            icon: const Icon(Icons.facebook),
            label: Text(tr(ar: 'Facebook', fr: 'Facebook', en: 'Facebook')),
          ),
        ),
      ],
    );
  }

  Widget _loginTab(ColorScheme cs) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(ar: 'تسجيل الدخول', fr: 'Connexion', en: 'Login'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _countryChip(cs),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _loginPhoneCtl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText:
                        tr(ar: 'رقم الهاتف', fr: 'Téléphone', en: 'Phone'),
                    hintText: tr(
                        ar: 'مثال: 22123456',
                        fr: 'Ex: 22123456',
                        en: 'e.g. 22123456'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _loginWithPhoneOtp,
            icon: const Icon(Icons.sms),
            label: Text(
                tr(ar: 'إرسال عبر SMS', fr: 'Envoyer (SMS)', en: 'Send (SMS)')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _loginWithWhatsAppOtp,
            icon: const Icon(Icons.chat),
            label: Text(tr(
                ar: 'إرسال عبر واتساب',
                fr: 'Envoyer (WhatsApp)',
                en: 'Send (WhatsApp)')),
          ),
          const SizedBox(height: 18),
          Center(child: Text(tr(ar: 'أو عبر', fr: 'Ou via', en: 'Or via'))),
          const SizedBox(height: 10),
          _thirdPartyRow(),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.play_circle_outline),
            label: Text(tr(
                ar: 'TikTok (قريبًا)',
                fr: 'TikTok (bientôt)',
                en: 'TikTok (soon)')),
          ),
        ],
      ),
    );
  }

  Widget _signupTab(ColorScheme cs) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(ar: 'إنشاء حساب', fr: 'Créer un compte', en: 'Create account'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _signupNameCtl,
            decoration: InputDecoration(
              labelText: tr(ar: 'الاسم', fr: 'Nom', en: 'Name'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _countryChip(cs),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _signupPhoneCtl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText:
                        tr(ar: 'رقم الهاتف', fr: 'Téléphone', en: 'Phone'),
                    hintText: tr(
                        ar: 'مثال: 22123456',
                        fr: 'Ex: 22123456',
                        en: 'e.g. 22123456'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _signupEmailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: tr(
                  ar: 'البريد (اختياري)',
                  fr: 'Email (optionnel)',
                  en: 'Email (optional)'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _signupWithPhoneOtp,
            icon: const Icon(Icons.sms),
            label: Text(
                tr(ar: 'إرسال عبر SMS', fr: 'Envoyer (SMS)', en: 'Send (SMS)')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _signupWithWhatsAppOtp,
            icon: const Icon(Icons.chat),
            label: Text(tr(
                ar: 'إرسال عبر واتساب',
                fr: 'Envoyer (WhatsApp)',
                en: 'Send (WhatsApp)')),
          ),
          const SizedBox(height: 18),
          Center(child: Text(tr(ar: 'أو عبر', fr: 'Ou via', en: 'Or via'))),
          const SizedBox(height: 10),
          _thirdPartyRow(),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.play_circle_outline),
            label: Text(tr(
                ar: 'TikTok (قريبًا)',
                fr: 'TikTok (bientôt)',
                en: 'TikTok (soon)')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(ar: 'الحساب', fr: 'Compte', en: 'Account')),
        actions: [
          TextButton(
            onPressed: _busy ? null : _continueAsGuest,
            child: Text(tr(ar: 'تصفح كضيف', fr: 'Invité', en: 'Guest')),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: tr(ar: 'دخول', fr: 'Connexion', en: 'Login')),
                  Tab(text: tr(ar: 'تسجيل', fr: 'Inscription', en: 'Signup')),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    // Login tab (scrollable to avoid bottom overflow)
                    LayoutBuilder(
                      builder: (ctx, c) {
                        return SingleChildScrollView(
                          padding: EdgeInsets.only(
                              bottom:
                                  MediaQuery.of(ctx).viewInsets.bottom + 18),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: c.maxHeight),
                            child: IntrinsicHeight(child: _loginTab(cs)),
                          ),
                        );
                      },
                    ),
                    // Signup tab (scrollable to avoid bottom overflow)
                    LayoutBuilder(
                      builder: (ctx, c) {
                        return SingleChildScrollView(
                          padding: EdgeInsets.only(
                              bottom:
                                  MediaQuery.of(ctx).viewInsets.bottom + 18),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: c.maxHeight),
                            child: IntrinsicHeight(child: _signupTab(cs)),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  ar: 'بالضغط على المتابعة، أنت توافق على الشروط وسياسة الخصوصية.',
                  fr: 'En continuant, vous acceptez les Conditions et la Confidentialité.',
                  en: 'By continuing, you agree to Terms & Privacy.',
                ),
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150)),
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: () => context.push('/content/policies/terms'),
                    child:
                        Text(tr(ar: 'الشروط', fr: 'Conditions', en: 'Terms')),
                  ),
                  TextButton(
                    onPressed: () => context.push('/content/policies/privacy'),
                    child: Text(tr(
                        ar: 'الخصوصية', fr: 'Confidentialité', en: 'Privacy')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
