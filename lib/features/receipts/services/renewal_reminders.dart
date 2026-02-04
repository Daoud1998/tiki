import '../../notifications/domain/app_notification.dart';
import '../../notifications/presentation/notifications_controller.dart';
import '../domain/service_receipt.dart';

/// Emits in-app renewal reminders based on receipts.
///
/// NOTE: This is intentionally in-app (not system push) until Firebase/FCM
/// or flutter_local_notifications is wired.
class ReceiptsRenewalReminders {
  static void run(
    List<ServiceReceipt> receipts,
    NotificationsController nCtrl,
  ) {
    final now = DateTime.now();

    for (final r in receipts) {
      if (r.status != ServiceReceiptStatus.active) continue;
      final end = r.endsAt;
      if (end == null) continue;

      final left = end.difference(now);

      final subjId = (r.subjectId ?? '').trim();
      if (subjId.isEmpty) continue;

      // Reuse the same ids/routes as existing mock reminders to avoid duplicates.
      final base = 'vip_${subjId}';

      final targetRoute = '/you/listings';

      if (left.isNegative || left == Duration.zero) {
        nCtrl.pushText(
          id: '${base}_expired',
          type: AppNotificationType.sales,
          arTitle: 'انتهى VIP',
          frTitle: 'VIP expiré',
          enTitle: 'VIP expired',
          arBody: 'انتهت مدة VIP. إذا كان الإعلان مهمًا لك، يمكنك تجديده الآن.',
          frBody: 'Votre VIP a expiré. Vous pouvez renouveler si nécessaire.',
          enBody: 'VIP has expired. Renew if needed.',
          targetRoute: targetRoute,
        );
        continue;
      }

      if (left <= const Duration(hours: 2)) {
        nCtrl.pushText(
          id: '${base}_exp2h',
          type: AppNotificationType.sales,
          arTitle: 'VIP سينتهي قريبًا',
          frTitle: 'VIP expire bientôt',
          enTitle: 'VIP ending soon',
          arBody: 'سيتم إنهاء VIP خلال أقل من ساعتين.',
          frBody: 'Votre VIP expire dans moins de 2 heures.',
          enBody: 'VIP ends in under 2 hours.',
          targetRoute: targetRoute,
        );
      } else if (left <= const Duration(hours: 24)) {
        nCtrl.pushText(
          id: '${base}_exp24h',
          type: AppNotificationType.sales,
          arTitle: 'تذكير: VIP ينتهي خلال 24 ساعة',
          frTitle: 'Rappel : VIP expire sous 24h',
          enTitle: 'Reminder: VIP ends within 24h',
          arBody: 'VIP سينتهي قريبًا. إذا كان مهمًا لك، جدّد الآن.',
          frBody: 'Votre VIP expire bientôt. Renouvelez si nécessaire.',
          enBody: 'VIP is ending soon. Renew if needed.',
          targetRoute: targetRoute,
        );
      }
    }
  }
}
