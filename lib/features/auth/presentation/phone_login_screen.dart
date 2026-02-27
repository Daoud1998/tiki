import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/data/country_codes.dart';
import '../../../core/config/support_config.dart';
import '../../../core/state/auth_state.dart';
import 'reset_password_screen.dart';

/// Auth screen (requested UX):
/// - Login: Phone + Password
/// - Signup: Name + Phone + Password (+ confirm)
/// - Keep country picker (dial code) to avoid wrong keyboard prefix.
/// - Third-party buttons (Google now; Apple can be wired later)
///
/// Notes:
/// - If your AuthController implements phone+password methods, this UI will call them.
/// - If not available, signup can fall back to OTP then link password (when implemented).
class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _loginPhoneCtl = TextEditingController();
  final _loginPassCtl = TextEditingController();

  final _signupNameCtl = TextEditingController();
  final _signupPhoneCtl = TextEditingController();
  final _signupPassCtl = TextEditingController();
  final _signupPass2Ctl = TextEditingController();

  String _country = '+222';
  bool _busy = false;
  bool _loginUsePassword = true; // password-only login (OTP only for reset)

  // Login mode: OTP by default, password only if enabled for this phone.
  // Requested UX: password-only login. OTP is used only for "Forgot password".
  bool _usePassword = true;
  bool _passwordEligible = false;
  Timer? _pwCheckDebounce;

  bool _loginPassObscure = true;
  bool _signupPassObscure = true;
  bool _signupPass2Obscure = true;

  @override
  void initState() {
    super.initState();
    _loginPhoneCtl.addListener(_onLoginPhoneChanged);
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pwCheckDebounce?.cancel();
    _loginPhoneCtl.removeListener(_onLoginPhoneChanged);
    _tabs.dispose();
    _loginPhoneCtl.dispose();
    _loginPassCtl.dispose();
    _signupNameCtl.dispose();
    _signupPhoneCtl.dispose();
    _signupPassCtl.dispose();
    _signupPass2Ctl.dispose();
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

  CountryCode get _selectedCountry {
    return kCountryCodes.firstWhere(
      (c) => c.dialCode == _country,
      orElse: () => kCountryCodes.first,
    );
  }

  String _normalizePhone(String raw, {required String country}) {
    final s = raw.trim();
    if (s.isEmpty) return '';

    // UI currently restricts to digits-only, but keep this robust for pasted values.
    if (s.startsWith('+')) {
      final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.isEmpty ? '' : '+$digits';
    }
    if (s.startsWith('00')) {
      final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length <= 2) return '';
      return '+${digits.substring(2)}';
    }

    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    final cc = country.replaceAll('+', '');

    // If the user pasted the full number without '+', keep it ONLY if it looks like
    // it contains both country code + national number (avoid Mauritania local numbers
    // that may start with 222).
    if (digits.length >= 11 && digits.startsWith(cc)) {
      return '+$digits';
    }

    // Otherwise treat as local digits and prepend the selected country code.
    return '$country$digits';
  }

  String? _normalizeAndValidatePhone(String raw) {
    final phone = _normalizePhone(raw, country: _country);
    if (phone.isEmpty) return null;

    final allDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final cc = _country.replaceAll('+', '');
    if (!allDigits.startsWith(cc) || allDigits.length <= cc.length) return null;

    final local = allDigits.substring(cc.length);

    if (_country == '+222') {
      // Mauritania: exactly 8 national digits.
      if (local.length != 8) return null;
    } else {
      // Generic fallback for other countries.
      if (local.length < 4) return null;
      if (allDigits.length > 15) return null; // E.164 max
    }

    return phone;
  }

  String _invalidPhoneMsg() {
    if (_country == '+222') {
      return tr(
        ar: 'اكتب رقمًا صحيحًا (8 أرقام) بدون +222',
        fr: 'Numéro invalide (8 chiffres, sans +222)',
        en: 'Invalid number (8 digits, without +222)',
      );
    }
    return tr(ar: 'رقم غير صحيح', fr: 'Numéro invalide', en: 'Invalid number');
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
    context.go('/home');
  }

  // ---------------------------------------------------------------------------
  // Country picker
  // ---------------------------------------------------------------------------

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

  Widget _countrySuffix(ColorScheme cs) {
    final c = _selectedCountry;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : _openCountryPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withAlpha(120)),
            color: cs.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.flagEmoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                c.dialCode,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more,
                  size: 16, color: cs.onSurface.withAlpha(160)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OTP helpers (still available as fallback)
  // ---------------------------------------------------------------------------

  String _otpErrorText(String key) {
    // Firebase custom-token sign-in errors (show real auth code)
    if (key.startsWith('auth_')) {
      final c = key.substring(5);
      return tr(
        ar: 'تعذر إكمال تسجيل الدخول ($c)',
        fr: "Impossible de terminer la connexion ($c)",
        en: 'Could not complete sign-in ($c)',
      );
    }

    // Twilio send/verify failures may include a numeric error code suffix.
    String? _extractTwilioCode(String k) {
      final m = RegExp(r'_(\d{4,6})\$').firstMatch(k);
      return m?.group(1);
    }

    if (key.startsWith('twilio_send_failed')) {
      final c = _extractTwilioCode(key);

      if (c == '60410') {
        return tr(
          ar: 'Twilio حظر الإرسال مؤقتًا لهذا البريفكس (~12 ساعة) بسبب Fraud Guard. جرّب لاحقًا أو Unblock من Twilio Console.',
          fr: "Twilio a bloqué temporairement ce préfixe (~12h) via Fraud Guard. Réessayez plus tard ou débloquez via Console.",
          en: 'Twilio temporarily blocked this prefix (~12h) via Fraud Guard. Try later or unblock in Twilio Console.',
        );
      }
      if (c == '21408') {
        return tr(
          ar: 'الإرسال محجوب بسبب Geo Permissions في Twilio. فعّل الدولة في Messaging/Verify Geo Permissions.',
          fr: "Envoi bloqué par Geo Permissions Twilio. Activez le pays dans Messaging/Verify Geo Permissions.",
          en: 'Blocked by Twilio Geo Permissions. Enable the country in Messaging/Verify Geo Permissions.',
        );
      }
      if (c == '21608') {
        return tr(
          ar: 'حساب Twilio Trial: الرقم غير Verified داخل Twilio. وثّق الرقم أو قم بترقية الحساب.',
          fr: "Compte Twilio Trial : numéro non vérifié. Vérifiez-le ou upgradez le compte.",
          en: 'Twilio Trial: number not verified. Verify it or upgrade the account.',
        );
      }
      if (c == '20003') {
        return tr(
          ar: 'بيانات Twilio غير صحيحة (SID/TOKEN). تحقق من env في Functions وأعد النشر.',
          fr: "Identifiants Twilio invalides (SID/TOKEN). Vérifiez env Functions et redeployez.",
          en: 'Invalid Twilio credentials (SID/TOKEN). Check Functions env and redeploy.',
        );
      }

      return tr(
        ar: 'فشل إرسال الرمز عبر Twilio${c != null ? " (code: $c)" : ""}. راجع Twilio (Geo permissions/الرصيد/Verify).',
        fr: "Échec d’envoi Twilio${c != null ? " (code: $c)" : ""}. Vérifiez Twilio (Geo permissions/crédit/Verify).",
        en: 'Failed to send code via Twilio${c != null ? " (code: $c)" : ""}. Check Twilio (Geo permissions/balance/Verify).',
      );
    }

    if (key.startsWith('twilio_verify_failed')) {
      final c = _extractTwilioCode(key);
      return tr(
        ar: 'فشل التحقق من الرمز عبر Twilio${c != null ? " (code: $c)" : ""}. تأكد من صحة الرمز وحاول مرة أخرى.',
        fr: "Échec de vérification Twilio${c != null ? " (code: $c)" : ""}. Vérifiez le code et réessayez.",
        en: 'Failed to verify code via Twilio${c != null ? " (code: $c)" : ""}. Check the code and retry.',
      );
    }

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
      case 'twilio_not_configured':
        return tr(
          ar: 'Twilio غير مهيأ بعد (تأكد من functions/.env ثم انشر Functions)',
          fr: "Twilio n’est pas configuré (functions/.env)",
          en: 'Twilio not configured (functions/.env)',
        );
      case 'functions_not_configured':
        return tr(
          ar: 'OTP غير مهيأ بعد (تأكد من functions/.env ثم انشر Functions)',
          fr: "OTP n’est pas configuré (functions/.env)",
          en: 'OTP not configured (functions/.env)',
        );
      case 'auth_lookup_failed':
        return tr(
          ar: 'تم التحقق من الرمز لكن فشل إنشاء/جلب المستخدم في Firebase. راجع Logs للـ Functions.',
          fr: "Code validé mais échec Firebase user. Vérifiez les logs Functions.",
          en: 'OTP verified but failed to create/lookup Firebase user. Check Functions logs.',
        );
      case 'functions_not_found':
        return tr(
          ar: 'الدالة غير موجودة (غير منشورة أو region غير صحيح).',
          fr: "Fonction introuvable (non déployée ou mauvaise région).",
          en: 'Function not found (not deployed or wrong region).',
        );
      case 'functions_internal':
        return tr(
          ar: 'خطأ داخلي من الخادم. راجع Logs للـ Functions.',
          fr: "Erreur interne serveur. Consultez les logs Functions.",
          en: 'Server internal error. Check Functions logs.',
        );
      case 'unauthenticated':
        return tr(
          ar: 'غير مصرح. أعد المحاولة.',
          fr: "Non authentifié. Réessayez.",
          en: 'Unauthenticated. Please retry.',
        );
      default:
        return tr(
            ar: 'حدث خطأ ($key)',
            fr: 'Erreur ($key)',
            en: 'Something went wrong ($key)');
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
            ar: 'تعذر إرسال الرمز',
            fr: "Impossible d’envoyer le code",
            en: 'Failed to send code');
    }
  }

  String _passwordErrorText(String? key) {
    switch (key) {
      case 'wrong_password':
        return tr(
            ar: 'كلمة المرور غير صحيحة',
            fr: 'Mot de passe incorrect',
            en: 'Wrong password');
      case 'user_not_found':
        return tr(
            ar: 'لا يوجد حساب لهذا الرقم',
            fr: 'Aucun compte pour ce numéro',
            en: 'No account for this number');
      case 'invalid_phone':
        return tr(
            ar: 'رقم غير صحيح', fr: 'Numéro invalide', en: 'Invalid number');
      case 'weak_password':
        return tr(
            ar: 'كلمة المرور ضعيفة',
            fr: 'Mot de passe faible',
            en: 'Weak password');
      case 'email_in_use':
        return tr(
            ar: 'هذا الرقم مرتبط بحساب آخر',
            fr: 'Ce numéro est déjà utilisé',
            en: 'Number already used');
      case 'account_exists_with_different_credential':
        return tr(
            ar: 'الحساب موجود بطريقة دخول مختلفة',
            fr: 'Compte déjà existant',
            en: 'Account exists with different credential');
      case 'network':
        return tr(
            ar: 'تحقق من الإنترنت',
            fr: 'Vérifiez Internet',
            en: 'Check internet');
      default:
        return tr(
            ar: 'فشل تسجيل الدخول',
            fr: 'Échec de connexion',
            en: 'Login failed');
    }
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
                  tr(ar: 'أدخل الرمز', fr: 'Entrez le code', en: 'Enter code')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viaWhatsApp
                        ? tr(
                            ar: 'أرسلنا لك رمز تحقق عبر واتساب.',
                            fr: 'Nous avons envoyé un code via WhatsApp.',
                            en: 'We sent you a code via WhatsApp.')
                        : tr(
                            ar: 'أرسلنا لك رمز تحقق عبر SMS.',
                            fr: 'Nous avons envoyé un code par SMS.',
                            en: 'We sent you a code via SMS.'),
                    style: TextStyle(color: cs.onSurface.withAlpha(180)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
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
                            en: 'Check WhatsApp then enter the code here.')
                        : tr(
                            ar: 'قد يتأخر SMS قليلاً. إن لم يصلك الرمز، تأكد من الرقم ثم أعد الإرسال.',
                            fr: "Le SMS peut prendre un moment. Vérifiez le numéro puis réessayez.",
                            en: 'SMS may take a moment. Verify the number then retry.'),
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

  Future<void> _loginWithPhoneOtp() async {
    final phone = _normalizeAndValidatePhone(_loginPhoneCtl.text);
    if (phone == null) {
      _toast(_invalidPhoneMsg());
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);

    try {
      final notifier = ref.read(authControllerProvider.notifier);

      final sent = await notifier.requestTwilioOtp(
        phoneE164: phone,
        channel: 'sms',
      );

      if (!mounted) return;

      if (!sent.ok) {
        _toast(_otpErrorText(sent.message ?? 'unknown'));
        return;
      }

      _toast(tr(ar: 'تم إرسال الرمز', fr: 'Code envoyé', en: 'Code sent'));

      final entered = await _askOtpDialog(channel: 'sms');
      if (!mounted) return;
      if (entered == null || entered.isEmpty) return;

      final res = await notifier.signInWithTwilioOtp(
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
      debugPrint('Twilio OTP login failed: $e');
      _toast(tr(ar: 'حدث خطأ', fr: 'Erreur', en: 'Something went wrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onLoginPhoneChanged() {
    _pwCheckDebounce?.cancel();
    _pwCheckDebounce = Timer(const Duration(milliseconds: 450), () async {
      final phone = _normalizeAndValidatePhone(_loginPhoneCtl.text);
      if (phone == null) {
        if (!mounted) return;
        setState(() {
          _passwordEligible = false;
          _usePassword = true;
        });
        return;
      }

      final checkedPhone = phone;
      try {
        final notifier = ref.read(authControllerProvider.notifier);
        final eligible =
            await notifier.phoneHasPasswordLogin(phoneE164: checkedPhone);

        if (!mounted) return;

        // Ignore stale results if the user changed the phone while we were checking.
        final current = _normalizeAndValidatePhone(_loginPhoneCtl.text);
        if (current != checkedPhone) return;

        setState(() {
          _passwordEligible = eligible;
          _usePassword = true;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _passwordEligible = false;
          _usePassword = true;
        });
      }
    });
  }

  void _togglePasswordMode(bool v) {
    if (!_passwordEligible && v) return;
    setState(() => _usePassword = v);
  }

  Future<void> _openResetPassword(String phoneE164) async {
    if (!mounted) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(phoneE164: phoneE164),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await _goNext();
    }
  }

  Future<void> _forgotPasswordWithOtp() async {
    final phone = _normalizeAndValidatePhone(_loginPhoneCtl.text);
    if (phone == null) {
      _toast(_invalidPhoneMsg());
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);

    try {
      final notifier = ref.read(authControllerProvider.notifier);

      final sent = await notifier.requestTwilioOtp(
        phoneE164: phone,
        channel: 'sms',
      );

      if (!mounted) return;

      if (!sent.ok) {
        _toast(_otpErrorText(sent.message ?? 'unknown'));
        return;
      }

      final entered = await _askOtpDialog(channel: 'sms');
      if (!mounted) return;
      if (entered == null || entered.trim().isEmpty) return;

      final res = await notifier.signInWithTwilioOtp(
        phoneE164: phone,
        code: entered.trim(),
      );

      if (!mounted) return;

      if (!res.ok) {
        _toast(_otpErrorText(res.message ?? 'unknown'));
        return;
      }

      await _openResetPassword(phone);
    } catch (e) {
      debugPrint('Forgot-pass Twilio OTP failed: $e');
      _toast(tr(
        ar: 'تعذر إرسال/التحقق من الرمز',
        fr: "Impossible d’envoyer/vérifier le code",
        en: 'Failed to send/verify code',
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithWhatsAppOtp() async {
    _toast(tr(ar: 'قريبًا', fr: 'Bientôt', en: 'Coming soon'));
  }

  Future<void> _contactAdminWhatsApp() async {
    // Allow contacting support even before login.
    final raw = _loginPhoneCtl.text.trim();
    final phoneDigits = raw.isEmpty ? '' : raw;

    final msg = tr(
      ar: 'السلام عليكم، لدي مشكلة في تسجيل الدخول. رقمي: $phoneDigits',
      fr: "Bonjour, j’ai un problème de connexion. Mon numéro : $phoneDigits",
      en: 'Hi, I have a login problem. My number: $phoneDigits',
    );

    // Read from Remote Config (fallback to constant).
    final waNumber = SupportConfig.whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse(
      'https://wa.me/$waNumber?text=${Uri.encodeComponent(msg)}',
    );

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        _toast(tr(
          ar: 'تعذر فتح واتساب. انسخ الرقم وتواصل معنا.',
          fr: "Impossible d’ouvrir WhatsApp. Copiez le numéro et contactez-nous.",
          en: "Couldn't open WhatsApp. Copy the number and contact us.",
        ));
      }
    } catch (e) {
      debugPrint('WhatsApp launch failed: $e');
      _toast(tr(
        ar: 'تعذر فتح واتساب. انسخ الرقم وتواصل معنا.',
        fr: "Impossible d’ouvrir WhatsApp. Copiez le numéro et contactez-nous.",
        en: "Couldn't open WhatsApp. Copy the number and contact us.",
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Phone + password actions
  // ---------------------------------------------------------------------------

  Future<void> _loginWithPassword() async {
    final phone = _normalizeAndValidatePhone(_loginPhoneCtl.text);
    final pass = _loginPassCtl.text;

    if (phone == null) {
      _toast(_invalidPhoneMsg());
      return;
    }
    if (pass.trim().length < 6) {
      _toast(tr(
          ar: 'كلمة المرور قصيرة',
          fr: 'Mot de passe trop court',
          en: 'Password too short'));
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);

    try {
      final notifier = ref.read(authControllerProvider.notifier);

      // Use dynamic call to be compatible with projects that already added this method.
      final dynamic res = await (notifier as dynamic).signInWithPhonePassword(
        phoneE164: phone,
        password: pass.trim(),
      );

      if (!mounted) return;

      if (res is AuthOpResult) {
        if (!res.ok) {
          _toast(_passwordErrorText(res.message));
          return;
        }
        await _goNext();
        return;
      }

      // If result isn't AuthOpResult, just check signed-in state.
      if (ref.read(authControllerProvider).isSignedIn) {
        await _goNext();
      } else {
        _toast(tr(
            ar: 'فشل تسجيل الدخول',
            fr: 'Échec de connexion',
            en: 'Login failed'));
      }
    } on NoSuchMethodError {
      _toastWithAction(
        tr(
          ar: 'ميزة الهاتف + كلمة المرور غير مفعّلة بعد. استخدم OTP مؤقتًا.',
          fr: 'Téléphone + mot de passe non configuré. Utilisez OTP.',
          en: 'Phone+password not configured. Use OTP.',
        ),
        actionLabel: tr(ar: 'OTP', fr: 'OTP', en: 'OTP'),
        onAction: () => _loginWithPhoneOtp(),
      );
    } catch (e) {
      debugPrint('loginWithPassword failed: $e');
      _toast(tr(ar: 'حدث خطأ', fr: 'Erreur', en: 'Something went wrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signupWithWhatsAppOtpOnly({
    required String name,
    required String phone,
    required String password,
  }) async {
    _toast(tr(ar: 'قريبًا', fr: 'Bientôt', en: 'Coming soon'));
  }

  Future<void> _signupWithPassword() async {
    final name = _signupNameCtl.text.trim();
    final phone = _normalizeAndValidatePhone(_signupPhoneCtl.text);
    final pass = _signupPassCtl.text.trim();
    final pass2 = _signupPass2Ctl.text.trim();

    if (name.isEmpty) {
      _toast(tr(ar: 'الاسم مطلوب', fr: 'Nom requis', en: 'Name required'));
      return;
    }
    if (phone == null) {
      _toast(_invalidPhoneMsg());
      return;
    }
    if (pass.length < 6) {
      _toast(tr(
          ar: 'كلمة المرور قصيرة',
          fr: 'Mot de passe court',
          en: 'Password too short'));
      return;
    }
    if (pass != pass2) {
      _toast(tr(
          ar: 'كلمتا المرور غير متطابقتين',
          fr: 'Mots de passe différents',
          en: 'Passwords do not match'));
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);

    final notifier = ref.read(authControllerProvider.notifier);

    try {
      // 1) Send OTP via Twilio Verify (SMS)
      final sent = await notifier.requestTwilioOtp(
        phoneE164: phone,
        channel: 'sms',
      );

      if (!mounted) return;

      if (!sent.ok) {
        _toast(_otpErrorText(sent.message ?? 'unknown'));
        return;
      }

      _toast(tr(ar: 'تم إرسال الرمز', fr: 'Code envoyé', en: 'Code sent'));

      // 2) Ask user for OTP
      final entered = await _askOtpDialog(channel: 'sms');
      if (!mounted) return;
      if (entered == null || entered.trim().isEmpty) return;

      // 3) Create account using Twilio OTP
      final created = await notifier.createAccountWithTwilioOtp(
        name: name,
        phoneE164: phone,
        code: entered.trim(),
      );

      if (!mounted) return;

      if (!created.ok) {
        _toast(_otpErrorText(created.message ?? 'unknown'));
        return;
      }

      // 4) Link password to the account (phone+password)
      final linked = await notifier.enablePhonePasswordLogin(
        phoneE164: phone,
        password: pass,
      );

      if (!mounted) return;

      if (!linked.ok) {
        _toast(linked.message ??
            tr(
                ar: 'تعذر حفظ كلمة المرور',
                fr: "Impossible d’enregistrer le mot de passe",
                en: 'Failed to save password'));
        return;
      }

      await _goNext();
    } catch (e) {
      debugPrint('Signup Twilio OTP failed: $e');
      _toast(tr(ar: 'حدث خطأ', fr: 'Erreur', en: 'Something went wrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Third party
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  InputDecoration _fieldDeco(ColorScheme cs,
      {required String hint,
      required IconData icon,
      Widget? suffix,
      String? label}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: cs.surfaceVariant.withAlpha(50),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary.withAlpha(120)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _header(ColorScheme cs) {
    final isLogin = _tabs.index == 0;

    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1D87FF),
                    const Color(0xFF2CA6FF),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 10,
            start: 12,
            child: TextButton(
              onPressed: _busy ? null : _continueAsGuest,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(tr(ar: 'تصفح كضيف', fr: 'Invité', en: 'Guest')),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(245),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: AppTheme.brandOrange.withAlpha(210),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/images/branding/tiki_app_icon_1024.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => Icon(
                          Icons.apps,
                          size: 36,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'tikiapp',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isLogin
                      ? tr(ar: 'تسجيل الدخول', fr: 'Connexion', en: 'Login')
                      : tr(
                          ar: 'إنشاء حساب',
                          fr: 'Créer un compte',
                          en: 'Create account'),
                  style: TextStyle(
                    color: Colors.white.withAlpha(235),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orDivider(ColorScheme cs, String text) {
    return Row(
      children: [
        Expanded(child: Divider(color: cs.outline.withAlpha(120))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child:
              Text(text, style: TextStyle(color: cs.onSurface.withAlpha(160))),
        ),
        Expanded(child: Divider(color: cs.outline.withAlpha(120))),
      ],
    );
  }

  Widget _socialButtons(ColorScheme cs) {
    return Column(
      children: [
        OutlinedButton(
          onPressed: _busy ? null : () => _thirdParty(AuthProviderKind.google),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('G',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(width: 10),
              Text(tr(
                  ar: 'التسجيل باستخدام Google',
                  fr: 'Continuer avec Google',
                  en: 'Continue with Google')),
            ],
          ),
        ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : () => _thirdParty(AuthProviderKind.apple),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.apple, size: 20),
                const SizedBox(width: 10),
                Text(tr(
                    ar: 'التسجيل باستخدام Apple',
                    fr: 'Continuer avec Apple',
                    en: 'Continue with Apple')),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _bottomSwitch({required bool isLogin}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isLogin
              ? tr(
                  ar: 'ليس لديك حساب ؟',
                  fr: "Pas de compte ?",
                  en: "Don't have an account?")
              : tr(
                  ar: 'لديك حساب ؟',
                  fr: 'Vous avez un compte ?',
                  en: 'Already have an account?'),
        ),
        const SizedBox(width: 6),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  _tabs.animateTo(isLogin ? 1 : 0);
                },
          child: Text(isLogin
              ? tr(ar: 'إنشاء حساب', fr: 'Créer', en: 'Sign up')
              : tr(ar: 'تسجيل الدخول', fr: 'Connexion', en: 'Login')),
        ),
      ],
    );
  }

  Widget _loginPage(ColorScheme cs) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _loginPhoneCtl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: _country == '+222' ? 8 : 15,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            decoration: _fieldDeco(
              cs,
              hint: tr(ar: 'رقم الهاتف', fr: 'Téléphone', en: 'Phone number'),
              icon: Icons.phone,
              suffix: _countrySuffix(cs),
            ).copyWith(counterText: ''),
          ),

          const SizedBox(height: 10),

          // Password-only login. If this phone doesn't have a password yet,
          // the user can set one via "Forgot password" (OTP verification).
          if (!_passwordEligible)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(
                tr(
                  ar: 'لا توجد كلمة مرور لهذا الرقم. اضغط «نسيت كلمة المرور؟» لتعيين كلمة مرور عبر OTP.',
                  fr: "Aucun mot de passe pour ce numéro. Appuyez sur «Mot de passe oublié ?» pour en définir un via OTP.",
                  en: 'No password for this number. Tap “Forgot password?” to set one via OTP.',
                ),
                style: TextStyle(
                    color: cs.onSurface.withOpacity(0.65), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),

          TextField(
            controller: _loginPassCtl,
            obscureText: _loginPassObscure,
            decoration: _fieldDeco(
              cs,
              hint: tr(ar: 'كلمة المرور', fr: 'Mot de passe', en: 'Password'),
              icon: Icons.lock,
              suffix: IconButton(
                onPressed: () =>
                    setState(() => _loginPassObscure = !_loginPassObscure),
                icon: Icon(_loginPassObscure
                    ? Icons.visibility
                    : Icons.visibility_off),
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _busy ? null : _forgotPasswordWithOtp,
              child: Text(tr(
                  ar: 'نسيت كلمة المرور؟',
                  fr: 'Mot de passe oublié ?',
                  en: 'Forgot password?')),
            ),
          ),

          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _busy ? null : _contactAdminWhatsApp,
              style:
                  TextButton.styleFrom(foregroundColor: AppTheme.brandOrange),
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(tr(
                ar: 'تواصل مع الإدارة عبر واتساب',
                fr: "Contacter l’admin sur WhatsApp",
                en: 'Contact admin on WhatsApp',
              )),
            ),
          ),

          const SizedBox(height: 4),
          FilledButton(
            onPressed: _busy ? null : _loginWithPassword,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr(ar: 'تسجيل الدخول', fr: 'Se connecter', en: 'Login')),
          ),
          const SizedBox(height: 18),
          _orDivider(cs,
              tr(ar: 'أو سجل باستخدام', fr: 'Ou avec', en: 'Or continue with')),
          const SizedBox(height: 14),
          _socialButtons(cs),
          const SizedBox(height: 14),
          _bottomSwitch(isLogin: true),
        ],
      ),
    );
  }

  Widget _signupPage(ColorScheme cs) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _signupNameCtl,
            textInputAction: TextInputAction.next,
            decoration: _fieldDeco(
              cs,
              hint: tr(ar: 'الاسم', fr: 'Nom', en: 'Name'),
              icon: Icons.person,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _signupPhoneCtl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: _country == '+222' ? 8 : 15,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            decoration: _fieldDeco(
              cs,
              hint: tr(ar: 'رقم الهاتف', fr: 'Téléphone', en: 'Phone number'),
              icon: Icons.phone,
              suffix: _countrySuffix(cs),
            ).copyWith(counterText: ''),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _signupPassCtl,
            obscureText: _signupPassObscure,
            decoration: _fieldDeco(
              cs,
              hint: tr(ar: 'كلمة المرور', fr: 'Mot de passe', en: 'Password'),
              icon: Icons.lock,
              suffix: IconButton(
                onPressed: () =>
                    setState(() => _signupPassObscure = !_signupPassObscure),
                icon: Icon(_signupPassObscure
                    ? Icons.visibility
                    : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _signupPass2Ctl,
            obscureText: _signupPass2Obscure,
            decoration: _fieldDeco(
              cs,
              hint: tr(
                  ar: 'تأكيد كلمة المرور',
                  fr: 'Confirmer le mot de passe',
                  en: 'Confirm password'),
              icon: Icons.lock,
              suffix: IconButton(
                onPressed: () =>
                    setState(() => _signupPass2Obscure = !_signupPass2Obscure),
                icon: Icon(_signupPass2Obscure
                    ? Icons.visibility
                    : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _signupWithPassword,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr(
                    ar: 'إنشاء حساب',
                    fr: 'Créer un compte',
                    en: 'Create account')),
          ),
          const SizedBox(height: 18),
          _orDivider(cs,
              tr(ar: 'أو سجل باستخدام', fr: 'Ou avec', en: 'Or continue with')),
          const SizedBox(height: 14),
          _socialButtons(cs),
          const SizedBox(height: 14),
          _bottomSwitch(isLogin: false),
          const SizedBox(height: 10),
          Text(
            tr(
              ar: 'بالضغط على المتابعة، أنت توافق على الشروط وسياسة الخصوصية.',
              fr: 'En continuant, vous acceptez les Conditions et la Confidentialité.',
              en: 'By continuing, you agree to Terms & Privacy.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150)),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              TextButton(
                onPressed: () => context.push('/content/policies/terms'),
                child: Text(tr(ar: 'الشروط', fr: 'Conditions', en: 'Terms')),
              ),
              TextButton(
                onPressed: () => context.push('/content/policies/privacy'),
                child: Text(
                    tr(ar: 'الخصوصية', fr: 'Confidentialité', en: 'Privacy')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _header(cs),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _loginPage(cs),
                  _signupPage(cs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
