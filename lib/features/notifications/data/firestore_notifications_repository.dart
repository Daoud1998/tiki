import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/app_notification.dart';
import '../shared/notifications_i18n.dart';
import 'notifications_repository.dart';

/// Firestore-backed notifications repository.
///
/// Reads:
/// - user_inbox/{uid}/items (personal notifications)
/// - broadcast_notifications (global / topic notifications)
///
/// Broadcast notifications are filtered client-side by targetTopic against
/// user's notifTopics stored in users/{uid}.notifTopics (array of strings).
class FirestoreNotificationsRepository implements NotificationsRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  FirestoreNotificationsRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  @override
  Future<List<AppNotification>> fetchInitial() async {
    final uid = _auth.currentUser?.uid;

    // Topics used to filter broadcasts.
    final topics = await _loadTopics(uid);

    // Personal inbox
    final inboxDocs = uid == null
        ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
        : (await _db
                .collection('user_inbox')
                .doc(uid)
                .collection('items')
                .orderBy('createdAtMs', descending: true)
                .limit(50)
                .get())
            .docs;

    // Broadcast
    final broadcastDocs = (await _db
            .collection('broadcast_notifications')
            .orderBy('createdAtMs', descending: true)
            .limit(50)
            .get())
        .docs;

    final items = <AppNotification>[];

    for (final d in inboxDocs) {
      final n = _mapDocToNotification(
        d.id,
        d.data(),
        defaultType: AppNotificationType.sales,
      );
      if (n != null) items.add(n);
    }

    for (final d in broadcastDocs) {
      final data = d.data();
      final targetTopic =
          (data['targetTopic'] ?? data['topic'] ?? '').toString().trim();

      // If topic specified, show only if user is subscribed.
      if (targetTopic.isNotEmpty && !topics.contains(targetTopic)) continue;

      final n = _mapDocToNotification(
        d.id,
        data,
        defaultType: AppNotificationType.system,
      );
      if (n != null) items.add(n);
    }

    // Sort newest first
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // De-dup by id (in case the same id appears in both sources)
    final seen = <String>{};
    final dedup = <AppNotification>[];
    for (final n in items) {
      if (seen.add(n.id)) dedup.add(n);
    }

    return dedup;
  }

  Future<Set<String>> _loadTopics(String? uid) async {
    // Default topic: all users
    final topics = <String>{'all_users'};

    if (uid == null) return topics;

    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      final data = userDoc.data();
      final list = data == null ? null : data['notifTopics'];

      if (list is List) {
        for (final v in list) {
          final s = (v ?? '').toString().trim();
          if (s.isNotEmpty) topics.add(s);
        }
      }
    } catch (_) {
      // Ignore and keep default
    }

    return topics;
  }

  AppNotification? _mapDocToNotification(
    String id,
    Map<String, dynamic> d, {
    required AppNotificationType defaultType,
  }) {
    final rawType = d['type'] ?? d['kind'] ?? d['category'];
    final type = _parseType(rawType, defaultType: defaultType);

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

    // Fallback: if backend sent no route (or mistakenly '/notifications')
    // for VIP-related seller notifications, open the promo ads screen.
    if (route.isEmpty || route == '/notifications') {
      final combined = ('${rawType ?? ''} '
              '${title.ar} ${title.fr} ${title.en} '
              '${body.ar} ${body.fr} ${body.en}')
          .toLowerCase();
      if (combined.contains('vip')) {
        route = '/you/support';
      }
    }

    final createdAt = _parseDate(d['createdAt'], d['createdAtMs']);
    final isRead = (d['read'] is bool) ? (d['read'] as bool) : false;

    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      targetRoute: route.isEmpty ? null : route,
      createdAt: createdAt,
      isRead: isRead,
    );
  }

  AppNotificationType _parseType(dynamic v,
      {required AppNotificationType defaultType}) {
    final s = (v ?? '').toString().toLowerCase().trim();

    if (s.isEmpty) return defaultType;

    if (s == 'sales' || s == 'listing' || s == 'product_moderation') {
      return AppNotificationType.sales;
    }
    if (s == 'deals' || s == 'promo' || s == 'offers') {
      return AppNotificationType.deals;
    }

    // Seller promos / VIP / paid boosts
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
    // Map form: {ar, fr, en}
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

    // String form
    final s = (v ?? '').toString().trim();
    final f = s.isNotEmpty ? s : fallback;
    return LocalizedText(ar: f, fr: f, en: f);
  }

  DateTime _parseDate(dynamic ts, dynamic ms) {
    if (ts is Timestamp) return ts.toDate();
    if (ms is num) return DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    return DateTime.now();
  }
}
