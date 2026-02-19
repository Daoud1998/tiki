import 'package:flutter/material.dart';

import '../../../app/localization/l10n.dart';
import '../../../core/i18n/tikki_tr.dart';

class AboutTikiScreen extends StatelessWidget {
  const AboutTikiScreen({super.key});

  static const List<_AboutSection> _sections = [
    _AboutSection(
      titleAr: 'ما هو Tki؟',
      titleFr: "C'est quoi Tki ?",
      titleEn: 'What is Tki?',
      bodyAr:
          'Tki سوق سريع وبسيط للنشر والشراء في موريتانيا: منتجات، سيارات، عقارات، وخدمات.',
      bodyFr:
          'Tki est un marché simple et rapide en Mauritanie: produits, autos, immobilier, services.',
      bodyEn:
          'Tki is a fast and simple marketplace for Mauritania: products, cars, real estate, services.',
    ),
    _AboutSection(
      titleAr: 'كيف تشتري بأمان؟',
      titleFr: 'Acheter en sécurité',
      titleEn: 'Buy safely',
      bodyAr:
          'افحص الصور، اسأل عن التفاصيل، قابل في مكان عام، ولا تدفع قبل التأكد.',
      bodyFr:
          "Vérifiez les photos, posez des questions, rencontrez en public, ne payez pas à l'avance.",
      bodyEn:
          'Check photos, ask details, meet in public, and avoid paying before verifying.',
    ),
    _AboutSection(
      titleAr: 'فيديوهات (قريباً)',
      titleFr: 'Vidéos (bientôt)',
      titleEn: 'Videos (coming soon)',
      bodyAr:
          'سنضيف فيديوهات قصيرة تشرح النشر والشراء خطوة بخطوة حسب اللغة المختارة.',
      bodyFr: 'Nous ajouterons des vidéos courtes selon la langue choisie.',
      bodyEn: 'We will add short videos per selected language, step-by-step.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);

    final title = tikkiTr(
      context,
      ar: 'عن Tki',
      fr: 'À propos de Tki',
      en: 'About Tki',
    );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withAlpha(150)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.shopping_bag_rounded, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.appName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tikkiTr(
                          context,
                          ar: 'سوق سريع للنشر والشراء في موريتانيا.',
                          fr: 'Un marché rapide pour vendre et acheter en Mauritanie.',
                          en: 'A fast marketplace for Mauritania.',
                        ),
                        style: TextStyle(
                          color: cs.onSurface.withAlpha(180),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._sections.map((sec) => _SectionCard(section: sec)),
          const SizedBox(height: 18),
          Text(
            '© ${DateTime.now().year} ${s.appName}',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurface.withAlpha(150)),
          ),
        ],
      ),
    );
  }
}

class _AboutSection {
  const _AboutSection({
    required this.titleAr,
    required this.titleFr,
    required this.titleEn,
    required this.bodyAr,
    required this.bodyFr,
    required this.bodyEn,
  });

  final String titleAr;
  final String titleFr;
  final String titleEn;

  final String bodyAr;
  final String bodyFr;
  final String bodyEn;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final _AboutSection section;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withAlpha(150)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tikkiTr(
              context,
              ar: section.titleAr,
              fr: section.titleFr,
              en: section.titleEn,
            ),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            tikkiTr(
              context,
              ar: section.bodyAr,
              fr: section.bodyFr,
              en: section.bodyEn,
            ),
            style: TextStyle(color: cs.onSurface.withAlpha(190), height: 1.35),
          ),
        ],
      ),
    );
  }
}
