import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Lightweight notification model (works now, scales later with Firebase).
class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
      );
}

class NotificationsController extends StateNotifier<List<AppNotification>> {
  NotificationsController() : super(const []);

  void add(AppNotification n) => state = [n, ...state];

  void markRead(String id, bool read) {
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isRead: read) else n,
    ];
  }

  void markAllRead() {
    state = [for (final n in state) n.copyWith(isRead: true)];
  }

  void clear() => state = const [];

  /// Optional demo seed (call manually while testing).
  void seedDemo() {
    if (state.isNotEmpty) return;
    add(
      AppNotification(
        id: 'welcome',
        title: 'Welcome to Tkii',
        body: 'Your notification center is ready.',
        createdAt: DateTime.now(),
      ),
    );
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsController, List<AppNotification>>(
  (ref) => NotificationsController(),
);

final notificationsUnreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider);
  return list.where((n) => !n.isRead).length;
});
