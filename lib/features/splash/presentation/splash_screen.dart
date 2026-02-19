import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sms_autofill/sms_autofill.dart';

/// Simple splash that forwards to Home after a short delay.
/// In DEBUG mode it also shows the Android APP_SIGNATURE (11 chars) on screen
/// so you can copy it into Meta (WhatsApp OTP template).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _sig;
  String? _sigError;

  @override
  void initState() {
    super.initState();
    _printAppSignature();

    // Give a tiny pause so the logo is visible, then go to the main shell.
    // In DEBUG we wait a bit longer so you can read/copy the signature.
    final delay = kDebugMode
        ? const Duration(seconds: 2)
        : const Duration(milliseconds: 250);

    Future<void>.delayed(delay, () {
      if (!mounted) return;
      context.go('/home?r=boot');
    });
  }

  Future<void> _printAppSignature() async {
    try {
      final sig = await SmsAutoFill().getAppSignature;
      debugPrint('APP_SIGNATURE: $sig');
      if (!mounted) return;
      setState(() {
        _sig = sig;
        _sigError = null;
      });
    } catch (e) {
      debugPrint('APP_SIGNATURE_ERROR: $e');
      if (!mounted) return;
      setState(() {
        _sig = null;
        _sigError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String tr({required String ar, required String fr, required String en}) {
      final code = Localizations.localeOf(context).languageCode.toLowerCase();
      if (code == 'fr') return fr;
      if (code == 'en') return en;
      return ar;
    }

    Widget debugSignature() {
      if (!kDebugMode) return const SizedBox.shrink();

      final text = _sig != null
          ? 'APP_SIGNATURE: $_sig'
          : (_sigError != null ? 'APP_SIGNATURE_ERROR: $_sigError' : '...');

      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          children: [
            SelectableText(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 6),
            if (_sig != null)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _sig!));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tr(
                        ar: 'تم نسخ الـ APP_SIGNATURE',
                        fr: "APP_SIGNATURE copié",
                        en: 'APP_SIGNATURE copied',
                      )),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(tr(
                  ar: 'نسخ',
                  fr: 'Copier',
                  en: 'Copy',
                )),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F2),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Brand lockup (Temu-lite style)
              Image.asset(
                'assets/images/branding/tiki_lockup_nogap.png',
                width: 200,
                errorBuilder: (_, __, ___) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_bag_rounded,
                        color: cs.primary, size: 32),
                    const SizedBox(width: 0),
                    Text(
                      'TKI',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                tr(
                  ar: 'سوق موريتانيا في جيبك',
                  fr: 'Le marché de la Mauritanie dans votre poche',
                  en: 'Mauritania’s market in your pocket',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    cs.primary.withValues(alpha: 0.85),
                  ),
                ),
              ),

              // DEBUG ONLY: show the signature on screen for easy copy
              debugSignature(),
            ],
          ),
        ),
      ),
    );
  }
}
