import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/storage/local_store.dart';
import '../firebase_options.dart';
import 'app.dart';

Future<void> bootstrap() async {
  // Firebase may already be initialized on the native side (especially after Hot Restart).
  // So we try to initialize, and if it already exists we just reuse it.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      // Reuse the existing default app.
      Firebase.app();
    } else {
      rethrow;
    }
  }

  // Sync FCM token to Firestore so Admin/Functions can notify the user.
  _setupMessagingTokenSync();

  runApp(const LocalStoreProviderScope(child: TikiApp()));
}

void _setupMessagingTokenSync() {
  // Listen for sign-in; when signed in, register token.
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // iOS + Android 13+: request permission (safe no-op on older Android).
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(user.uid, token);
      }

      messaging.onTokenRefresh.listen((t) async {
        if (t.isNotEmpty) {
          await _saveToken(user.uid, t);
        }
      });
    } catch (_) {
      // Ignore token setup errors (app still works without push).
    }
  });
}

Future<void> _saveToken(String uid, String token) async {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final platform = _platformName();

  await FirebaseFirestore.instance
      .collection('user_devices')
      .doc(uid)
      .collection('tokens')
      .doc(token)
      .set(
    {
      'token': token,
      'platform': platform,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtMs': nowMs,
    },
    SetOptions(merge: true),
  );
}

String _platformName() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}
