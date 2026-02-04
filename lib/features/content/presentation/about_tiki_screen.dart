import 'package:flutter/material.dart';

import '../../../app/localization/l10n.dart';
import 'content_data.dart';

class AboutTikiScreen extends StatelessWidget {
  const AboutTikiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);

    final title = tikkiTr(
      context,
      ar: 'عن Tikki',
      fr: 'À propos de Tikki',
      en: 'About Tikki',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
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
          ...tikkiAboutSections.map(
            (sec) => _SectionCard(section: sec),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withAlpha(120),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withAlpha(140)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tikkiTr(
                    context,
                    ar: 'ملاحظة',
                    fr: 'Note',
                    en: 'Note',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  tikkiTr(
                    context,
                    ar: 'هذا المحتوى محلي داخل التطبيق الآن. لاحقاً يمكنك ربطه بـ Firebase/Firestore أو HTML أو فيديوهات.',
                    fr: 'Ce contenu est local pour le moment. Vous pouvez le relier à Firebase/Firestore, HTML ou vidéos plus tard.',
                    en: 'This content is local for now. You can later connect it to Firebase/Firestore, HTML, or videos.',
                  ),
                  style: TextStyle(
                    color: cs.onSurface.withAlpha(190),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});
  final TikkiContentSection section;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withAlpha(140)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (section.heading(context) != null) ...[
              Text(
                section.heading(context)!,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              section.body(context),
              style: TextStyle(
                color: cs.onSurface.withAlpha(210),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
