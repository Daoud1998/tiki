import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/app_notification.dart';
import '../shared/notifications_i18n.dart';


/// Firestore-backed notifications repository.
///
/// Reads:
/// - user_inbox/{uid}/items (personal notifications)
/// - broadcast_notifications (global / topic notifications)
///
/// Broadcast notifications are filtered client-side by [targetTopic] against
/// user's topics stored in users/{uid}.notifTopics (array of strings).
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
      final n = _mapDocToNotification(d.id, d.data());
      if (n != null) items.add(n);
    }

    for (final d in broadcastDocs) {
      final data = d.data();
      final targetTopic =
          (data['targetTopic'] ?? data['topic'] ?? '').toString().trim();

      // If no topic specified -> treat as public broadcast.
      if (targetTopic.isNotEmpty && !topics.contains(targetTopic)) continue;

      final n = _mapDocToNotification(d.id, data);
      if (n != null) items.add(n);
    }

    // Sort newest first
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // De-dup by id
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
      // ignore
    }

    return topics;
  }

  AppNotification? _mapDocToNotification(String id, Map<String, dynamic> d) {
    final type = _parseType(d['type'] ?? d['kind'] ?? d['category']);
    final title = _parseLocalized(
      d['title'] ?? d['titleText'] ?? d['subject'],
      fallback: 'Notification',
    );
    final body = _parseLocalized(
      d['body'] ?? d['message'] ?? d['text'],
      fallback: '',
    );
    final route = (d['targetRoute'] ?? d['route'] ?? d['deeplink'] ?? '')
        .toString()
        .trim();

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

  AppNotificationType _parseType(dynamic v) {
    final s = (v ?? '').toString().toLowerCase().trim();

    // product moderation / listing status
    if (s == 'sales' || s == 'listing' || s == 'product_moderation') {
      return AppNotificationType.sales;
    }

    // promos
    if (s == 'deals' || s == 'promo' || s == 'offers') {
      return AppNotificationType.deals;
    }

    return AppNotificationType.system;
  }

  LocalizedText _parseLocalized(dynamic v, {required String fallback}) {
    // Map form: {ar, fr, en}
    if (v is Map) {
      final ar = (v['ar'] ?? v['AR'] ?? '').toString().trim();
      final fr = (v['fr'] ?? v['FR'] ?? '').toString().trim();
      final en = (v['en'] ?? v['EN'] ?? '').toString().trim();

      final any = ar.isNotEmpty ? ar : (fr.isNotEmpty ? fr : en);
      final f = any.isNotEmpty ? any : fallback;

      return LocalizedText(
        ar: ar.isEmpty ? f : ar,
        fr: fr.isEmpty ? f : fr,
        en: en.isEmpty ? f : en,
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
