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

    final intro = article.sections.isNotEmpty &&
            article.sections.first.heading(context) == null
        ? article.sections.first
        : null;

    final sections = intro == null
        ? article.sections
        : article.sections.skip(1).toList(growable: false);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(article.title(context)),
          surfaceTintColor: Colors.transparent,
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
            if (intro != null) ...[
              _IntroCard(text: intro.body(context)),
              const SizedBox(height: 12),
            ],
            ...sections.map((sec) => _Section(section: sec)),
            const SizedBox(height: 6),
            _FooterNote(),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withAlpha(14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withAlpha(55)),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          color: cs.onSurface.withAlpha(220),
          fontWeight: FontWeight.w700,
          height: 1.45,
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
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
            ],
            SelectableText(
              section.body(context),
              style: TextStyle(
                color: cs.onSurface.withAlpha(215),
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withAlpha(35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withAlpha(120)),
      ),
      child: Text(
        tikkiTr(
          context,
          ar: 'إذا كان لديك سؤال أو بلاغ يتعلق بالخصوصية أو المحتوى، تواصل معنا من صفحة الدعم داخل التطبيق.',
          fr: 'Si vous avez une question ou un signalement (confidentialité/contenu), contactez le support dans l\'application.',
          en: 'If you have a privacy/content question or report, contact Support in the app.',
        ),
        style: TextStyle(
          color: cs.onSurface.withAlpha(200),
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}
