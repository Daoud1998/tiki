import 'dart:io' show Platform;

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
  if (Platform.isAndroid) {
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
  // - Debug builds: use the Debug provider (requires adding the debug token in Firebase Console).
  // - Release builds: use Play Integrity.
  //
  // If you see:
  //   "Error returned from API. code: 403 body: App attestation failed."
  // then you DID NOT register the debug token yet (or you're running a release build without
  // Play Integrity setup).
  await FirebaseAppCheck.instance.activate(
    androidProvider:
        kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
  );

  // Trigger a token request once at startup so the "debug secret" is printed in Logcat
  // when using AndroidProvider.debug.
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

  // Keep token refresh enabled (default = true).
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

  await bootstrap();
}
