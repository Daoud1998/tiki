import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/state/auth_state.dart';
import '../../../core/storage/local_store.dart';
import '../data/firestore_notifications_repository.dart';
import '../data/notifications_repository.dart';
import '../domain/app_notification.dart';
import '../shared/notifications_i18n.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return FirestoreNotificationsRepository();
});

@immutable
class NotificationsState {
  final List<AppNotification> items;
  final AppNotificationType? filter; // null = all
  final bool inAppNotificationsEnabled; // in-app toggle
  final bool hasSeenEnableCard;

  const NotificationsState({
    required this.items,
    required this.filter,
    required this.inAppNotificationsEnabled,
    required this.hasSeenEnableCard,
  });

  int get unreadCount => items.where((n) => !n.isRead).length;

  List<AppNotification> get filtered {
    if (filter == null) return items;
    return items.where((n) => n.type == filter).toList();
  }

  NotificationsState copyWith({
    List<AppNotification>? items,
    AppNotificationType? filter,
    bool? inAppNotificationsEnabled,
    bool? hasSeenEnableCard,
    bool clearFilter = false,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      filter: clearFilter ? null : (filter ?? this.filter),
      inAppNotificationsEnabled:
          inAppNotificationsEnabled ?? this.inAppNotificationsEnabled,
      hasSeenEnableCard: hasSeenEnableCard ?? this.hasSeenEnableCard,
    );
  }

  static const empty = NotificationsState(
    items: <AppNotification>[],
    filter: null,
    inAppNotificationsEnabled: false,
    hasSeenEnableCard: false,
  );
}

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
  final repo = ref.watch(notificationsRepositoryProvider);
  final store = ref.watch(localStoreProvider);
  final auth = ref.watch(authControllerProvider);

  return NotificationsController(
    repo,
    store: store,
    userId: auth.userId,
  )..load();
});

class NotificationsController extends StateNotifier<NotificationsState> {
  final NotificationsRepository _repo;
  final LocalStore _store;
  final String? _userId;

  NotificationsController(
    this._repo, {
    required LocalStore store,
    required String? userId,
  })  : _store = store,
        _userId = (userId ?? '').trim().isEmpty ? null : userId!.trim(),
        super(
          NotificationsState(
            items: const <AppNotification>[],
            filter: null,
            inAppNotificationsEnabled:
                store.getInAppNotificationsEnabled(userId: userId),
            hasSeenEnableCard:
                store.getHasSeenNotificationsEnableCard(userId: userId),
          ),
        );

  Future<void> load() async {
    if (state.items.isNotEmpty) return;

    final fetched = await _repo.fetchInitial();

    // Merge read state from Firestore + device-local cache.
    final cachedRead = _store.getReadNotificationIds(userId: _userId);
    final mergedRead = <String>{...cachedRead};
    for (final n in fetched) {
      if (n.isRead) mergedRead.add(n.id);
    }

    if (mergedRead.length != cachedRead.length) {
      unawaited(
          _store.setReadNotificationIds(mergedRead, userId: _userId));
    }

    final items = fetched
        .map((n) => mergedRead.contains(n.id) ? n.copyWith(isRead: true) : n)
        .toList();

    state = state.copyWith(items: items);
  }

  void setFilter(AppNotificationType? type) {
    if (type == null) {
      state = state.copyWith(clearFilter: true);
    } else {
      state = state.copyWith(filter: type);
    }
  }

  Future<void> markAllRead() async {
    if (state.items.isEmpty) return;

    final ids = state.items.map((e) => e.id).toSet();
    state = state.copyWith(
      items: state.items.map((n) => n.copyWith(isRead: true)).toList(),
    );

    await _store.setReadNotificationIds(
      {..._store.getReadNotificationIds(userId: _userId), ...ids},
      userId: _userId,
    );

    // Best-effort: mark personal inbox docs as read (won't create docs).
    final uid = _userId;
    if (uid != null) {
      for (final id in ids) {
        unawaited(_tryUpdateInboxRead(uid: uid, id: id));
      }
    }
  }

  Future<void> markRead(String id) async {
    final nid = id.trim();
    if (nid.isEmpty) return;

    // Already read?
    final already = state.items.firstWhere(
      (n) => n.id == nid,
      orElse: () => AppNotification(
        id: '__missing__',
        type: AppNotificationType.system,
        title: LocalizedText(ar: '', fr: '', en: ''),
        body: LocalizedText(ar: '', fr: '', en: ''),
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        isRead: true,
      ),
    );
    if (already.id != '__missing__' && already.isRead) return;

    state = state.copyWith(
      items: state.items
          .map((n) => n.id == nid ? n.copyWith(isRead: true) : n)
          .toList(),
    );

    final read = _store.getReadNotificationIds(userId: _userId)..add(nid);
    await _store.setReadNotificationIds(read, userId: _userId);

    final uid = _userId;
    if (uid != null) {
      unawaited(_tryUpdateInboxRead(uid: uid, id: nid));
    }
  }

  Future<void> delete(String id) async {
    final nid = id.trim();
    if (nid.isEmpty) return;

    state = state.copyWith(
        items: state.items.where((n) => n.id != nid).toList());

    // Remove from local read cache.
    final read = _store.getReadNotificationIds(userId: _userId);
    if (read.remove(nid)) {
      unawaited(_store.setReadNotificationIds(read, userId: _userId));
    }

    // Best-effort: delete from personal inbox (won't crash if missing).
    final uid = _userId;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('user_inbox')
            .doc(uid)
            .collection('items')
            .doc(nid)
            .delete();
      } catch (_) {
        // ignore
      }
    }
  }

  /// Keep UI working (this screen expects these methods).
  Future<void> enableInAppNotifications() async {
    state = state.copyWith(
      inAppNotificationsEnabled: true,
      hasSeenEnableCard: true,
    );
    await _store.setInAppNotificationsEnabled(true, userId: _userId);
    await _store.setHasSeenNotificationsEnableCard(true, userId: _userId);
  }

  Future<void> dismissEnableCard() async {
    state = state.copyWith(hasSeenEnableCard: true);
    await _store.setHasSeenNotificationsEnableCard(true, userId: _userId);
  }

  void push({
    required AppNotificationType type,
    required LocalizedText title,
    required LocalizedText body,
    String? targetRoute,
    String? id,
    DateTime? createdAt,
  }) {
    final nid = (id ?? '').trim().isEmpty
        ? 'n_${DateTime.now().millisecondsSinceEpoch}'
        : id!.trim();

    if (state.items.any((e) => e.id == nid)) return;

    // Apply local read cache when inserting (rare, but keeps consistency).
    final cachedRead = _store.getReadNotificationIds(userId: _userId);

    final n = AppNotification(
      id: nid,
      type: type,
      title: title,
      body: body,
      targetRoute: targetRoute,
      createdAt: createdAt ?? DateTime.now(),
      isRead: cachedRead.contains(nid),
    );

    final next = [n, ...state.items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    state = state.copyWith(items: next);
  }

  void pushText({
    required AppNotificationType type,
    required String arTitle,
    required String frTitle,
    required String enTitle,
    required String arBody,
    required String frBody,
    required String enBody,
    String? targetRoute,
    String? id,
    DateTime? createdAt,
  }) {
    push(
      type: type,
      title: LocalizedText(ar: arTitle, fr: frTitle, en: enTitle),
      body: LocalizedText(ar: arBody, fr: frBody, en: enBody),
      targetRoute: targetRoute,
      id: id,
      createdAt: createdAt,
    );
  }

  Future<void> _tryUpdateInboxRead({required String uid, required String id}) async {
    try {
      await FirebaseFirestore.instance
          .collection('user_inbox')
          .doc(uid)
          .collection('items')
          .doc(id)
          .update({
        'read': true,
        'readAtMs': DateTime.now().millisecondsSinceEpoch,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Doc may not exist (broadcast notification) or user may not have access.
    }
  }
}

final notificationsUnreadCountProvider = Provider<int>((ref) {
  final s = ref.watch(notificationsControllerProvider);
  return s.unreadCount;
});
