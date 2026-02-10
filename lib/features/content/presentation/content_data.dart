import 'package:flutter/widgets.dart';
import '../../../core/i18n/tikki_tr.dart' show tikkiTr;
export '../../../core/i18n/tikki_tr.dart' show tikkiTr;

/// Simple local (non-Firebase) content store.
///
/// - Uses stable IDs (e.g. 'privacy', 'terms') so UI stays consistent
///   even when the language changes.
/// - Text is intentionally short and structured so you can later replace
///   it with HTML/Markdown, Firestore docs, or remote config.

class TikkiContentSection {
  final String? headingAr;
  final String? headingFr;
  final String? headingEn;
  final String bodyAr;
  final String bodyFr;
  final String bodyEn;

  const TikkiContentSection({
    this.headingAr,
    this.headingFr,
    this.headingEn,
    required this.bodyAr,
    required this.bodyFr,
    required this.bodyEn,
  });

  String? heading(BuildContext c) => tikkiTr(
        c,
        ar: headingAr ?? '',
        fr: headingFr ?? '',
        en: headingEn ?? '',
      ).trim().isEmpty
          ? null
          : tikkiTr(c,
              ar: headingAr ?? '', fr: headingFr ?? '', en: headingEn ?? '');

  String body(BuildContext c) => tikkiTr(c, ar: bodyAr, fr: bodyFr, en: bodyEn);
}

class TikkiPolicyArticle {
  final String id;
  final String titleAr;
  final String titleFr;
  final String titleEn;
  final List<TikkiContentSection> sections;

  const TikkiPolicyArticle({
    required this.id,
    required this.titleAr,
    required this.titleFr,
    required this.titleEn,
    required this.sections,
  });

  String title(BuildContext c) =>
      tikkiTr(c, ar: titleAr, fr: titleFr, en: titleEn);
}

const List<TikkiPolicyArticle> tikkiPolicyArticles = [
  TikkiPolicyArticle(
    id: 'privacy',
    titleAr: 'سياسة الخصوصية',
    titleFr: 'Confidentialité',
    titleEn: 'Privacy Policy',
    sections: [
      TikkiContentSection(
        headingAr: null,
        headingFr: null,
        headingEn: null,
        bodyAr:
            'آخر تحديث: 10 فبراير 2026\n\nنحن نحترم خصوصيتك. توضّح هذه السياسة نوع البيانات التي قد نجمعها، وكيف نستخدمها، ومتى نشاركها. باستخدامك للتطبيق، أنت توافق على هذه السياسة.',
        bodyFr:
            'Dernière mise à jour : 10 février 2026\n\nNous respectons votre vie privée. Cette politique explique les données que nous pouvons collecter, comment nous les utilisons et quand nous les partageons. En utilisant l\'application, vous acceptez cette politique.',
        bodyEn:
            'Last updated: 10 Feb 2026\n\nWe respect your privacy. This policy explains the data we may collect, how we use it, and when we share it. By using the app, you agree to this policy.',
      ),
      TikkiContentSection(
        headingAr: 'ما الذي نجمعه؟',
        headingFr: 'Données collectées',
        headingEn: 'What we collect',
        bodyAr: 'قد نجمع الأنواع التالية من البيانات حسب استخدامك للتطبيق:\n'
            '• بيانات الحساب: رقم الهاتف، الاسم (إن وُجد)، وصورة الحساب (إن وُجد).\n'
            '• بيانات الإعلان: العنوان، الوصف، الفئة، السعر (إن وُجد)، الصور/الفيديو، والموقع التقريبي (الولاية/المدينة).\n'
            '• بيانات الاستخدام: كلمات البحث، التفضيلات، التفاعلات داخل التطبيق (مثل الإعجاب/الحفظ).\n'
            '• بيانات تقنية: نوع الجهاز، نظام التشغيل، مُعرّفات القياس/الأعطال، وسجلات الأخطاء لتحسين الاستقرار.',
        bodyFr:
            'Nous pouvons collecter les données suivantes selon votre utilisation :\n'
            '• Compte : numéro de téléphone, nom (si fourni), photo de profil (si fournie).\n'
            '• Annonce : titre, description, catégorie, prix (si fourni), photos/vidéo, localisation approximative (région/ville).\n'
            '• Utilisation : termes recherchés, préférences, interactions (ex. favoris).\n'
            '• Technique : appareil, OS, identifiants de mesure/crash, journaux d\'erreur.',
        bodyEn:
            'We may collect the following depending on how you use the app:\n'
            '• Account: phone number, name (if provided), profile photo (if provided).\n'
            '• Listing: title, description, category, price (if provided), photos/video, approximate location (region/city).\n'
            '• Usage: search terms, preferences, in-app interactions (e.g., favorites).\n'
            '• Technical: device type, OS, analytics/crash identifiers, error logs.',
      ),
      TikkiContentSection(
        headingAr: 'كيف نستخدم المعلومات؟',
        headingFr: 'Utilisation',
        headingEn: 'How we use it',
        bodyAr: 'نستخدم البيانات من أجل:\n'
            '• تشغيل التطبيق وعرض إعلاناتك وإدارة حسابك.\n'
            '• تمكين التواصل بين البائع والمشتري (مثل إظهار رقم الاتصال/الواتساب إن اخترت ذلك).\n'
            '• تحسين البحث والفرز وتجربة الاستخدام.\n'
            '• كشف الاحتيال وإساءة الاستخدام ومراجعة البلاغات والمحتوى.\n'
            '• إرسال إشعارات مهمة (مثل حالة النشر/المراجعة) عند الحاجة.',
        bodyFr:
            'Nous utilisons vos données pour :\n'
            '• Exploiter l\'application, afficher vos annonces et gérer votre compte.\n'
            '• Faciliter le contact entre vendeur et acheteur (ex. afficher téléphone/WhatsApp si vous l\'autorisez).\n'
            '• Améliorer la recherche, le tri et l\'expérience.\n'
            '• Détecter la fraude, traiter les signalements et modérer le contenu.\n'
            '• Envoyer des notifications importantes (statut de publication/revue).',
        bodyEn:
            'We use data to:\n'
            '• Operate the app, show your listings, and manage your account.\n'
            '• Enable buyer–seller contact (e.g., showing phone/WhatsApp if you allow it).\n'
            '• Improve search, sorting, and user experience.\n'
            '• Detect fraud/abuse, handle reports, and moderate content.\n'
            '• Send important notifications (publishing/review status) when needed.',
      ),
      TikkiContentSection(
        headingAr: 'متى نشارك البيانات؟',
        headingFr: 'Partage',
        headingEn: 'When we share data',
        bodyAr: 'قد نشارك البيانات في الحالات التالية فقط:\n'
            '• مع المستخدمين الآخرين: معلومات الإعلان العامة التي تنشرها (العنوان/الصور/السعر/الموقع التقريبي) ووسيلة التواصل التي تختار إظهارها.\n'
            '• مع مزوّدي الخدمة: خدمات الاستضافة/التخزين/الإحصاءات اللازمة لتشغيل التطبيق (مثل خدمات سحابية).\n'
            '• لأسباب قانونية: عند طلب الجهات المختصة أو لحماية حقوقنا وحقوق المستخدمين.',
        bodyFr:
            'Nous pouvons partager les données uniquement dans ces cas :\n'
            '• Avec les autres utilisateurs : les infos publiques de votre annonce et le moyen de contact que vous choisissez d\'afficher.\n'
            '• Avec des prestataires : hébergement, stockage, analytics nécessaires au fonctionnement.\n'
            '• Raisons légales : demandes officielles ou protection des droits.',
        bodyEn:
            'We may share data only in these cases:\n'
            '• With other users: public listing info you publish and the contact method you choose to show.\n'
            '• With service providers: hosting, storage, analytics required to operate the app.\n'
            '• Legal reasons: official requests or to protect our rights and users.',
      ),
      TikkiContentSection(
        headingAr: 'الاحتفاظ والحذف',
        headingFr: 'Conservation & suppression',
        headingEn: 'Retention & deletion',
        bodyAr:
            'نحتفظ بالبيانات طالما كان حسابك نشطاً أو حسب الحاجة لتشغيل الخدمة. يمكنك حذف إعلانك من داخل التطبيق. عند طلب حذف الحساب، قد نحتفظ ببعض البيانات لفترة محدودة للامتثال القانوني أو مكافحة الاحتيال.',
        bodyFr:
            'Nous conservons les données tant que votre compte est actif ou si nécessaire au service. Vous pouvez supprimer vos annonces. En cas de suppression de compte, certaines données peuvent être conservées brièvement pour des raisons légales/anti-fraude.',
        bodyEn:
            'We retain data while your account is active or as needed to provide the service. You can delete your listings in-app. If you request account deletion, some data may be retained briefly for legal/anti-fraud purposes.',
      ),
      TikkiContentSection(
        headingAr: 'خياراتك وحقوقك',
        headingFr: 'Vos choix',
        headingEn: 'Your choices',
        bodyAr: 'يمكنك:\n'
            '• تعديل/حذف إعلاناتك في أي وقت من صفحة «إعلاناتي».\n'
            '• التحكم في معلومات التواصل التي تظهر للآخرين.\n'
            '• طلب مساعدة/حذف حساب عبر الدعم داخل التطبيق.',
        bodyFr:
            'Vous pouvez :\n'
            '• Modifier/supprimer vos annonces à tout moment (Mes annonces).\n'
            '• Contrôler les infos de contact affichées.\n'
            '• Demander de l\'aide ou la suppression du compte via le support.',
        bodyEn:
            'You can:\n'
            '• Edit/delete your listings anytime (My listings).\n'
            '• Control which contact details you show.\n'
            '• Request help or account deletion via in-app support.',
      ),
      TikkiContentSection(
        headingAr: 'الأمان والأطفال',
        headingFr: 'Sécurité & enfants',
        headingEn: 'Security & children',
        bodyAr:
            'نستخدم إجراءات أمنية معقولة لحماية البيانات (مثل التشفير أثناء النقل وضوابط الوصول). التطبيق غير موجّه لمن هم دون 13 عاماً. إذا كنت تعتقد أن طفلاً زوّدنا ببياناته، تواصل معنا لحذفها.',
        bodyFr:
            'Nous appliquons des mesures de sécurité raisonnables (chiffrement en transit, contrôles d\'accès). L\'application n\'est pas destinée aux moins de 13 ans. Si un enfant a fourni des données, contactez-nous pour les supprimer.',
        bodyEn:
            'We use reasonable security measures (encryption in transit, access controls). The app is not intended for children under 13. If you believe a child provided data, contact us to delete it.',
      ),
    ],
  ),
  TikkiPolicyArticle(
    id: 'terms',
    titleAr: 'الشروط والأحكام',
    titleFr: 'Conditions',
    titleEn: 'Terms & Conditions',
    sections: [
      TikkiContentSection(
        headingAr: null,
        headingFr: null,
        headingEn: null,
        bodyAr:
            'آخر تحديث: 10 فبراير 2026\n\nمرحباً بك في Tikki. باستخدامك للتطبيق، أنت توافق على هذه الشروط. إذا لم توافق، يرجى عدم استخدام التطبيق.',
        bodyFr:
            'Dernière mise à jour : 10 février 2026\n\nBienvenue sur Tikki. En utilisant l\'application, vous acceptez ces conditions. Si vous n\'êtes pas d\'accord, veuillez ne pas utiliser l\'application.',
        bodyEn:
            'Last updated: 10 Feb 2026\n\nWelcome to Tikki. By using the app, you agree to these terms. If you do not agree, please do not use the app.',
      ),
      TikkiContentSection(
        headingAr: 'من يمكنه استخدام التطبيق؟',
        headingFr: 'Éligibilité',
        headingEn: 'Eligibility',
        bodyAr:
            'يجب أن تكون قادراً قانونياً على إبرام اتفاقات. أنت مسؤول عن استخدام حسابك وعن أي نشاط يتم عبره.',
        bodyFr:
            'Vous devez être légalement capable de conclure des accords. Vous êtes responsable de votre compte et de toute activité effectuée via celui‑ci.',
        bodyEn:
            'You must be legally able to enter agreements. You are responsible for your account and any activity under it.',
      ),
      TikkiContentSection(
        headingAr: 'مسؤولية المحتوى',
        headingFr: 'Contenu interdit',
        headingEn: 'Content responsibility',
        bodyAr:
            'أنت (الناشر) مسؤول عن صحة معلومات إعلانك وصوره وسعره. يجب أن يكون المحتوى واضحاً وغير مضلل. نحتفظ بحق إزالة المحتوى أو تعطيل الحساب عند الاشتباه بالمخالفة.',
        bodyFr:
            'Vous (l\'éditeur) êtes responsable des informations, photos et prix. Le contenu doit être clair et non trompeur. Nous pouvons supprimer du contenu ou désactiver un compte en cas de violation.',
        bodyEn:
            'You (the publisher) are responsible for listing details, photos, and price. Content must be clear and not misleading. We may remove content or disable accounts for violations.',
      ),
      TikkiContentSection(
        headingAr: 'المحتوى الممنوع (صارم)',
        headingFr: 'Contenu interdit (strict)',
        headingEn: 'Prohibited content (strict)',
        bodyAr:
            'يُمنع نشر أو طلب أو الترويج لما يلي (وأي شيء مخالف للقانون):\n'
            '• الاحتيال، التضليل، أو انتحال الهوية.\n'
            '• سلع مسروقة أو مقلدة.\n'
            '• مواد ممنوعة/مقيّدة محلياً (وفق القوانين السارية).\n'
            '• محتوى مسيء، كراهية، أو تحريض.\n'
            '• صور غير لائقة أو تنتهك خصوصية الآخرين.',
        bodyFr:
            'Interdits :\n'
            '• Fraude, tromperie, usurpation d\'identité.\n'
            '• Biens volés ou contrefaits.\n'
            '• Articles interdits/réglementés (selon la loi).\n'
            '• Contenu abusif, haine, incitation.\n'
            '• Images inappropriées ou portant atteinte à la vie privée.',
        bodyEn:
            'You must not publish or request prohibited/illegal content, including:\n'
            '• Fraud, deception, impersonation.\n'
            '• Stolen or counterfeit goods.\n'
            '• Locally restricted/illegal items (per applicable law).\n'
            '• Abusive/hate content or incitement.\n'
            '• Inappropriate images or privacy violations.',
      ),
      TikkiContentSection(
        headingAr: 'الصفقات والتواصل',
        headingFr: 'Transactions & contact',
        headingEn: 'Transactions & contact',
        bodyAr:
            'التواصل بين المشتري والبائع مباشر. التطبيق لا يضمن إتمام الصفقة ولا يتحمل مسؤولية الدفع أو التسليم. ننصح بالتحقق واللقاء في مكان عام.',
        bodyFr:
            'Le contact est direct entre acheteur et vendeur. L\'application ne garantit pas la vente et n\'est pas responsable du paiement ou de la livraison. Rencontrez-vous en lieu public.',
        bodyEn:
            'Buyer–seller contact is direct. The app does not guarantee the transaction and is not responsible for payment/delivery. Meet in a public place and verify items.',
      ),
      TikkiContentSection(
        headingAr: 'VIP والإعلانات المروّجة',
        headingFr: 'VIP & promotions',
        headingEn: 'VIP & promotions',
        bodyAr:
            'ميزة VIP هي خدمة ترويجية تخضع للمراجعة والموافقة. قد نرفض أو نوقف VIP لأي إعلان يخالف السياسات. مدة الترويج والترتيب يحددهما النظام/الإدارة حسب الباقات المتاحة.',
        bodyFr:
            'VIP est un service promotionnel soumis à revue et approbation. Nous pouvons refuser ou arrêter un VIP en cas de violation. La durée et le classement dépendent des packs disponibles.',
        bodyEn:
            'VIP is a promotional service subject to review/approval. We may refuse or stop VIP for policy violations. Duration and ranking depend on available packages.',
      ),
      TikkiContentSection(
        headingAr: 'حدود المسؤولية',
        headingFr: 'Limitation de responsabilité',
        headingEn: 'Limitation of liability',
        bodyAr:
            'نقدّم الخدمة "كما هي" دون ضمانات صريحة. إلى الحد الذي يسمح به القانون، لا نتحمل مسؤولية أي خسائر ناتجة عن استخدام التطبيق أو التعاملات بين المستخدمين.',
        bodyFr:
            'Le service est fourni « tel quel » sans garanties explicites. Dans la limite permise par la loi, nous ne sommes pas responsables des pertes liées à l\'utilisation ou aux transactions entre utilisateurs.',
        bodyEn:
            'The service is provided “as is” without express warranties. To the extent permitted by law, we are not liable for losses arising from use of the app or user-to-user transactions.',
      ),
    ],
  ),
  TikkiPolicyArticle(
    id: 'safety',
    titleAr: 'نصائح الأمان',
    titleFr: 'Conseils de sécurité',
    titleEn: 'Safety tips',
    sections: [
      TikkiContentSection(
        headingAr: 'قبل اللقاء',
        headingFr: 'Avant la rencontre',
        headingEn: 'Before meeting',
        bodyAr:
            'تحقق من التفاصيل، واطلب صوراً إضافية، وتأكد من السعر قبل اللقاء.',
        bodyFr:
            'Vérifiez les détails et confirmez le prix avant de vous rencontrer.',
        bodyEn:
            'Verify details, request extra photos, and confirm price beforehand.',
      ),
      TikkiContentSection(
        headingAr: 'مكان آمن',
        headingFr: 'Lieu sûr',
        headingEn: 'Safe place',
        bodyAr: 'اختر مكاناً عاماً، ويفضل اصطحاب شخص معك للسلامة.',
        bodyFr: 'Choisissez un lieu public et idéalement venez accompagné.',
        bodyEn: 'Meet in a public place and preferably bring someone with you.',
      ),
    ],
  ),
  TikkiPolicyArticle(
    id: 'publishing',
    titleAr: 'قواعد النشر',
    titleFr: 'Règles de publication',
    titleEn: 'Publishing rules',
    sections: [
      TikkiContentSection(
        headingAr: 'صور واضحة',
        headingFr: 'Photos claires',
        headingEn: 'Clear photos',
        bodyAr:
            'استخدم صوراً واضحة للمنتج الحقيقي، وتجنب الصور المسروقة من الإنترنت.',
        bodyFr:
            'Utilisez des photos réelles et évitez les images volées d\'internet.',
        bodyEn: 'Use clear real photos; avoid stolen internet images.',
      ),
      TikkiContentSection(
        headingAr: 'عنوان صادق',
        headingFr: 'Titre honnête',
        headingEn: 'Honest title',
        bodyAr: 'اجعل العنوان يصف المنتج بدقة لتسهيل العثور عليه.',
        bodyFr: 'Un titre précis aide les acheteurs à trouver votre annonce.',
        bodyEn: 'A precise title helps buyers find your listing.',
      ),
    ],
  ),
];

const List<TikkiContentSection> tikkiAboutSections = [
  TikkiContentSection(
    headingAr: 'ما هو Tikki؟',
    headingFr: 'C\'est quoi Tikki ?',
    headingEn: 'What is Tikki?',
    bodyAr:
        'Tikki سوق سريع وبسيط للنشر والشراء في موريتانيا: منتجات، سيارات، عقارات، وخدمات.',
    bodyFr:
        'Tikki est un marché simple et rapide en Mauritanie: produits, autos, immobilier, services.',
    bodyEn:
        'Tikki is a fast and simple marketplace for Mauritania: products, cars, real estate, services.',
  ),
  TikkiContentSection(
    headingAr: 'كيف تشتري بأمان؟',
    headingFr: 'Acheter en sécurité',
    headingEn: 'Buy safely',
    bodyAr:
        'افحص الصور، اسأل عن التفاصيل، قابل في مكان عام، ولا تدفع قبل التأكد.',
    bodyFr:
        'Vérifiez les photos, posez des questions, rencontrez en public, ne payez pas à l\'avance.',
    bodyEn:
        'Check photos, ask details, meet in public, and avoid paying before verifying.',
  ),
  TikkiContentSection(
    headingAr: 'فيديوهات (قريباً)',
    headingFr: 'Vidéos (bientôt)',
    headingEn: 'Videos (coming soon)',
    bodyAr:
        'سنضيف فيديوهات قصيرة تشرح النشر والشراء خطوة بخطوة حسب اللغة المختارة.',
    bodyFr: 'Nous ajouterons des vidéos courtes selon la langue choisie.',
    bodyEn: 'We will add short videos per selected language, step-by-step.',
  ),
];
