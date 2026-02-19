import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../domain/app_notification.dart';
import 'notifications_controller.dart';

/// Bridges Firebase Cloud Messaging events into the in-app notifications UI.
///
/// - Foreground messages won't show a system notification by default on iOS.
///   We push them into the in-app notification list so the user still sees them.
/// - Tapping a notification opens the target route (if provided).
final fcmWatcherProvider = Provider<_FcmWatcher>((ref) {
  final watcher = _FcmWatcher(ref);
  watcher.bind();
  ref.onDispose(watcher.dispose);
  return watcher;
});

class _FcmWatcher {
  _FcmWatcher(this._ref);

  final Ref _ref;

  StreamSubscription<RemoteMessage>? _msgSub;
  StreamSubscription<RemoteMessage>? _openSub;

  bool _bound = false;

  void bind() {
    if (_bound) return;
    _bound = true;

    // Foreground messages.
    _msgSub = FirebaseMessaging.onMessage.listen((m) {
      final title =
          (m.notification?.title ?? m.data['title'] ?? '').toString().trim();
      final body =
          (m.notification?.body ?? m.data['body'] ?? '').toString().trim();
      final route = (m.data['targetRoute'] ?? m.data['route'] ?? m.data['deeplink'] ?? '')
          .toString()
          .trim();

      if (kDebugMode) {
        debugPrint('[FCM] onMessage title="$title" route="$route"');
      }

      if (title.isEmpty && body.isEmpty) return;

      // Push as a system notification (localized fallback = same text).
      _ref.read(notificationsControllerProvider.notifier).pushText(
            type: AppNotificationType.system,
            arTitle: title.isEmpty ? 'إشعار' : title,
            frTitle: title.isEmpty ? 'Notification' : title,
            enTitle: title.isEmpty ? 'Notification' : title,
            arBody: body,
            frBody: body,
            enBody: body,
            targetRoute: _sanitizeRoute(route),
          );
    });

    // When the user taps a notification.
    _openSub = FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final route = (m.data['targetRoute'] ?? m.data['route'] ?? m.data['deeplink'] ?? '')
          .toString()
          .trim();
      final r = _sanitizeRoute(route);
      if (r == null) return;
      _go(r);
    });

    // If app was launched from a terminated state via notification.
    unawaited(_handleInitialMessage());
  }

  Future<void> _handleInitialMessage() async {
    try {
      final m = await FirebaseMessaging.instance.getInitialMessage();
      if (m == null) return;
      final route = (m.data['targetRoute'] ?? m.data['route'] ?? m.data['deeplink'] ?? '')
          .toString()
          .trim();
      final r = _sanitizeRoute(route);
      if (r == null) return;
      _go(r);
    } catch (_) {
      // ignore
    }
  }

  void _go(String route) {
    try {
      final router = _ref.read(appRouterProvider);
      router.go(route);
    } catch (_) {
      // ignore
    }
  }

  String? _sanitizeRoute(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return null;
    // Only allow in-app routes.
    if (!r.startsWith('/')) return null;
    return r;
  }

  void dispose() {
    _msgSub?.cancel();
    _openSub?.cancel();
    _msgSub = null;
    _openSub = null;
  }
}
