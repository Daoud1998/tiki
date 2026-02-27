import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sms_autofill/sms_autofill.dart';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app/bootstrap.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Prints the Android App Signature (11 chars) used for WhatsApp "Autofill" templates.
  // Look in the debug console for: APP_SIGNATURE: XXXXXXXXXXX
  if (kDebugMode &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android) {
    try {
      final sig = await SmsAutoFill().getAppSignature;
      debugPrint('APP_SIGNATURE: $sig');
    } catch (e) {
      debugPrint('APP_SIGNATURE_ERROR: $e');
    }
  }

  // Ensure Firebase is initialized BEFORE App Check and BEFORE calling bootstrap().
  // (bootstrap() will safely ignore duplicate initialization)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // App Check:
  // - Web: either configure reCAPTCHA v3 OR skip App Check to avoid blocking startup.
  // - Android/iOS: Debug provider in debug builds, Play Integrity / App Attest in release.
  //
  // If your Firebase Console → App Check is set to "Monitoring", you can safely skip
  // App Check on web. If you later set "Enforce", configure WebProvider.reCaptchaV3.
  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );

    // Trigger a token request once at startup so the "debug secret" is printed in Logcat
    // when using AndroidProvider.debug.
    if (kDebugMode) {
      try {
        final token = await FirebaseAppCheck.instance.getToken(true);
        debugPrint('APPCHECK_TOKEN_READY: ${token != null}');
      } catch (e) {
        debugPrint('APPCHECK_TOKEN_ERROR: $e');
        debugPrint(
          'If you are in DEBUG mode, copy the "debug secret" from Logcat and add it in: '
          'Firebase Console → App Check → (your app) → Manage debug tokens.',
        );
      }
    }

    // Keep token refresh enabled (default = true).
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  } else {
    // Web: do nothing (prevents "Uncaught Error" on startup).
    // If you want App Check on web later:
    // await FirebaseAppCheck.instance.activate(webProvider: ReCaptchaV3Provider('YOUR_SITE_KEY'));
  }

  await bootstrap();
}
