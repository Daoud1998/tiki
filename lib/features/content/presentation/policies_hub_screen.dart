import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'content_data.dart';

class PoliciesHubScreen extends StatelessWidget {
  const PoliciesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final title = tikkiTr(
      context,
      ar: 'السياسات والخصوصية',
      fr: 'Politiques',
      en: 'Policies',
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final r = GoRouter.of(context);
        if (r.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const BackButtonIcon(),
            onPressed: () {
              final r = GoRouter.of(context);
              if (r.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            _IntroCard(),
            const SizedBox(height: 12),
            for (final a in tikkiPolicyArticles) ...[
              _PolicyTile(article: a, isRtl: isRtl),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withAlpha(35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tikkiTr(
              context,
              ar: 'اقرأ قبل الاستخدام',
              fr: 'À lire avant d\'utiliser',
              en: 'Read before using',
            ),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            tikkiTr(
              context,
              ar: 'هذه الصفحات تشرح الخصوصية، الشروط، الأمان وقواعد النشر. الالتزام بها يساعدنا على إبقاء السوق نظيفاً وآمناً.',
              fr: 'Ces pages décrivent la confidentialité, les conditions, la sécurité et les règles de publication.',
              en: 'These pages describe privacy, terms, safety, and publishing rules.',
            ),
            style: TextStyle(
              color: cs.onSurface.withAlpha(210),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyTile extends StatelessWidget {
  const _PolicyTile({required this.article, required this.isRtl});
  final TkiiPolicyArticle article;
  final bool isRtl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/content/policies/${article.id}'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withAlpha(150)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(24),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.description_rounded, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title(context),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tikkiTr(
                        context,
                        ar: 'اضغط لعرض التفاصيل',
                        fr: 'Touchez pour ouvrir',
                        en: 'Tap to open',
                      ),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isRtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
