import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/auth_state.dart';
import '../domain/app_notification.dart';
import '../shared/notifications_i18n.dart';
import 'notifications_controller.dart';

/// Watches user_inbox/{uid}/items and pushes new items into the in-app
/// notifications state so the UI updates instantly.
final inboxWatcherProvider = Provider<_InboxWatcher>((ref) {
  final auth = ref.watch(authControllerProvider);
  final watcher = _InboxWatcher(ref);
  watcher.bind(uid: auth.userId);
  ref.onDispose(watcher.dispose);
  return watcher;
});

class _InboxWatcher {
  _InboxWatcher(this._ref);

  final Ref _ref;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;
  int _lastMs = 0;

  void bind({required String? uid}) {
    final next = (uid ?? '').trim().isEmpty ? null : uid!.trim();
    if (next == _uid) return;
    _uid = next;
    _sub?.cancel();
    _sub = null;

    // Start watching only when signed in.
    if (_uid == null) return;

    // Seed lastMs from already-loaded notifications so we don't re-push them.
    final existing = _ref.read(notificationsControllerProvider).items;
    if (existing.isNotEmpty) {
      _lastMs = existing
          .map((e) => e.createdAt.millisecondsSinceEpoch)
          .reduce((a, b) => a > b ? a : b);
    } else {
      _lastMs = DateTime.now().millisecondsSinceEpoch;
    }

    final q = FirebaseFirestore.instance
        .collection('user_inbox')
        .doc(_uid)
        .collection('items')
        .orderBy('createdAtMs', descending: true)
        .limit(25);

    _sub = q.snapshots().listen((snap) {
      // We only care about new docs.
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final d = change.doc;
        final data = d.data();
        if (data == null) continue;

        final createdMs = _asInt(data['createdAtMs']) ??
            _asTimestampMs(data['createdAt']) ??
            DateTime.now().millisecondsSinceEpoch;

        if (createdMs <= _lastMs) continue;
        _lastMs = createdMs;

        final n = _mapToNotification(d.id, data);
        if (n == null) continue;

        _ref.read(notificationsControllerProvider.notifier).push(
              type: n.type,
              title: n.title,
              body: n.body,
              targetRoute: n.targetRoute,
              id: n.id,
              createdAt: n.createdAt,
            );
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  int? _asTimestampMs(dynamic v) {
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    return null;
  }

  AppNotification? _mapToNotification(String id, Map<String, dynamic> d) {
    final rawType = d['type'] ?? d['kind'] ?? d['category'];

    final title = _parseLocalized(
      d['title'] ?? d['titleText'] ?? d['subject'],
      fallback: 'Notification',
    );
    final body = _parseLocalized(
      d['body'] ?? d['message'] ?? d['text'],
      fallback: '',
    );

    var route = (d['targetRoute'] ?? d['route'] ?? d['deeplink'] ?? '')
        .toString()
        .trim();

    // Fallback: VIP-related notifications should open the seller promo page.
    if (route.isEmpty || route == '/notifications') {
      final combined = ('${rawType ?? ''} '
              '${title.ar} ${title.fr} ${title.en} '
              '${body.ar} ${body.fr} ${body.en}')
          .toLowerCase();
      if (combined.contains('vip')) {
        route = '/promo-ads?mine=1';
      }
    }

    final createdAt = _parseDate(d['createdAt'], d['createdAtMs']);
    final isRead = (d['read'] is bool) ? (d['read'] as bool) : false;

    return AppNotification(
      id: id,
      type: _parseType(rawType),
      title: title,
      body: body,
      targetRoute: route.isEmpty ? null : route,
      createdAt: createdAt,
      isRead: isRead,
    );
  }

  AppNotificationType _parseType(dynamic v) {
    final s = (v ?? '').toString().toLowerCase().trim();

    // user_inbox is mostly seller/account related; default to 'sales'
    // if no explicit category is provided.
    if (s.isEmpty) return AppNotificationType.sales;

    if (s == 'sales' || s == 'listing' || s == 'product_moderation') {
      return AppNotificationType.sales;
    }
    if (s == 'deals' || s == 'promo' || s == 'offers') {
      return AppNotificationType.deals;
    }
    if (s.contains('vip') ||
        s.contains('promo') ||
        s.contains('boost') ||
        s.contains('featured') ||
        s.contains('top') ||
        s.contains('ad')) {
      return AppNotificationType.sales;
    }

    return AppNotificationType.system;
  }

  LocalizedText _parseLocalized(dynamic v, {required String fallback}) {
    if (v is Map) {
      final ar = (v['ar'] ?? v['AR'] ?? '').toString();
      final fr = (v['fr'] ?? v['FR'] ?? '').toString();
      final en = (v['en'] ?? v['EN'] ?? '').toString();
      String choose(String a, String b, String c) {
        final aa = a.trim();
        if (aa.isNotEmpty) return aa;
        final bb = b.trim();
        if (bb.isNotEmpty) return bb;
        final cc = c.trim();
        if (cc.isNotEmpty) return cc;
        return fallback;
      }
      final chosen = choose(ar, fr, en);
      return LocalizedText(
        ar: ar.trim().isEmpty ? chosen : ar.trim(),
        fr: fr.trim().isEmpty ? chosen : fr.trim(),
        en: en.trim().isEmpty ? chosen : en.trim(),
      );
    }
    final s = (v ?? '').toString().trim();
    final f = s.isNotEmpty ? s : fallback;
    return LocalizedText(ar: f, fr: f, en: f);
  }

  DateTime _parseDate(dynamic ts, dynamic ms) {
    if (ts is Timestamp) return ts.toDate();
    final msi = _asInt(ms);
    if (msi != null) return DateTime.fromMillisecondsSinceEpoch(msi);
    return DateTime.now();
  }
}
