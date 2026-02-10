import 'dart:async';

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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? prefSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? kycSub;
  StreamSubscription<String>? tokenRefreshSub;

  Future<void> cleanup() async {
    await prefSub?.cancel();
    await kycSub?.cancel();
    await tokenRefreshSub?.cancel();
    prefSub = null;
    kycSub = null;
    tokenRefreshSub = null;
  }

  FirebaseAuth.instance.authStateChanges().listen((user) async {
    await cleanup();
    if (user == null) return;

    final uid = user.uid;
    final phone = user.phoneNumber ?? '';
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    bool? lastEnabled;

    Future<void> disablePush({bool updateTopics = true}) async {
      try {
        final messaging = FirebaseMessaging.instance;
        await messaging.setAutoInitEnabled(false);

        // Unsubscribe from known topics (safe even if not subscribed).
        const knownTopics = <String>[
          'all_users',
          'verified',
          'unverified',
          'country_mr',
          'country_eu',
        ];
        for (final t in knownTopics) {
          try {
            await messaging.unsubscribeFromTopic(t);
          } catch (_) {}
        }

        // Remove current token from Firestore, then delete it.
        final token = await messaging.getToken();
        if (token != null && token.trim().isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('user_devices')
                .doc(uid)
                .collection('tokens')
                .doc(token)
                .delete();
          } catch (_) {}
        }

        try {
          await messaging.deleteToken();
        } catch (_) {}

        await tokenRefreshSub?.cancel();
        tokenRefreshSub = null;

        await kycSub?.cancel();
        kycSub = null;

        if (updateTopics) {
          // Clear topics so broadcast (in-app) notifications are filtered out.
          await userRef.set(
            {
              'notifTopics': <String>[],
              'notifUpdatedAtMs': DateTime.now().millisecondsSinceEpoch,
              'notifUpdatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      } catch (e) {
        debugPrint('FCM disable error: $e');
      }
    }

    Future<void> enablePush() async {
      try {
        final messaging = FirebaseMessaging.instance;
        await messaging.setAutoInitEnabled(true);

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
        await userRef.set(
          {
            'notifTopics': topics,
            'notifUpdatedAtMs': DateTime.now().millisecondsSinceEpoch,
            'notifUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // Token refresh
        await tokenRefreshSub?.cancel();
        tokenRefreshSub = messaging.onTokenRefresh.listen((t) async {
          if (t.isNotEmpty) {
            await _saveToken(uid, t);
          }
        });

        // If KYC status changes later, resync topics.
        await kycSub?.cancel();
        kycSub = FirebaseFirestore.instance
            .doc('kyc_requests/$uid')
            .snapshots()
            .listen((_) async {
          await _syncTopics(uid: uid, phone: phone);
        });
      } catch (e) {
        // App still works without push
        debugPrint('FCM setup error: $e');
      }
    }

    // React to /users/{uid}.notificationsEnabled
    prefSub = userRef.snapshots().listen((snap) async {
      final enabled = (snap.data()?['notificationsEnabled'] as bool?) ?? true;
      if (lastEnabled == enabled) return;
      lastEnabled = enabled;

      if (!enabled) {
        await disablePush(updateTopics: true);
      } else {
        await enablePush();
      }
    });

    // Apply once immediately even before first snapshot event.
    try {
      final snap = await userRef.get();
      final enabled = (snap.data()?['notificationsEnabled'] as bool?) ?? true;
      lastEnabled = enabled;
      if (enabled) {
        await enablePush();
      } else {
        await disablePush(updateTopics: true);
      }
    } catch (_) {
      // If cannot read user doc, still try to enable (defaults to true).
      await enablePush();
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
