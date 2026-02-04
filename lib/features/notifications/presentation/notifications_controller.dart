import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/firestore_notifications_repository.dart';
import '../data/notifications_repository.dart';
import '../domain/app_notification.dart';
import '../shared/notifications_i18n.dart';

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
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
  return NotificationsController(repo)..load();
});

class NotificationsController extends StateNotifier<NotificationsState> {
  final NotificationsRepository _repo;

  NotificationsController(this._repo) : super(NotificationsState.empty);

  Future<void> load() async {
    if (state.items.isNotEmpty) return;
    final items = await _repo.fetchInitial();
    state = state.copyWith(items: items);
  }

  void setFilter(AppNotificationType? type) {
    if (type == null) {
      state = state.copyWith(clearFilter: true);
    } else {
      state = state.copyWith(filter: type);
    }
  }

  void markAllRead() {
    state = state.copyWith(
      items: state.items.map((n) => n.copyWith(isRead: true)).toList(),
    );
  }

  void markRead(String id) {
    state = state.copyWith(
      items: state.items
          .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
          .toList(),
    );
  }

  void delete(String id) {
    state =
        state.copyWith(items: state.items.where((n) => n.id != id).toList());
  }

  /// Keep UI working (this screen expects these methods).
  void enableInAppNotifications() {
    state = state.copyWith(
      inAppNotificationsEnabled: true,
      hasSeenEnableCard: true,
    );
  }

  void dismissEnableCard() {
    state = state.copyWith(hasSeenEnableCard: true);
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

    final n = AppNotification(
      id: nid,
      type: type,
      title: title,
      body: body,
      targetRoute: targetRoute,
      createdAt: createdAt ?? DateTime.now(),
      isRead: false,
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
}

final notificationsUnreadCountProvider = Provider<int>((ref) {
  final s = ref.watch(notificationsControllerProvider);
  return s.unreadCount;
});
