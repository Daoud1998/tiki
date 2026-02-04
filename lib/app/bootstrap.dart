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
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      Firebase.app();
    } else {
      rethrow;
    }
  }

  // FCM token + Topics + write notifTopics to /users/{uid}
  _setupMessaging();

  runApp(const LocalStoreProviderScope(child: TikiApp()));
}

void _setupMessaging() {
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;

    final uid = user.uid;
    final phone = user.phoneNumber ?? '';

    try {
      final messaging = FirebaseMessaging.instance;

      // iOS + Android 13+: request permission (safe no-op on older Android).
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Topics (segments)
      final topics = await _syncTopics(uid: uid, phone: phone);

      // Token
      final token = await messaging.getToken();
      debugPrint('FCM TOKEN = $token');
      if (token != null && token.isNotEmpty) {
        await _saveToken(uid, token);
      }

      // Save topics on user profile for Firestore filtering (merge).
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'notifTopics': topics,
          'notifUpdatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'notifUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Token refresh
      messaging.onTokenRefresh.listen((t) async {
        if (t.isNotEmpty) {
          await _saveToken(uid, t);
        }
      });

      // If KYC status changes later, resync topics.
      FirebaseFirestore.instance
          .doc('kyc_requests/$uid')
          .snapshots()
          .listen((_) async {
        await _syncTopics(uid: uid, phone: phone);
      });
    } catch (e) {
      // App still works without push
      debugPrint('FCM setup error: $e');
    }
  });
}

Future<List<String>> _syncTopics(
    {required String uid, required String phone}) async {
  final messaging = FirebaseMessaging.instance;

  final isMr =
      phone.trim().startsWith('+222') || phone.trim().startsWith('222');
  final countryTopic = isMr ? 'country_mr' : 'country_eu';

  // Determine verified via kyc_requests/{uid}.status == 'approved'
  bool isVerified = false;
  try {
    final kyc = await FirebaseFirestore.instance.doc('kyc_requests/$uid').get();
    isVerified = kyc.exists && (kyc.data()?['status'] == 'approved');
  } catch (_) {
    // ignore
  }

  final verifiedTopic = isVerified ? 'verified' : 'unverified';
  final otherVerifiedTopic = isVerified ? 'unverified' : 'verified';
  final otherCountryTopic = isMr ? 'country_eu' : 'country_mr';

  // Always subscribe to all_users
  await messaging.subscribeToTopic('all_users');

  // Keep topics clean (unsubscribe from opposites, then subscribe to correct ones)
  await messaging.unsubscribeFromTopic(otherVerifiedTopic);
  await messaging.unsubscribeFromTopic(otherCountryTopic);

  await messaging.subscribeToTopic(verifiedTopic);
  await messaging.subscribeToTopic(countryTopic);

  return <String>['all_users', verifiedTopic, countryTopic];
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
