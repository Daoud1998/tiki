import 'package:flutter/material.dart';
import '../shared/notifications_i18n.dart';

/// Notification categories used in the app (no chat/messages).
enum AppNotificationType {
  /// Seller-related: publish/reject/sold/hidden/views... etc
  sales,

  /// Discounts and promos
  deals,

  /// System + safety + important app announcements
  system,
}

@immutable
class AppNotification {
  final String id;
  final AppNotificationType type;

  final LocalizedText title;
  final LocalizedText body;

  /// Optional route target. Example: '/discounts'
  final String? targetRoute;

  /// When it happened (used for sorting)
  final DateTime createdAt;

  /// Read state
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.targetRoute,
    this.isRead = false,
  });

  AppNotification copyWith({
    AppNotificationType? type,
    LocalizedText? title,
    LocalizedText? body,
    String? targetRoute,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return AppNotification(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      targetRoute: targetRoute ?? this.targetRoute,
      isRead: isRead ?? this.isRead,
    );
  }
}
