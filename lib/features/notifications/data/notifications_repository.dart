import '../domain/app_notification.dart';

/// Interface for notifications sources (mock / firestore).
abstract class NotificationsRepository {
  Future<List<AppNotification>> fetchInitial();
}
