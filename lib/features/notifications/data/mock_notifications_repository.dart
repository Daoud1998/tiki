import 'dart:math';
import '../domain/app_notification.dart';
import '../shared/notifications_i18n.dart';

abstract class NotificationsRepository {
  Future<List<AppNotification>> fetchInitial();
}

/// Mock repository: works offline, no Firestore needed.
/// Later you can replace this with a Firestore-backed repository.
class MockNotificationsRepository implements NotificationsRepository {
  @override
  Future<List<AppNotification>> fetchInitial() async {
    // Simulate tiny delay
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final now = DateTime.now();
    final r = Random(42);

    // 10 sample notifications (NO chat/messages)
    final items = <AppNotification>[
      AppNotification(
        id: 'n1',
        type: AppNotificationType.deals,
        title: const LocalizedText(
          ar: 'تخفيضات اليوم داخل Tikki',
          fr: 'Promos du jour sur Tikki',
          en: 'Today discounts on Tikki',
        ),
        body: const LocalizedText(
          ar: 'اضغط لعرض كل المنتجات التي عليها تخفيض.',
          fr: 'Touchez pour voir tous les produits en promo.',
          en: 'Tap to see all discounted items.',
        ),
        targetRoute: '/discounts',
        createdAt: now.subtract(const Duration(minutes: 10)),
        isRead: false,
      ),
      AppNotification(
        id: 'n2',
        type: AppNotificationType.sales,
        title: const LocalizedText(
          ar: 'تم نشر إعلانك بنجاح',
          fr: 'Votre annonce est publiée',
          en: 'Your listing is live',
        ),
        body: const LocalizedText(
          ar: 'أصبح منتجك ظاهرًا للناس الآن.',
          fr: 'Votre produit est visible maintenant.',
          en: 'Your product is now visible.',
        ),
        targetRoute: '/profile', // عدّلها لمسار منتجات البائع عندك إن وجدت
        createdAt: now.subtract(const Duration(hours: 3)),
        isRead: r.nextBool(),
      ),
      AppNotification(
        id: 'n3',
        type: AppNotificationType.sales,
        title: const LocalizedText(
          ar: 'تم رفض إعلانك',
          fr: 'Annonce refusée',
          en: 'Listing rejected',
        ),
        body: const LocalizedText(
          ar: 'السبب: صور غير واضحة أو سعر غير مكتمل.',
          fr: 'Raison : photos floues ou prix incomplet.',
          en: 'Reason: unclear photos or missing price.',
        ),
        targetRoute: '/publish', // لو عندك صفحة تعديل الإعلان، عدّل المسار
        createdAt: now.subtract(const Duration(hours: 6)),
        isRead: false,
      ),
      AppNotification(
        id: 'n4',
        type: AppNotificationType.deals,
        title: const LocalizedText(
          ar: 'رائج التخفيضات الآن',
          fr: 'Top promos maintenant',
          en: 'Trending deals now',
        ),
        body: const LocalizedText(
          ar: 'أفضل العروض في الأعلى. لا تفوّت الفرصة.',
          fr: 'Les meilleures offres en haut. Ne ratez pas.',
          en: 'Best offers at the top. Don’t miss out.',
        ),
        targetRoute: '/discounts',
        createdAt: now.subtract(const Duration(hours: 10)),
        isRead: r.nextBool(),
      ),
      AppNotification(
        id: 'n5',
        type: AppNotificationType.system,
        title: const LocalizedText(
          ar: 'نصيحة أمان',
          fr: 'Conseil de sécurité',
          en: 'Safety tip',
        ),
        body: const LocalizedText(
          ar: 'لا تحوّل عربون قبل المعاينة. استخدم واتساب بحذر.',
          fr: "N'envoyez pas d'acompte avant de voir le produit.",
          en: "Don't pay a deposit before inspection.",
        ),
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        isRead: true,
      ),
      AppNotification(
        id: 'n6',
        type: AppNotificationType.sales,
        title: const LocalizedText(
          ar: 'تم تعليم المنتج كمباع',
          fr: 'Produit marqué vendu',
          en: 'Marked as sold',
        ),
        body: const LocalizedText(
          ar: 'لم يعد المنتج يظهر ضمن المعروض للبيع.',
          fr: "Le produit n'apparaît plus comme disponible.",
          en: 'The product is no longer listed as available.',
        ),
        createdAt: now.subtract(const Duration(days: 2, hours: 3)),
        isRead: r.nextBool(),
      ),
      AppNotification(
        id: 'n7',
        type: AppNotificationType.deals,
        title: const LocalizedText(
          ar: 'خصومات على الإلكترونيات',
          fr: 'Promos sur l’électronique',
          en: 'Electronics discounts',
        ),
        body: const LocalizedText(
          ar: 'عروض جديدة وصلت للتو.',
          fr: 'De nouvelles offres viennent d’arriver.',
          en: 'New offers just arrived.',
        ),
        targetRoute: '/discounts',
        createdAt: now.subtract(const Duration(days: 3)),
        isRead: r.nextBool(),
      ),
      AppNotification(
        id: 'n8',
        type: AppNotificationType.system,
        title: const LocalizedText(
          ar: 'تحديث مهم داخل التطبيق',
          fr: 'Mise à jour importante',
          en: 'Important in-app update',
        ),
        body: const LocalizedText(
          ar: 'أضفنا تحسينات على الصفحة الرئيسية والإعلانات.',
          fr: "Nous avons amélioré la page d’accueil et les annonces.",
          en: 'We improved the home page and ads.',
        ),
        createdAt: now.subtract(const Duration(days: 4, hours: 1)),
        isRead: true,
      ),
      AppNotification(
        id: 'n9',
        type: AppNotificationType.sales,
        title: const LocalizedText(
          ar: 'مشاهدات كثيرة على منتجك',
          fr: 'Beaucoup de vues sur votre produit',
          en: 'Lots of views on your product',
        ),
        body: const LocalizedText(
          ar: 'جرّب تخفيض السعر أو أضف صورًا أوضح.',
          fr: 'Essayez de baisser le prix ou ajouter de meilleures photos.',
          en: 'Try lowering price or adding clearer photos.',
        ),
        createdAt: now.subtract(const Duration(days: 6)),
        isRead: r.nextBool(),
      ),
      AppNotification(
        id: 'n10',
        type: AppNotificationType.system,
        title: const LocalizedText(
          ar: 'تذكير بسياسات النشر',
          fr: 'Rappel des règles de publication',
          en: 'Publishing rules reminder',
        ),
        body: const LocalizedText(
          ar: 'الصور الواضحة والسعر الصحيح يساعدان على البيع أسرع.',
          fr: 'Des photos claires et un bon prix aident à vendre plus vite.',
          en: 'Clear photos and correct pricing help you sell faster.',
        ),
        createdAt: now.subtract(const Duration(days: 7, hours: 2)),
        isRead: true,
      ),
    ];

    // Sort newest first
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }
}
