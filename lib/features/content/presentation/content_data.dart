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
        headingAr: 'ما الذي نجمعه؟',
        headingFr: 'Données collectées',
        headingEn: 'What we collect',
        bodyAr:
            'قد نجمع معلومات أساسية عند النشر مثل رقم الهاتف، الولاية، وصور المنتج.',
        bodyFr:
            'Nous collectons des infos de base lors de la publication: téléphone, région, photos.',
        bodyEn:
            'We collect basic info when publishing: phone, region, and photos.',
      ),
      TikkiContentSection(
        headingAr: 'كيف نستخدم المعلومات؟',
        headingFr: 'Utilisation',
        headingEn: 'How we use it',
        bodyAr: 'لعرض إعلانك وتسهيل التواصل وتحسين البحث والفرز داخل التطبيق.',
        bodyFr:
            'Pour afficher votre annonce, faciliter le contact et améliorer la recherche.',
        bodyEn:
            'To show your listing, enable contact, and improve search/sorting.',
      ),
      TikkiContentSection(
        headingAr: 'التحكم',
        headingFr: 'Contrôle',
        headingEn: 'Control',
        bodyAr: 'يمكنك تعديل أو حذف إعلانك في أي وقت من صفحة إعلاناتي.',
        bodyFr: 'Vous pouvez modifier ou supprimer vos annonces à tout moment.',
        bodyEn: 'You can edit or delete your listings anytime.',
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
        headingAr: 'مسؤولية المحتوى',
        headingFr: 'Responsabilité',
        headingEn: 'Content responsibility',
        bodyAr: 'البائع مسؤول عن صحة معلومات الإعلان وصوره وسعره.',
        bodyFr: 'Le vendeur est responsable des informations, photos et prix.',
        bodyEn:
            'The seller is responsible for listing details, photos, and price.',
      ),
      TikkiContentSection(
        headingAr: 'المحتوى الممنوع',
        headingFr: 'Contenu interdit',
        headingEn: 'Prohibited content',
        bodyAr: 'يمنع نشر أي محتوى مخالف للقانون أو مسيء أو احتيالي.',
        bodyFr:
            'Interdiction de publier du contenu illégal, offensant ou frauduleux.',
        bodyEn: 'Do not publish illegal, abusive, or fraudulent content.',
      ),
      TikkiContentSection(
        headingAr: 'التواصل',
        headingFr: 'Contact',
        headingEn: 'Contact',
        bodyAr:
            'التواصل بين المشتري والبائع مباشر. التطبيق لا يضمن إتمام الصفقة.',
        bodyFr:
            'Le contact est direct. L\'application ne garantit pas la vente.',
        bodyEn:
            'Contact is direct; the app does not guarantee the transaction.',
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
