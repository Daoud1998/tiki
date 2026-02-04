import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'content_data.dart';

class PolicyArticleScreen extends StatelessWidget {
  const PolicyArticleScreen({super.key, required this.articleId});

  final String articleId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final article = tikkiPolicyArticles.firstWhere(
      (a) => a.id == articleId,
      orElse: () => tikkiPolicyArticles.first,
    );

    void goBack() {
      final r = GoRouter.of(context);
      if (r.canPop()) {
        context.pop();
      } else {
        context.go('/content/policies');
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(article.title(context)),
          leading: IconButton(
            icon: const BackButtonIcon(),
            onPressed: goBack,
          ),
          actions: [
            IconButton(
              tooltip: tikkiTr(
                context,
                ar: 'كل السياسات',
                fr: 'Toutes les politiques',
                en: 'All policies',
              ),
              onPressed: goBack,
              icon: const Icon(Icons.list_alt_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant.withAlpha(150)),
              ),
              child: Text(
                tikkiTr(
                  context,
                  ar: 'هذا النص قابل للتعديل. لاحقاً يمكنك استبداله بمحتوى HTML أو Firebase أو إضافة صور/فيديو.',
                  fr: 'Texte modifiable. Plus tard, remplacez-le par HTML/Firebase ou ajoutez des images/vidéos.',
                  en: 'Editable text. Later you can replace it with HTML/Firebase or add images/videos.',
                ),
                style: TextStyle(
                  color: cs.onSurface.withAlpha(190),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...article.sections.map((sec) => _Section(section: sec)),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section});
  final TikkiContentSection section;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final heading = section.heading(context);

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
            if (heading != null) ...[
              Text(
                heading,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
            ],
            SelectableText(
              section.body(context),
              style: TextStyle(
                color: cs.onSurface.withAlpha(215),
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
