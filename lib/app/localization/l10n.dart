import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings)!;
  }

  bool get isAr => locale.languageCode == 'ar';
  bool get isFr => locale.languageCode == 'fr';
  bool get isEn => locale.languageCode == 'en';

  String get _code => locale.languageCode.toLowerCase();

  /// Key-based translation (single source of truth).
  ///
  /// Why this exists:
  /// - The project currently mixes multiple patterns (`_tr(...)`, `tikkiTr(...)`,
  ///   and scattered hardcoded strings). That *inevitably* leads to mismatched
  ///   vocabulary between screens.
  /// - With `tr(key)`, every shared text is defined once, and reused everywhere.
  ///
  /// Supports simple interpolation via `{name}` placeholders.
  String tr(String key, {Map<String, String> args = const {}}) {
    final entry = _k[key];
    String out;

    if (entry == null) {
      // Loud placeholder during development.
      out = kDebugMode ? '⟦$key⟧' : key;
    } else {
      out = entry[_code] ?? entry['en'] ?? entry.values.first;
    }

    if (args.isEmpty) return out;
    var s = out;
    for (final e in args.entries) {
      s = s.replaceAll('{${e.key}}', e.value);
    }
    return s;
  }

  String get appName => 'TIKI';

  String get searchHint => tr('search.hint');

  String get trending => tr('home.trending');
  String get featured => tr('home.featured');

  String get you => tr('nav.you');

  // Bottom navigation labels
  String get navHome => tr('nav.home');
  String get navCategories => tr('nav.categories');
  String get navPublish => tr('nav.publish');
  String get navYou => tr('nav.you');

  // Auth / profile
  String get signIn => tr('auth.sign_in');
  String get signOut => tr('auth.sign_out');
  String get editProfile => tr('profile.edit');
  String get yourName => tr('profile.your_name');
  String get save => tr('common.save');
  String get cancel => tr('common.cancel');
  String get back => tr('common.back');
  String get next => tr('common.next');
  String get later => tr('common.later');

  // Profile setup
  String get profileSetupTitle => tr('profile.setup_title');
  String get profileSetupSubtitle => tr('profile.setup_subtitle');
  String get profileWilaya => tr('profile.wilaya');
  String get profileMoughataa => tr('profile.moughataa');
  String get profileEnterNameOrLater => tr('profile.enter_name_or_later');

  // Router / errors
  String get pageNotFound => tr('router.page_not_found');
  String get backHome => tr('router.back_home');

  // Safety & support
  String get blockedSellers => tr('you.blocked');
  String get support => tr('support.title');
  String get terms => tr('legal.terms');
  String get privacy => tr('legal.privacy');

  // Reporting / blocking
  String get reportProduct => tr('report.product');
  String get blockSeller => tr('block.seller');
  String get unblock => tr('block.unblock');

  String get settings => tr('settings.title');

  String get likes => tr('likes.title');
  String get recentlyViewed => tr('home.recently_viewed');
  String get youMayLike => tr('home.you_may_like');

  String publishedAgo(String v) => tr('time.ago', args: {'v': v});

  // ---------------------------------------------------------------------------
  // Central dictionary (AR / FR / EN)
  // ---------------------------------------------------------------------------
  static const Map<String, Map<String, String>> _k = {
    // Common
    'common.save': {'ar': 'حفظ', 'fr': 'Enregistrer', 'en': 'Save'},
    'common.cancel': {'ar': 'إلغاء', 'fr': 'Annuler', 'en': 'Cancel'},
    'common.back': {'ar': 'السابق', 'fr': 'Précédent', 'en': 'Back'},
    'common.next': {'ar': 'التالي', 'fr': 'Suivant', 'en': 'Next'},
    'common.later': {'ar': 'لاحقاً', 'fr': 'Plus tard', 'en': 'Later'},
    'common.close': {'ar': 'إغلاق', 'fr': 'Fermer', 'en': 'Close'},
    'common.unavailable_feature': {
      'ar': 'هذه الميزة غير متاحة حالياً',
      'fr': 'Fonctionnalité indisponible pour le moment',
      'en': 'This feature is not available right now',
    },

    // Search
    'search.hint': {
      'ar': 'ابحث عن منتج، خدمة، عقار، أو حي…',
      'fr': 'Recherchez un produit, service, quartier…',
      'en': 'Search products, services, or neighborhoods…',
    },

    // Home
    'home.trending': {'ar': 'الرائج', 'fr': 'Tendance', 'en': 'Trending'},
    'home.featured': {'ar': 'مميّز', 'fr': 'Mis en avant', 'en': 'Featured'},
    'home.recently_viewed': {
      'ar': 'شوهد مؤخراً',
      'fr': 'Vu récemment',
      'en': 'Recently viewed'
    },
    'home.you_may_like': {
      'ar': 'قد يعجبك',
      'fr': 'Vous aimerez peut-être',
      'en': 'You may like'
    },

    // Nav
    'nav.home': {'ar': 'الرئيسية', 'fr': 'Accueil', 'en': 'Home'},
    'nav.categories': {'ar': 'الفئات', 'fr': 'Catégories', 'en': 'Categories'},
    'nav.publish': {'ar': 'نشر', 'fr': 'Publier', 'en': 'Publish'},
    'nav.you': {'ar': 'أنت', 'fr': 'Vous', 'en': 'You'},

    // Categories screen
    'categories.title': {
      'ar': 'الفئات',
      'fr': 'Catégories',
      'en': 'Categories'
    },
    'categories.pick_category_then_sub': {
      'ar': 'اختر فئة ثم اختر قسمًا فرعيًا',
      'fr': 'Choisissez une catégorie puis une sous-catégorie',
      'en': 'Pick a category, then a subcategory',
    },
    'categories.choose_subcategory': {
      'ar': 'اختر قسمًا فرعيًا',
      'fr': 'Choisissez une sous-catégorie',
      'en': 'Choose a subcategory',
    },
    'categories.guest_banner_title': {
      'ar': 'سجّل الآن لتحفظ بياناتك وتستفيد من العروض',
      'fr':
          'Connectez-vous pour sauvegarder vos données et profiter des offres',
      'en': 'Sign in to save your data and get offers',
    },
    'categories.guest_banner_subtitle': {
      'ar': '• لا تفقد مفضلاتك وسلتك  • دخول في السحب  • مزايا VIP',
      'fr': '• Favoris/panier synchronisés  • Tirages  • Avantages VIP',
      'en': '• Synced favorites/cart  • Giveaways  • VIP perks',
    },

    // Auth / Profile
    'auth.sign_in': {'ar': 'تسجيل الدخول', 'fr': 'Connexion', 'en': 'Sign in'},
    'auth.sign_in_short': {'ar': 'تسجيل', 'fr': 'Connexion', 'en': 'Sign in'},
    'auth.sign_out': {
      'ar': 'تسجيل الخروج',
      'fr': 'Déconnexion',
      'en': 'Sign out'
    },
    'profile.edit': {
      'ar': 'تعديل بياناتي',
      'fr': 'Modifier mon profil',
      'en': 'Edit profile'
    },
    'profile.your_name': {'ar': 'اسمك', 'fr': 'Votre nom', 'en': 'Your name'},

    // Profile setup
    'profile.setup_title': {
      'ar': 'إعداد ملفك (اختياري)',
      'fr': 'Profil (optionnel)',
      'en': 'Profile (optional)'
    },
    'profile.setup_subtitle': {
      'ar': 'يساعدنا هذا لعرض "قريب منك" وتسهيل الفلترة.',
      'fr': 'Utile pour "près de vous" et les filtres.',
      'en': 'Helps for "near you" and filtering.'
    },
    'profile.wilaya': {'ar': 'الولاية', 'fr': 'Wilaya', 'en': 'Wilaya'},
    'profile.moughataa': {
      'ar': 'المقاطعة',
      'fr': 'Moughataa',
      'en': 'Moughataa'
    },
    'profile.enter_name_or_later': {
      'ar': 'أدخل الاسم أو اختر "لاحقاً".',
      'fr': 'Entrez un nom ou choisissez "Plus tard".',
      'en': 'Enter a name or choose "Later".'
    },

    // You / Settings
    'you.blocked': {'ar': 'المحظورون', 'fr': 'Bloqués', 'en': 'Blocked'},
    'settings.title': {'ar': 'الإعدادات', 'fr': 'Paramètres', 'en': 'Settings'},
    'likes.title': {'ar': 'الإعجابات', 'fr': 'Favoris', 'en': 'Likes'},

    // Legal / Support
    'support.title': {'ar': 'الدعم', 'fr': 'Support', 'en': 'Support'},
    'legal.terms': {'ar': 'الشروط', 'fr': 'Conditions', 'en': 'Terms'},
    'legal.privacy': {
      'ar': 'الخصوصية',
      'fr': 'Confidentialité',
      'en': 'Privacy'
    },

    // Reporting / Blocking
    'report.product': {
      'ar': 'الإبلاغ عن المنتج',
      'fr': "Signaler l'annonce",
      'en': 'Report'
    },
    'block.seller': {
      'ar': 'حظر البائع',
      'fr': 'Bloquer le vendeur',
      'en': 'Block seller'
    },
    'block.unblock': {'ar': 'إلغاء الحظر', 'fr': 'Débloquer', 'en': 'Unblock'},

    // Time
    'time.ago': {'ar': 'قبل {v}', 'fr': 'il y a {v}', 'en': '{v} ago'},

    // Router
    'router.page_not_found': {
      'ar': 'الصفحة غير موجودة',
      'fr': 'Page introuvable',
      'en': 'Page not found'
    },
    'router.back_home': {
      'ar': 'العودة للرئيسية',
      'fr': 'Accueil',
      'en': 'Home'
    },

    // Publish wizard
    'publish.title_new': {'ar': 'نشر إعلان', 'fr': 'Publier', 'en': 'Publish'},
    'publish.title_edit': {
      'ar': 'تعديل الإعلان',
      'fr': 'Modifier',
      'en': 'Edit'
    },
    'publish.step_photos': {'ar': 'الصور', 'fr': 'Photos', 'en': 'Photos'},
    'publish.step_info': {'ar': 'المعلومات', 'fr': 'Infos', 'en': 'Info'},
    'publish.step_location': {
      'ar': 'الموقع',
      'fr': 'Localisation',
      'en': 'Location'
    },
    'publish.step_contact': {'ar': 'التواصل', 'fr': 'Contact', 'en': 'Contact'},
    'publish.step_preview': {'ar': 'المعاينة', 'fr': 'Aperçu', 'en': 'Preview'},
    'publish.photos_tip_title': {
      'ar': 'نصيحة للصور',
      'fr': 'Conseil photos',
      'en': 'Photo tip'
    },
    'publish.photos_tip_body': {
      'ar': 'صور المنتج بإضاءة جيدة وخلفية بسيطة. 3 صور تكفي كبداية.',
      'fr':
          'Des photos avec bonne lumière et fond simple. 3 photos suffisent pour commencer.',
      'en':
          'Use good lighting and a simple background. 3 photos are enough to start.',
    },
    'publish.field_title': {'ar': 'عنوان المنتج', 'fr': 'Titre', 'en': 'Title'},
    'publish.field_details': {
      'ar': 'تفاصيل (اختياري)',
      'fr': 'Détails (optionnel)',
      'en': 'Details (optional)'
    },
    'publish.field_price': {
      'ar': 'السعر (MRU) (اختياري)',
      'fr': 'Prix (MRU) (optionnel)',
      'en': 'Price (MRU) (optional)'
    },
    'publish.required': {'ar': 'مطلوب', 'fr': 'Requis', 'en': 'Required'},
    'publish.tap_to_choose': {
      'ar': 'اضغط للاختيار',
      'fr': 'Appuyez pour choisir',
      'en': 'Tap to choose'
    },

    // Product details
    'product.details_title': {
      'ar': 'تفاصيل المنتج',
      'fr': 'Détails du produit',
      'en': 'Product details'
    },
    'product.seller_note': {
      'ar': 'ملاحظة البائع',
      'fr': 'Note du vendeur',
      'en': 'Seller note'
    },
    'product.has_warranty': {
      'ar': 'هذا المنتج عليه ضمان',
      'fr': 'Ce produit a une garantie',
      'en': 'This product has a warranty'
    },
    'product.policy': {'ar': 'السياسة', 'fr': 'Politique', 'en': 'Policy'},

    // Attribute labels (used across product UI)
    'attr.type': {'ar': 'النوع', 'fr': 'Type', 'en': 'Type'},
    'attr.brand': {'ar': 'الماركة', 'fr': 'Marque', 'en': 'Brand'},
    'attr.model': {'ar': 'الموديل', 'fr': 'Modèle', 'en': 'Model'},
    'attr.storage': {'ar': 'السعة', 'fr': 'Stockage', 'en': 'Storage'},
    'attr.color': {'ar': 'اللون', 'fr': 'Couleur', 'en': 'Color'},
    'attr.condition': {'ar': 'الحالة', 'fr': 'État', 'en': 'Condition'},
    'attr.year': {'ar': 'السنة', 'fr': 'Année', 'en': 'Year'},
    'attr.mileage': {'ar': 'المسافة', 'fr': 'Kilométrage', 'en': 'Mileage'},
    'attr.transmission': {
      'ar': 'ناقل الحركة',
      'fr': 'Transmission',
      'en': 'Transmission'
    },
    'attr.fuel': {'ar': 'الوقود', 'fr': 'Carburant', 'en': 'Fuel'},
    'attr.origin': {'ar': 'المنشأ', 'fr': 'Origine', 'en': 'Origin'},
    'attr.mileage_km': {
      'ar': 'المسافة (كم)',
      'fr': 'Kilométrage (km)',
      'en': 'Mileage (km)'
    },
    'attr.area_m2': {
      'ar': 'المساحة (م²)',
      'fr': 'Surface (m²)',
      'en': 'Area (m²)'
    },
    'attr.rooms': {'ar': 'الغرف', 'fr': 'Pièces', 'en': 'Rooms'},
    'attr.size': {'ar': 'المقاس', 'fr': 'Taille', 'en': 'Size'},
    'attr.location_note': {
      'ar': 'ملاحظة الموقع',
      'fr': 'Note de localisation',
      'en': 'Location note'
    },
  };
}

extension AppStringsX on BuildContext {
  AppStrings get s => AppStrings.of(this);
  String tr(String key, {Map<String, String> args = const {}}) =>
      s.tr(key, args: args);
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const ['ar', 'fr', 'en'].contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale);

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
