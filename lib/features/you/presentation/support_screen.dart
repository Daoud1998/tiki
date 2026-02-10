import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/support_contacts.dart';
import '../../../core/widgets/dir_chevrons.dart';

/// مركز المساعدة (ستايل قريب من Temu)
/// - بحث بالكلمات
/// - أقسام قابلة للفتح
/// - عند الضغط على سؤال: يفتح مقال بتصميم أخضر + خط منقط + تنسيق نقاط
///
/// ملاحظة مهمة:
/// لا يوجد parameter اسمه `matchTextDirection` داخل Icon.
/// لذلك نعكس الأسهم يدوياً عبر DirChevrons.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  // TODO: عدّلها لبيانات الدعم الحقيقية
  static const String _supportWhatsApp = kSupportWhatsApp;
  static const String _supportPhone = kSupportPhone;
  static const String _supportEmail = kSupportEmail;

  // Temu-like article palette
  static const Color _temuGreen = Color(0xFF1E8E3E);
  static const Color _temuGreenBg = Color(0xFFEAF7EC);
  static const Color _temuGreenBorder = Color(0xFFB9E2C1);

  final _searchCtl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _query.trim();
    final results = q.isEmpty ? const <_Faq>[] : _search(q);

    return WillPopScope(
      onWillPop: () async {
        if (context.canPop()) return true;
        context.go('/you');
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_tr(context, ar: 'الدعم', fr: 'Support', en: 'Support')),
          leading: BackButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/you');
              }
            },
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            _searchBox(cs),
            const SizedBox(height: 12),
            _sectionHeader(
              cs,
              title: _tr(context,
                  ar: 'مقالات المساعدة',
                  fr: 'Articles d\'aide',
                  en: 'Help articles'),
              icon: Icons.article_outlined,
            ),
            const SizedBox(height: 10),
            if (q.isNotEmpty) ...[
              _resultsPanel(cs, results: results, query: q),
              const SizedBox(height: 12),
            ] else ...[
              _recommendedPanel(cs),
              const SizedBox(height: 12),
            ],
            ..._categories.map((c) => _categoryTile(cs, c)).toList(),
            const SizedBox(height: 10),
            _divider(cs),
            const SizedBox(height: 10),
            _actionTile(
              cs,
              icon: Icons.support_agent_outlined,
              title: _tr(context,
                  ar: 'لم تجد ما تبحث عنه؟',
                  fr: 'Besoin d\'aide ?',
                  en: "Can't find what you need?"),
              subtitle: _tr(context,
                  ar: 'تواصل معنا: واتساب أو اتصال أو بريد',
                  fr: 'Contact: WhatsApp, appel, email',
                  en: 'Contact: WhatsApp, call, email'),
              onTap: _openContactSheet,
            ),
            const SizedBox(height: 10),
            _actionTile(
              cs,
              icon: Icons.forum_outlined,
              title: _tr(context,
                  ar: 'محادثة داخل التطبيق',
                  fr: 'Chat in-app',
                  en: 'In-app chat'),
              subtitle: _tr(context,
                  ar: 'راسل فريق الدعم داخل التطبيق.',
                  fr: 'Discutez avec le support dans l’application.',
                  en: 'Chat with support in the app.'),
              onTap: _openInAppChat,
            ),
          ],
        ),
      ),
    );
  }

  // UI
  Widget _searchBox(ColorScheme cs) {
    return TextField(
      controller: _searchCtl,
      onChanged: (v) => setState(() => _query = v),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: _tr(context,
            ar: 'ابحث عن سؤال أو كلمة مفتاحية',
            fr: 'Rechercher une question ou un mot-clé',
            en: 'Search by question or keyword'),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? const Icon(Icons.help_outline_rounded)
            : IconButton(
                onPressed: () {
                  _searchCtl.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: cs.surfaceVariant.withValues(alpha: 0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.85)),
        ),
      ),
    );
  }

  Widget _sectionHeader(ColorScheme cs,
      {required String title, required IconData icon}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ),
        Icon(icon, color: cs.onSurface.withValues(alpha: 0.75)),
      ],
    );
  }

  Widget _divider(ColorScheme cs) {
    return Container(
      height: 1,
      color: cs.outlineVariant.withValues(alpha: 0.5),
    );
  }

  Widget _resultsPanel(ColorScheme cs,
      {required List<_Faq> results, required String query}) {
    if (results.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            _tr(context,
                ar: 'لا توجد نتائج لـ "$query". جرّب كلمات أقصر.',
                fr: 'Aucun résultat pour "$query". Essayez des mots plus courts.',
                en: 'No results for "$query". Try shorter keywords.'),
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          for (final f in results)
            ListTile(
              title: Text(
                f.question(context),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: DirChevrons.forward(
                context,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
              onTap: () => _openFaq(f),
            ),
        ],
      ),
    );
  }

  Widget _recommendedPanel(ColorScheme cs) {
    final items = _recommended;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          leading: Icon(Icons.lightbulb_outline_rounded,
              color: cs.onSurface.withValues(alpha: 0.75)),
          title: Text(
            _tr(context,
                ar: 'الموضوعات الموصى بها',
                fr: 'Sujets recommandés',
                en: 'Recommended topics'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          children: [
            for (final f in items)
              ListTile(
                title: Text(f.question(context)),
                trailing: DirChevrons.forward(
                  context,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
                onTap: () => _openFaq(f),
              ),
          ],
        ),
      ),
    );
  }

  Widget _categoryTile(ColorScheme cs, _Category cat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: cat.initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            leading: Icon(cat.icon, color: cs.onSurface.withValues(alpha: 0.75)),
            title: Text(
              cat.title(context),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            children: [
              for (final f in cat.items)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  title: Text(
                    f.question(context),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: DirChevrons.forward(
                    context,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                  onTap: () => _openFaq(f),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile(ColorScheme cs,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _temuGreenBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _temuGreenBorder),
          ),
          child: Icon(icon, color: _temuGreen),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: DirChevrons.forward(
          context,
          color: cs.onSurface.withValues(alpha: 0.55),
        ),
        onTap: onTap,
      ),
    );
  }

  // Search
  List<_Faq> _search(String query) {
    final q = _norm(query);
    if (q.isEmpty) return const <_Faq>[];

    final all = <_Faq>[
      ..._recommended,
      for (final c in _categories) ...c.items,
    ];

    // de-dup by id
    final byId = <String, _Faq>{};
    for (final f in all) {
      byId[f.id] = f;
    }

    final unique = byId.values.toList(growable: false);
    return unique.where((f) => f.matches(q)).take(60).toList(growable: false);
  }

  // Article sheet (Temu-like)
  Future<void> _openFaq(_Faq f) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.50,
          maxChildSize: 0.94,
          builder: (ctx, controller) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _temuGreenBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _temuGreenBorder),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                  ],
                ),
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  children: [
                    const SizedBox(height: 2),
                    Center(child: _dragHandle()),
                    const SizedBox(height: 12),
                    Text(
                      f.question(context),
                      textAlign: TextAlign.start,
                      style: const TextStyle(
                        color: _temuGreen,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DashedLine(color: _temuGreen.withValues(alpha: 0.55)),
                    const SizedBox(height: 12),
                    _answerWidget(
                      f.answer(context),
                      baseStyle: const TextStyle(
                        height: 1.45,
                        fontSize: 14.5,
                        color: Colors.black87,
                      ),
                      highlightColor: _temuGreen,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _pillButton(
                          ctx,
                          icon: Icons.forum_outlined,
                          label: _tr(context,
                              ar: 'محادثة داخل التطبيق',
                              fr: 'Chat in-app',
                              en: 'In-app chat'),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openInAppChat();
                          },
                        ),
                        _pillButton(
                          ctx,
                          icon: Icons.chat_bubble_outline_rounded,
                          label: _tr(context,
                              ar: 'واتساب', fr: 'WhatsApp', en: 'WhatsApp'),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openWhatsApp();
                          },
                        ),
                        _pillButton(
                          ctx,
                          icon: Icons.call_outlined,
                          label: _tr(context,
                              ar: 'اتصال', fr: 'Appel', en: 'Call'),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _callSupport();
                          },
                        ),
                        _pillButton(
                          ctx,
                          icon: Icons.mail_outline_rounded,
                          label: _tr(context,
                              ar: 'بريد', fr: 'Email', en: 'Email'),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _emailSupport();
                          },
                        ),
                        if (f.routeToOpen != null)
                          _pillButton(
                            ctx,
                            icon: Icons.open_in_new_rounded,
                            label: _tr(context,
                                ar: 'فتح الصفحة', fr: 'Ouvrir', en: 'Open'),
                            onTap: () {
                              final r = f.routeToOpen!;
                              Navigator.of(ctx).pop();
                              context.push(r);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _dragHandle() {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  Widget _contactQuickButton({
    required String label,
    required IconData icon,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bg.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactLine({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurface.withValues(alpha: 0.65)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label: $value',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.75)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _pillButton(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: _temuGreen),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _temuGreen,
        side: BorderSide(color: _temuGreen.withValues(alpha: 0.45)),
        backgroundColor: Colors.white.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }

  Widget _answerWidget(
    String text, {
    required TextStyle baseStyle,
    required Color highlightColor,
  }) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trimRight())
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final highlightStyle = baseStyle.copyWith(
      color: highlightColor,
      fontWeight: FontWeight.w900,
    );

    final children = <Widget>[];
    for (final line in lines) {
      final isBullet =
          line.startsWith('•') || line.startsWith('-') || line.startsWith('*');

      if (isBullet) {
        final clean = line.replaceFirst(RegExp(r'^[•\-*]\s*'), '');
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 6, end: 10),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _temuGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText.rich(
                    TextSpan(
                      children: _richSpans(clean, baseStyle, highlightStyle),
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 10),
            child: SelectableText.rich(
              TextSpan(
                children: _richSpans(line, baseStyle, highlightStyle),
              ),
              textAlign: TextAlign.start,
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  List<InlineSpan> _richSpans(
    String line,
    TextStyle base,
    TextStyle highlight,
  ) {
    // Highlight anything containing digits/currency/phone-like patterns.
    final r = RegExp(
      r'([0-9٠-٩]+([\.,][0-9٠-٩]+)?\s*(MRU|UM|MRO|€|\$|%|مرو)?|\+?[0-9٠-٩][0-9٠-٩\s\-]{6,})',
      caseSensitive: false,
    );

    final spans = <InlineSpan>[];
    int start = 0;
    for (final m in r.allMatches(line)) {
      if (m.start > start) {
        spans.add(TextSpan(text: line.substring(start, m.start), style: base));
      }
      spans.add(TextSpan(text: m.group(0), style: highlight));
      start = m.end;
    }
    if (start < line.length) {
      spans.add(TextSpan(text: line.substring(start), style: base));
    }
    return spans;
  }

  // Contact sheet
  Future<void> _openContactSheet() async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dragHandle(),
                  const SizedBox(height: 8),
                  Text(
                    _tr(context,
                        ar: 'تواصل معنا', fr: 'Contact', en: 'Contact'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _tr(context,
                        ar: 'إذا لم تستطع إيجاد ما تبحث عنه، راسلنا وسنساعدك بسرعة.',
                        fr: 'Si vous ne trouvez pas ce que vous cherchez, contactez-nous.',
                        en: "If you can't find what you need, contact us and we'll help."),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _contactQuickButton(
                          label: _tr(context,
                              ar: 'واتساب', fr: 'WhatsApp', en: 'WhatsApp'),
                          icon: Icons.chat_bubble_outline_rounded,
                          bg: const Color(0xFF25D366),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openWhatsApp();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _contactQuickButton(
                          label: _tr(context,
                              ar: 'اتصال', fr: 'Appeler', en: 'Call'),
                          icon: Icons.call_outlined,
                          bg: const Color(0xFF2563EB),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _callSupport();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _contactQuickButton(
                          label: _tr(context,
                              ar: 'Email', fr: 'Email', en: 'Email'),
                          icon: Icons.mail_outline_rounded,
                          bg: const Color(0xFFF97316),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _emailSupport();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: _contactQuickButton(
                      label: _tr(context,
                          ar: 'محادثة داخل التطبيق',
                          fr: 'Chat in-app',
                          en: 'In-app chat'),
                      icon: Icons.support_agent_outlined,
                      bg: _temuGreen,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _openInAppChat();
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      children: [
                        _contactLine(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: _tr(context,
                              ar: 'واتساب', fr: 'WhatsApp', en: 'WhatsApp'),
                          value: _supportWhatsApp,
                        ),
                        const SizedBox(height: 8),
                        _contactLine(
                          icon: Icons.call_outlined,
                          label: _tr(context,
                              ar: 'هاتف', fr: 'Téléphone', en: 'Phone'),
                          value: _supportPhone,
                        ),
                        const SizedBox(height: 8),
                        _contactLine(
                          icon: Icons.mail_outline_rounded,
                          label: _tr(context,
                              ar: 'بريد', fr: 'Email', en: 'Email'),
                          value: _supportEmail,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openInAppChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(context,
              ar: 'يجب تسجيل الدخول للتواصل مع الدعم.',
              fr: 'Vous devez vous connecter pour contacter le support.',
              en: 'You need to sign in to chat with support.')),
        ),
      );
      // Go to Account tab to sign in
      if (context.mounted) context.go('/account');
      return;
    }

    // Open in-app support chat
    if (context.mounted) context.push('/support-chat');
  }

  Future<void> _openWhatsApp() async {
    final phone = _supportWhatsApp.replaceAll(RegExp(r'[^0-9]'), '');
    final text = Uri.encodeComponent(_tr(context,
        ar: 'مرحبا، أحتاج مساعدة في تطبيق Tikki.',
        fr: 'Bonjour, j\'ai besoin d\'aide sur Tikki.',
        en: 'Hi, I need help with Tikki.'));
    final uri = Uri.parse('https://wa.me/$phone?text=$text');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _callSupport() async {
    final uri = Uri.parse('tel:${_supportPhone.replaceAll(' ', '')}');
    await launchUrl(uri);
  }

  Future<void> _emailSupport() async {
    final uri = Uri.parse('mailto:$_supportEmail?subject=Tikki%20Support');
    await launchUrl(uri);
  }

  // Helpers
  String _tr(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr.isNotEmpty ? fr : en;
    return en.isNotEmpty ? en : fr;
  }

  String _norm(String s) {
    return s
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), ''); // remove Arabic diacritics
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedLinePainter(color),
      child: const SizedBox(height: 1),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _Faq {
  const _Faq({
    required this.id,
    required this.qAr,
    required this.qFr,
    required this.qEn,
    required this.aAr,
    required this.aFr,
    required this.aEn,
    this.routeToOpen,
    this.keywords = const <String>[],
  });

  final String id;
  final String qAr;
  final String qFr;
  final String qEn;
  final String aAr;
  final String aFr;
  final String aEn;
  final String? routeToOpen;
  final List<String> keywords;

  String question(BuildContext c) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'ar') return qAr;
    if (code == 'fr') return qFr.isNotEmpty ? qFr : qEn;
    return qEn.isNotEmpty ? qEn : qFr;
  }

  String answer(BuildContext c) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'ar') return aAr;
    if (code == 'fr') return aFr.isNotEmpty ? aFr : aEn;
    return aEn.isNotEmpty ? aEn : aFr;
  }

  bool matches(String qLower) {
    String norm(String s) => s
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '');

    final hay = <String>[
      qAr,
      qFr,
      qEn,
      aAr,
      aFr,
      aEn,
      ...keywords,
    ].map(norm).join(' | ');

    return hay.contains(qLower);
  }
}

class _Category {
  const _Category({
    required this.icon,
    required this.titleAr,
    required this.titleFr,
    required this.titleEn,
    required this.items,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String titleAr;
  final String titleFr;
  final String titleEn;
  final List<_Faq> items;
  final bool initiallyExpanded;

  String title(BuildContext c) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'ar') return titleAr;
    if (code == 'fr') return titleFr;
    return titleEn;
  }
}

// -------------------- FAQ Data (AR / FR / EN) --------------------

final List<_Faq> _recommended = <_Faq>[
  const _Faq(
    id: 'start_1',
    qAr: 'كيف أبدأ استخدام التطبيق؟',
    qFr: 'Comment commencer à utiliser l\'application ?',
    qEn: 'How do I start using the app?',
    aAr:
        'يمكنك تصفح المنتجات كزائر بدون حساب.\nإذا أردت النشر كبائع أو حفظ المفضلة، قم بتسجيل الدخول من صفحة الحساب.\n• ابدأ بالبحث أو اختيار فئة\n• افتح أي منتج لقراءة التفاصيل\n• تواصل مع البائع عبر الاتصال أو واتساب',
    aFr:
        'Vous pouvez parcourir les produits en mode invité, sans compte.\nPour publier, enregistrer des favoris ou synchroniser، connectez-vous depuis la page Compte.\n• Recherchez ou choisissez une catégorie\n• Ouvrez un produit pour voir les détails\n• Contactez le vendeur via appel ou WhatsApp',
    aEn:
        'You can browse as a guest without an account.\nTo publish, save favorites, or sync, sign in from the Account page.\n• Search or pick a category\n• Open any product to see details\n• Contact the seller via call or WhatsApp',
    keywords: ['ابدأ', 'start', 'commencer', 'guest', 'زائر'],
  ),
  const _Faq(
    id: 'search_fast',
    qAr: 'كيف أبحث بسرعة عن منتج؟',
    qFr: 'Comment chercher rapidement un produit ?',
    qEn: 'How can I quickly search for a product?',
    aAr:
        'استخدم شريط البحث ثم اكتب اسم المنتج أو كلمة مفتاحية.\n• جرّب كلمات قصيرة (مثال: iPhone، لابتوب)\n• استعمل الفلاتر: الفئة، السعر، الولاية، الترتيب',
    aFr:
        'Utilisez la barre de recherche et tapez le nom du produit ou un mot-clé.\n• Essayez des mots courts (ex: iPhone, laptop)\n• Utilisez les filtres: catégorie, prix, wilaya, tri',
    aEn:
        'Use the search bar and type the product name or keyword.\n• Try short keywords (e.g., iPhone, laptop)\n• Use filters: category, price, region, sorting',
    keywords: ['بحث', 'search', 'recherche', 'filter', 'فلتر', 'فلاتر'],
    routeToOpen: '/search',
  ),
  const _Faq(
    id: 'seller_products',
    qAr: 'كيف أرى كل منتجات نفس البائع؟',
    qFr: 'Comment voir tous les produits du même vendeur ?',
    qEn: 'How do I see all products from the same seller?',
    aAr:
        'افتح منتجاً ثم اضغط على اسم البائع.\nسيتم عرض كل المنتجات التابعة له في صفحة واحدة.',
    aFr:
        'Ouvrez un produit puis appuyez sur le nom du vendeur.\nVous verrez tous ses produits dans une seule page.',
    aEn:
        'Open a product and tap the seller name.\nYou\'ll see all their listings in one page.',
    keywords: ['بائع', 'seller', 'vendeur', 'منتجات البائع'],
  ),
  const _Faq(
    id: 'phone_search',
    qAr: 'هل يمكنني البحث برقم الهاتف؟',
    qFr: 'Puis-je rechercher par numéro de téléphone ?',
    qEn: 'Can I search by phone number?',
    aAr:
        'نعم. إذا كتبت رقم الهاتف في البحث، ستظهر منتجات الحساب المرتبطة بذلك الرقم (إن وُجدت).\nنصيحة: اكتب الرقم بدون فراغات لنتائج أدق.',
    aFr:
        'Oui. Si vous tapez un numéro dans la recherche, les annonces liées à ce numéro s\'afficheront (si elles existent).\nConseil: tapez le numéro sans espaces.',
    aEn:
        'Yes. If you type a phone number in search, listings linked to that number will appear (if any).\nTip: type it without spaces for better results.',
    keywords: ['رقم', 'هاتف', 'phone', 'numéro', '+222'],
  ),
  const _Faq(
    id: 'change_lang',
    qAr: 'كيف أغير لغة التطبيق؟',
    qFr: 'Comment changer la langue ?',
    qEn: 'How do I change the language?',
    aAr: 'اذهب إلى الإعدادات ثم اختر اللغة: العربية أو الفرنسية أو الإنجليزية.',
    aFr:
        'Allez dans Paramètres puis choisissez la langue: Arabe, Français ou Anglais.',
    aEn: 'Go to Settings and choose your language: Arabic, French, or English.',
    keywords: ['لغة', 'language', 'langue', 'اعدادات', 'settings'],
    routeToOpen: '/settings',
  ),
  const _Faq(
    id: 'report_scam',
    qAr: 'كيف أبلغ عن إعلان مزعج أو احتيالي؟',
    qFr: 'Comment signaler une annonce frauduleuse ?',
    qEn: 'How do I report a scam or abusive listing?',
    aAr:
        'افتح المنتج ثم اختر "إبلاغ" من الخيارات.\n• لا ترسل دفعات مقدماً بدون ضمان\n• تحقّق من تفاصيل البائع وتواصل داخل التطبيق',
    aFr:
        'Ouvrez l\'annonce puis choisissez "Signaler".\n• Évitez les paiements à l\'avance sans garantie\n• Vérifiez le vendeur et échangez via l\'application',
    aEn:
        'Open the listing and choose "Report".\n• Avoid advance payments without protection\n• Verify the seller and communicate via the app',
    keywords: ['ابلاغ', 'report', 'signaler', 'fraud', 'احتيال'],
  ),
  const _Faq(
    id: 'publish_first',
    qAr: 'كيف أنشر أول إعلان؟',
    qFr: 'Comment publier ma première annonce ?',
    qEn: 'How do I publish my first listing?',
    aAr: 'اذهب إلى زر (نشر) ثم أكمل الخطوات.\n'
        '• اختر الفئة المناسبة\n'
        '• أضف صوراً واضحة (يفضل 3 صور أو أكثر)\n'
        '• اكتب تفاصيل صادقة وسعر واضح أو "حسب الاتفاق"\n'
        '• تأكد من الولاية ورقم الهاتف',
    aFr: 'Appuyez sur (Publier) puis suivez les étapes.\n'
        '• Choisissez la bonne catégorie\n'
        '• Ajoutez des photos nettes (idéalement 3+)\n'
        '• Décrivez clairement et indiquez un prix ou "À négocier"\n'
        '• Vérifiez la wilaya et le numéro de téléphone',
    aEn: 'Tap (Publish) and follow the steps.\n'
        '• Pick the right category\n'
        '• Add clear photos (ideally 3+)\n'
        '• Write honest details and a clear price or "Negotiable"\n'
        '• Verify region and phone number',
    routeToOpen: '/publish',
    keywords: ['نشر', 'publish', 'publier', 'اعلان', 'annonce'],
  ),
  const _Faq(
    id: 'fav_cart',
    qAr: 'كيف أضيف منتجاً إلى المفضلة أو السلة؟',
    qFr: 'Comment ajouter un produit aux favoris ou au panier ?',
    qEn: 'How do I add a product to favorites or cart?',
    aAr:
        'افتح المنتج ثم اضغط على أيقونة القلب للمفضلة أو زر السلة إن كان متاحاً.\n'
        'نصيحة: سجّل الدخول حتى لا تضيع العناصر عند تغيير الجهاز.',
    aFr:
        'Ouvrez le produit puis appuyez sur l’icône cœur pour les favoris, ou le bouton panier s’il est disponible.\n'
        'Astuce: connectez-vous pour synchroniser vos éléments.',
    aEn:
        'Open a product and tap the heart for favorites, or the cart button if available.\n'
        'Tip: sign in to sync your items across devices.',
    keywords: ['مفضلة', 'السلة', 'favorites', 'panier', 'cart', 'favoris'],
  ),
  const _Faq(
    id: 'price_agreement',
    qAr: 'ماذا يعني "حسب الاتفاق"؟',
    qFr: 'Que signifie "À négocier" ?',
    qEn: 'What does “Negotiable” mean?',
    aAr:
        'يعني أن السعر غير ثابت وسيتم الاتفاق عليه مع البائع حسب الحالة أو التوصيل أو الملحقات.\n'
        'نصيحة: اسأل عن السعر النهائي قبل اللقاء.',
    aFr:
        'Cela signifie que le prix n’est pas fixe et sera discuté avec le vendeur (état, livraison, accessoires...).\n'
        'Astuce: confirmez le prix final avant le rendez-vous.',
    aEn:
        'It means the price is not fixed and will be discussed with the seller (condition, delivery, accessories...).\n'
        'Tip: confirm the final price before meeting.',
    keywords: ['حسب الاتفاق', 'à négocier', 'negotiable', 'سعر'],
  ),
  const _Faq(
    id: 'reset_password',
    qAr: 'نسيت كلمة المرور، ماذا أفعل؟',
    qFr: 'J’ai oublié mon mot de passe, que faire ?',
    qEn: 'I forgot my password. What should I do?',
    aAr: 'من صفحة تسجيل الدخول اختر (نسيت كلمة المرور) واتبع التعليمات.\n'
        'إذا لم يصلك الرمز، تأكد من الشبكة ثم أعد المحاولة.',
    aFr:
        'Depuis la page de connexion, choisissez (Mot de passe oublié) et suivez les étapes.\n'
        'Si vous ne recevez pas le code, vérifiez la connexion puis réessayez.',
    aEn: 'On the sign-in page, tap (Forgot password) and follow the steps.\n'
        'If you don’t receive the code, check your connection and try again.',
    keywords: ['نسيت', 'password', 'mot de passe', 'forgot', 'otp'],
  ),
];

final List<_Category> _categories = <_Category>[
  _Category(
    icon: Icons.shopping_bag_outlined,
    titleAr: 'مشكلات الطلبات',
    titleFr: 'Problèmes de commandes',
    titleEn: 'Order issues',
    initiallyExpanded: true,
    items: const <_Faq>[
      _Faq(
        id: 'order_delay',
        qAr: 'تأخرت عملية الشراء أو الاتفاق مع البائع',
        qFr: 'Achat / accord avec le vendeur en retard',
        qEn: 'Purchase or agreement with the seller is delayed',
        aAr:
            'التطبيق يربطك بالبائع مباشرة. تأكد من رقم الهاتف داخل الإعلان واطلب توضيحاً حول السعر ووقت التسليم.\n• اكتب رسالة واضحة\n• اتفق على مكان آمن للقاء\n• لا تدفع مقدماً بدون ضمان',
        aFr:
            'L\'application vous met en relation directe avec le vendeur. Vérifiez le numéro et demandez des précisions (prix / délai).\n• Message clair\n• Rendez-vous dans un lieu sûr\n• Évitez les paiements à l\'avance sans garantie',
        aEn:
            'The app connects you directly with the seller. Verify the phone number and ask for details (price / timing).\n• Send a clear message\n• Meet in a safe place\n• Avoid advance payments without protection',
        keywords: ['تأخر', 'delay', 'retard', 'شراء'],
      ),
      _Faq(
        id: 'trusted_seller',
        qAr: 'كيف أتأكد أن البائع موثوق؟',
        qFr: 'Comment vérifier si un vendeur est fiable ?',
        qEn: 'How do I know a seller is trustworthy?',
        aAr:
            'لا يوجد ضمان مطلق، لكن هذه علامات تساعدك:\n• صور واضحة وحقيقية\n• وصف مفصل + موقع محدد\n• بائع يرد بسرعة وباحترام\n• إمكانية تجربة المنتج قبل الشراء\n• تجنب طلب الدفع المسبق',
        aFr:
            'Aucune garantie absolue, mais voici des indices:\n• Photos claires et réelles\n• Description détaillée + localisation\n• Réponses rapides et respectueuses\n• Possibilité de tester avant d\'acheter\n• Évitez la demande de paiement à l\'avance',
        aEn:
            'No absolute guarantee, but these signs help:\n• Clear real photos\n• Detailed description + location\n• Responsive and respectful seller\n• You can test before buying\n• Avoid advance payment requests',
        keywords: ['موثوق', 'trusted', 'fiable', 'seller'],
      ),
      _Faq(
        id: 'cancel',
        qAr: 'هل يمكنني إلغاء الاتفاق؟',
        qFr: 'Puis-je annuler un accord ?',
        qEn: 'Can I cancel an agreement?',
        aAr:
            'نعم. فقط أخبر البائع بأدب قبل الموعد.\nنصيحة: لا تعطي وعداً بالشراء إن لم تكن متأكداً.',
        aFr:
            'Oui. Prévenez le vendeur poliment avant le rendez-vous.\nConseil: ne promettez pas d\'acheter si vous n\'êtes pas sûr.',
        aEn:
            'Yes. Inform the seller politely before the meeting time.\nTip: don\'t promise to buy if you\'re not sure.',
        keywords: ['إلغاء', 'annuler', 'cancel'],
      ),
      _Faq(
        id: 'seller_no_reply',
        qAr: 'البائع لا يرد، ماذا أفعل؟',
        qFr: 'Le vendeur ne répond pas, que faire ?',
        qEn: 'The seller is not replying. What can I do?',
        aAr: 'جرّب هذه الخطوات:\n'
            '• أعد الإرسال بعد فترة (قد يكون البائع مشغولاً)\n'
            '• جرّب الاتصال أو واتساب من داخل الإعلان\n'
            '• ابحث عن منتجات مشابهة أو بائع آخر\n'
            'إذا لاحظت سلوكاً مزعجاً يمكنك الإبلاغ عن الإعلان.',
        aFr: 'Essayez ceci:\n'
            '• Réessayez plus tard (le vendeur peut être occupé)\n'
            '• Appelez ou utilisez WhatsApp depuis l’annonce\n'
            '• Cherchez une annonce similaire / un autre vendeur\n'
            'Si le comportement est abusif, vous pouvez signaler l’annonce.',
        aEn: 'Try this:\n'
            '• Try again later (the seller may be busy)\n'
            '• Call or WhatsApp from the listing\n'
            '• Look for a similar listing or another seller\n'
            'If it looks abusive, you can report the listing.',
        keywords: ['لا يرد', 'no reply', 'ne répond pas', 'seller'],
      ),
      _Faq(
        id: 'wrong_info',
        qAr: 'المنتج مختلف عن الوصف، ماذا أفعل؟',
        qFr: 'Le produit est différent de la description, que faire ?',
        qEn: 'The item is different from the description. What now?',
        aAr: 'تواصل مع البائع واشرح الفرق بهدوء.\n'
            '• إذا لم يتم الاتفاق، يمكنك إلغاء الشراء\n'
            '• التقط صوراً (للتوثيق)\n'
            '• يمكنك الإبلاغ عن الإعلان إذا كان مضللاً بشكل واضح',
        aFr: 'Contactez le vendeur et expliquez la différence calmement.\n'
            '• Si aucun accord, vous pouvez annuler\n'
            '• Prenez des photos (preuve)\n'
            '• Signalez l’annonce si elle est clairement trompeuse',
        aEn: 'Contact the seller and explain the difference calmly.\n'
            '• If you can’t agree, you can cancel\n'
            '• Take photos as proof\n'
            '• Report the listing if it’s clearly misleading',
        keywords: ['مختلف', 'different', 'différent', 'وصف'],
      ),
    ],
  ),
  _Category(
    icon: Icons.local_shipping_outlined,
    titleAr: 'التوصيل',
    titleFr: 'Livraison',
    titleEn: 'Delivery',
    items: const <_Faq>[
      _Faq(
        id: 'delivery_in_wilaya',
        qAr: 'هل يوجد توصيل داخل ولايتي؟',
        qFr: 'La livraison est-elle disponible dans ma wilaya ?',
        qEn: 'Is delivery available in my region?',
        aAr:
            'ذلك يعتمد على البائع. افتح الإعلان وتحقق من خيار التوصيل ورسومه.\nإذا لم يكن مذكوراً، اسأل البائع مباشرة.',
        aFr:
            'Cela dépend du vendeur. Ouvrez l\'annonce et vérifiez l\'option de livraison et les frais.\nSinon, demandez au vendeur.',
        aEn:
            'It depends on the seller. Open the listing and check delivery option and fee.\nIf not shown, ask the seller directly.',
        keywords: ['توصيل', 'livraison', 'delivery', 'رسوم'],
      ),
      _Faq(
        id: 'delivery_fee',
        qAr: 'كيف يتم تحديد رسوم التوصيل؟',
        qFr: 'Comment les frais de livraison sont-ils calculés ?',
        qEn: 'How is the delivery fee calculated?',
        aAr:
            'الرسوم يحددها البائع حسب المسافة والمدينة/الولاية.\nنصيحة: اتفق على السعر النهائي قبل الإرسال.',
        aFr:
            'Les frais sont fixés par le vendeur selon la distance et la ville/région.\nConseil: confirmez le prix final avant l\'envoi.',
        aEn:
            'The seller sets the fee based on distance and location.\nTip: confirm the final price before shipping.',
        keywords: ['رسوم', 'fee', 'frais', 'delivery'],
      ),
      _Faq(
        id: 'delivery_time',
        qAr: 'كم يستغرق التوصيل عادةً؟',
        qFr: 'Quel est le délai de livraison en général ?',
        qEn: 'How long does delivery usually take?',
        aAr: 'المدة تختلف حسب المدينة والمسافة وتوفر الناقل.\n'
            'نصيحة: اتفق مع البائع على الوقت والطريقة قبل الإرسال.',
        aFr:
            'Le délai dépend de la ville, de la distance et de la disponibilité du transport.\n'
            'Astuce: confirmez le délai et la méthode avec le vendeur avant l’envoi.',
        aEn: 'It depends on city, distance, and courier availability.\n'
            'Tip: agree on time and method with the seller before shipping.',
        keywords: ['مدة', 'time', 'délai', 'livraison'],
      ),
      _Faq(
        id: 'delivery_not_listed',
        qAr: 'لا أرى خيار التوصيل في الإعلان، لماذا؟',
        qFr: 'Je ne vois pas l’option livraison, pourquoi ?',
        qEn: 'I don’t see delivery option. Why?',
        aAr:
            'بعض البائعين لا يفعلون التوصيل. إذا لم يظهر الخيار، اسأل البائع مباشرة عبر الاتصال أو واتساب.',
        aFr:
            'Certains vendeurs ne proposent pas la livraison. Si l’option n’apparaît pas, contactez le vendeur (appel ou WhatsApp).',
        aEn:
            'Some sellers don’t offer delivery. If the option is not shown, contact the seller (call or WhatsApp).',
        keywords: ['لا أرى', 'option', 'livraison', 'delivery'],
      ),
    ],
  ),
  _Category(
    icon: Icons.assignment_return_outlined,
    titleAr: 'الإرجاع والاسترجاع',
    titleFr: 'Retours & remboursements',
    titleEn: 'Returns & refunds',
    items: const <_Faq>[
      _Faq(
        id: 'return_possible',
        qAr: 'هل يمكنني إرجاع المنتج؟',
        qFr: 'Puis-je retourner un produit ?',
        qEn: 'Can I return a product?',
        aAr: 'هذا يعتمد على البائع لأن التطبيق سوق يربطك بالبائع مباشرة.\n'
            'قبل الشراء: اسأل عن سياسة الإرجاع، وجرب المنتج إن أمكن.',
        aFr:
            'Cela dépend du vendeur car l’app est une marketplace qui vous met en relation directe.\n'
            'Avant l’achat: demandez la politique de retour et testez si possible.',
        aEn:
            'It depends on the seller because the app is a marketplace connecting you directly.\n'
            'Before buying: ask about return policy and test the item if possible.',
        keywords: ['إرجاع', 'return', 'retour', 'refund', 'استرجاع'],
      ),
      _Faq(
        id: 'damaged_item',
        qAr: 'ماذا أفعل إذا كان المنتج تالفاً؟',
        qFr: 'Que faire si le produit est endommagé ?',
        qEn: 'What if the item is damaged?',
        aAr: 'صوّر الضرر مباشرة وتواصل مع البائع فوراً.\n'
            'إذا كان هناك توصيل، اسأل عن المسؤولية قبل الدفع.\n'
            'يمكنك الإبلاغ عن الإعلان إذا كان مضللاً.',
        aFr:
            'Prenez des photos du dommage et contactez le vendeur immédiatement.\n'
            'En cas de livraison, clarifiez la responsabilité avant paiement.\n'
            'Vous pouvez signaler l’annonce si elle est trompeuse.',
        aEn: 'Take photos of the damage and contact the seller immediately.\n'
            'If delivered, clarify responsibility before paying.\n'
            'You can report the listing if it’s misleading.',
        keywords: ['تالف', 'endommagé', 'damaged', 'refund', 'إبلاغ'],
      ),
      _Faq(
        id: 'refund_possible',
        qAr: 'هل يوجد استرجاع أموال داخل التطبيق؟',
        qFr: 'Y a-t-il un remboursement dans l\'application?',
        qEn: 'Is there in-app refund?',
        aAr: 'حالياً المعاملات تتم بالاتفاق بينك وبين البائع (اتصال/واتساب).\n'
            'لذلك الاسترجاع يكون بالتفاهم مع البائع.\n'
            'نصيحة: تجنب الدفع المسبق بدون ضمان.',
        aFr:
            'Pour le moment, les transactions se font directement avec le vendeur (appel/WhatsApp).\n'
            'Donc le remboursement se fait par accord avec le vendeur.\n'
            'Astuce: évitez les paiements à l’avance sans garantie.',
        aEn:
            'For now, transactions are arranged directly with the seller (call/WhatsApp).\n'
            'So refunds are handled by agreement with the seller.\n'
            'Tip: avoid advance payments without protection.',
        keywords: ['استرجاع', 'refund', 'remboursement', 'دفع'],
      ),
      _Faq(
        id: 'dispute',
        qAr: 'حصل نزاع مع البائع، ماذا أفعل؟',
        qFr: 'Litige avec le vendeur, que faire ?',
        qEn: 'I have a dispute with the seller. What should I do?',
        aAr: 'حاول حل الأمر بهدوء واحتفظ بالرسائل كدليل.\n'
            'إذا كان هناك احتيال أو إساءة، استخدم خيار الإبلاغ أو الحظر.\n'
            'وفي الحالات الخطيرة، تواصل مع الجهات المختصة.',
        aFr:
            'Essayez de résoudre calmement et gardez les messages comme preuve.\n'
            'En cas de fraude أو abus, utilisez Signaler ou Bloquer.\n'
            'Pour les cas graves, contactez les autorités compétentes.',
        aEn: 'Try to resolve calmly and keep messages as proof.\n'
            'If there is fraud or abuse, use Report or Block.\n'
            'For serious cases, contact the appropriate authorities.',
        keywords: ['نزاع', 'litige', 'dispute', 'حظر', 'report'],
      ),
    ],
  ),
  _Category(
    icon: Icons.publish_outlined,
    titleAr: 'النشر',
    titleFr: 'Publication',
    titleEn: 'Publishing',
    items: const <_Faq>[
      _Faq(
        id: 'publish_effective',
        qAr: 'كيف أنشر إعلاناً فعالاً؟',
        qFr: 'Comment publier une annonce efficace ?',
        qEn: 'How do I publish an effective listing?',
        aAr:
            'اتبع هذه النصائح لزيادة المشاهدات:\n• صور واضحة بإضاءة جيدة (بدون فلاش قوي)\n• صوّر المنتج من عدة زوايا\n• اكتب تفاصيل مهمة: الحالة، المقاس/السعة، الملحقات\n• ضع ولاية ومكان صحيح\n• سعر منطقي أو اكتب "حسب الاتفاق" إن كان متغيراً',
        aFr:
            'Conseils pour augmenter les vues:\n• Photos nettes avec bonne lumière (sans flash fort)\n• Plusieurs angles\n• Détails importants: état, taille/capacité, accessoires\n• Localisation correcte\n• Prix raisonnable ou "À négocier" si variable',
        aEn:
            'Tips to get more views:\n• Clear photos with good lighting (avoid harsh flash)\n• Multiple angles\n• Key details: condition, size/capacity, accessories\n• Correct location\n• Fair price or "Negotiable" if flexible',
        keywords: ['نشر', 'publish', 'publication', 'صور', 'photos'],
      ),
      _Faq(
        id: 'publish_photos',
        qAr: 'ما أفضل دقة للصور؟',
        qFr: 'Quelle est la meilleure qualité pour les photos ?',
        qEn: 'What\'s the best photo quality?',
        aAr:
            'أفضل نتيجة: صور واضحة بدون اهتزاز.\n• نظّف عدسة الكاميرا\n• استخدم ضوء طبيعي\n• تجنب الصور المظلمة أو المقصوصة\n• لا تستخدم صوراً من الإنترنت إن أمكن',
        aFr:
            'Le mieux: photos nettes sans flou.\n• Nettoyez l\'objectif\n• Lumière naturelle\n• Évitez les photos sombres / recadrées\n• Évitez les photos d\'internet si possible',
        aEn:
            'Best results: sharp photos without blur.\n• Clean the lens\n• Use natural light\n• Avoid dark/cropped photos\n• Avoid internet images when possible',
        keywords: ['دقة', 'quality', 'qualité', 'صور'],
      ),
      _Faq(
        id: 'publish_details',
        qAr: 'ما التفاصيل التي يجب أن أكتبها؟',
        qFr: 'Quels détails dois-je écrire ?',
        qEn: 'What details should I write?',
        aAr: 'اكتب أهم ما يساعد المشتري على اتخاذ قرار:\n'
            '• الحالة (جديد/مستعمل)\n'
            '• المواصفات (المقاس/السعة/اللون/الموديل)\n'
            '• أي عيب... مع صور\n'
            '• الملحقات الموجودة\n'
            'كلما كانت التفاصيل أوضح، زادت الثقة والمشاهدات.',
        aFr: 'Écrivez les infos qui aident l’acheteur:\n'
            '• État (neuf/occasion)\n'
            '• Caractéristiques (taille/capacité/couleur/modèle)\n'
            '• Défauts éventuels... avec photos\n'
            '• Accessoires inclus\n'
            'Plus c’est clair, plus vous gagnez en confiance et en vues.',
        aEn: 'Write what helps buyers decide:\n'
            '• Condition (new/used)\n'
            '• Specs (size/capacity/color/model)\n'
            '• Any defect... with photos\n'
            '• Included accessories\n'
            'The clearer it is, the more trust and views you get.',
        keywords: ['تفاصيل', 'details', 'détails', 'وصف', 'description'],
      ),
      _Faq(
        id: 'publish_price',
        qAr: 'كيف أحدد السعر؟',
        qFr: 'Comment fixer le prix ?',
        qEn: 'How do I set the price?',
        aAr: 'نصائح سريعة:\n'
            '• قارن أسعار منتجات مشابهة\n'
            '• اذكر إن كان السعر قابل للتفاوض\n'
            '• إذا كان السعر متغيراً، استخدم "حسب الاتفاق"\n'
            '• لا تنس رسوم التوصيل إن وجدت',
        aFr: 'Conseils rapides:\n'
            '• Comparez avec des annonces similaires\n'
            '• Indiquez si c’est négociable\n'
            '• Si variable, utilisez "À négocier"\n'
            '• Pensez aux frais de livraison si besoin',
        aEn: 'Quick tips:\n'
            '• Compare similar listings\n'
            '• Say if it’s negotiable\n'
            '• If variable, use "Negotiable"\n'
            '• Consider delivery fee if applicable',
        keywords: ['سعر', 'price', 'prix', 'تفاوض', 'negociable'],
      ),
      _Faq(
        id: 'edit_listing',
        qAr: 'كيف أعدّل أو أحذف إعلاني؟',
        qFr: 'Comment modifier ou supprimer mon annonce ?',
        qEn: 'How do I edit or delete my listing?',
        aAr:
            'اذهب إلى صفحة "إعلاناتي" ثم اختر تعديل أو حذف.\nإذا تم البيع، يمكنك وضعه "مباع" ليظهر للزبائن أنه غير متاح.',
        aFr:
            'Allez dans "Mes annonces" puis choisissez Modifier ou Supprimer.\nSi vendu, marquez-le "Vendu" pour informer les acheteurs.',
        aEn:
            'Go to "My listings" then choose Edit or Delete.\nIf sold, mark it as "Sold" so buyers know it\'s unavailable.',
        keywords: ['تعديل', 'حذف', 'edit', 'delete', 'supprimer', 'modifier'],
        routeToOpen: '/you/listings',
      ),
    ],
  ),
  _Category(
    icon: Icons.inventory_2_outlined,
    titleAr: 'المنتج والمخزون',
    titleFr: 'Produit & stock',
    titleEn: 'Product & stock',
    items: const <_Faq>[
      _Faq(
        id: 'sold_out',
        qAr: 'المنتج غير متوفر أو تم بيعه، ماذا يحدث؟',
        qFr: 'Le produit est indisponible ou vendu, que se passe-t-il ?',
        qEn: 'If the item is unavailable or sold, what happens?',
        aAr:
            'إذا تم بيع المنتج، من الأفضل أن يقوم البائع بتحديده "مباع" أو حذفه من قائمة البيع حتى لا يضيع وقت المشترين.',
        aFr:
            'Si l’article est vendu, le vendeur devrait le marquer "Vendu" ou le supprimer afin d’éviter de perdre le temps des acheteurs.',
        aEn:
            'If an item is sold, the seller should mark it as "Sold" or remove it to avoid wasting buyers’ time.',
        keywords: ['مباع', 'sold', 'vendu', 'غير متوفر', 'stock'],
      ),
      _Faq(
        id: 'mark_sold',
        qAr: 'كيف أضع إعلاني "مباع"؟',
        qFr: 'Comment marquer mon annonce "Vendu" ?',
        qEn: 'How do I mark my listing as "Sold"?',
        aAr:
            'اذهب إلى "إعلاناتي" ثم اختر تعديل الحالة إلى مباع (أو احذف الإعلان إذا انتهى).',
        aFr:
            'Allez dans "Mes annonces" puis modifiez le statut en "Vendu" (ou supprimez l’annonce).',
        aEn:
            'Go to "My listings" and change the status to "Sold" (or delete the listing).',
        routeToOpen: '/you/listings',
        keywords: ['مباع', 'sold', 'vendu', 'إعلاناتي'],
      ),
      _Faq(
        id: 'view_count',
        qAr: 'ماذا يعني عدد المشاهدات؟',
        qFr: 'Que signifie le nombre de vues ?',
        qEn: 'What does view count mean?',
        aAr:
            'هو عدد مرات فتح صفحة الإعلان. زيادة المشاهدات عادة تعني أن العنوان والصور والسعر جذابون.',
        aFr:
            'C’est le nombre d’ouvertures de l’annonce. Plus de vues signifie souvent que le titre, les photos et le prix sont attractifs.',
        aEn:
            'It’s how many times people opened the listing. More views usually means the title, photos, and price are attractive.',
        keywords: ['مشاهدات', 'vues', 'views'],
      ),
      _Faq(
        id: 'share_listing',
        qAr: 'كيف أشارك إعلاناً مع شخص آخر؟',
        qFr: 'Comment partager une annonce ?',
        qEn: 'How do I share a listing?',
        aAr: 'من صفحة المنتج اضغط زر المشاركة ثم اختر واتساب أو أي تطبيق آخر.',
        aFr:
            'Depuis la page du produit, appuyez sur Partager puis choisissez WhatsApp ou une autre application.',
        aEn:
            'On the product page, tap Share and choose WhatsApp or another app.',
        keywords: ['مشاركة', 'share', 'partager', 'واتساب'],
      ),
      _Faq(
        id: 'warranty',
        qAr: 'هل يمكن إضافة ضمان للمنتج؟',
        qFr: 'Peut-on ajouter une garantie ?',
        qEn: 'Can I add a warranty?',
        aAr:
            'نعم إذا كان المنتج يشمل ضماناً. اذكر مدة الضمان ونوعه بوضوح داخل الإعلان، وأضف صورة الفاتورة إن وُجدت.',
        aFr:
            'Oui si le produit a une garantie. Indiquez la durée et le type clairement dans l’annonce, et ajoutez une photo de la facture si possible.',
        aEn:
            'Yes if the item has warranty. Mention duration and type clearly, and add an invoice photo if available.',
        keywords: ['ضمان', 'garantie', 'warranty'],
      ),
    ],
  ),
  _Category(
    icon: Icons.search_rounded,
    titleAr: 'البحث والفلاتر',
    titleFr: 'Recherche & filtres',
    titleEn: 'Search & filters',
    items: const <_Faq>[
      _Faq(
        id: 'filters',
        qAr: 'كيف أستخدم الفلاتر؟',
        qFr: 'Comment utiliser les filtres ?',
        qEn: 'How do I use filters?',
        aAr:
            'بعد البحث أو داخل الفئة، استخدم الفلاتر لتضييق النتائج:\n• الفئة\n• السعر (MRU)\n• الولاية\n• الترتيب (الأحدث / الأرخص)',
        aFr:
            'Après la recherche, utilisez les filtres:\n• Catégorie\n• Prix (MRU)\n• Wilaya\n• Tri (plus récent / moins cher)',
        aEn:
            'After searching, use filters:\n• Category\n• Price (MRU)\n• Region\n• Sorting (newest / lowest price)',
        keywords: ['فلاتر', 'filters', 'filtres', 'MRU', 'السعر'],
      ),
      _Faq(
        id: 'image_search',
        qAr: 'هل يوجد بحث بالصورة؟',
        qFr: 'La recherche par image est-elle disponible ?',
        qEn: 'Is image search available?',
        aAr:
            'إذا ظهرت أيقونة الكاميرا في البحث، يمكنك رفع صورة للعثور على منتجات مشابهة.\nإذا لم تكن متاحة عندك حالياً، فهي قيد الإطلاق قريباً.',
        aFr:
            'Si l\'icône caméra apparaît dans la recherche, vous pouvez envoyer une image pour trouver des produits similaires.\nSi ce n\'est pas encore disponible, la fonctionnalité arrive bientôt.',
        aEn:
            'If the camera icon appears in search, you can upload a photo to find similar products.\nIf it\'s not available yet, it\'s coming soon.',
        keywords: ['صورة', 'image', 'caméra', 'camera'],
      ),
    ],
  ),
  _Category(
    icon: Icons.security_outlined,
    titleAr: 'الأمان والبلاغات',
    titleFr: 'Sécurité & signalement',
    titleEn: 'Safety & reporting',
    items: const <_Faq>[
      _Faq(
        id: 'safe_meet',
        qAr: 'كيف أشتري بأمان؟',
        qFr: 'Comment acheter en toute sécurité ?',
        qEn: 'How do I buy safely?',
        aAr:
            '• قابل البائع في مكان عام\n• جرّب المنتج قبل الدفع\n• تجنب إرسال المال مقدماً\n• إذا كان العرض يبدو غير منطقي: كن حذراً',
        aFr:
            '• Rencontrez le vendeur dans un lieu public\n• Testez le produit avant paiement\n• Évitez les paiements à l\'avance\n• Si l\'offre semble trop belle: soyez prudent',
        aEn:
            '• Meet in a public place\n• Test before paying\n• Avoid advance payments\n• If the deal looks too good: be careful',
        keywords: ['أمان', 'sécurité', 'safety', 'احتيال', 'fraud'],
      ),
      _Faq(
        id: 'block_seller',
        qAr: 'كيف أحظر بائعاً؟',
        qFr: 'Comment bloquer un vendeur ?',
        qEn: 'How do I block a seller?',
        aAr:
            'من صفحة المنتج أو صفحة البائع اختر "حظر".\nبعد الحظر لن ترى إعلاناته.',
        aFr:
            'Depuis la page du produit ou du vendeur, choisissez "Bloquer".\nAprès blocage, vous ne verrez plus ses annonces.',
        aEn:
            'From the product page or seller page, choose "Block".\nAfter blocking, you won\'t see their listings.',
        keywords: ['حظر', 'block', 'bloquer'],
        routeToOpen: '/you/blocked',
      ),
    ],
  ),
  _Category(
    icon: Icons.person_outline_rounded,
    titleAr: 'الحساب',
    titleFr: 'Compte',
    titleEn: 'Account',
    items: const <_Faq>[
      _Faq(
        id: 'guest',
        qAr: 'هل يمكنني استخدام التطبيق كزائر؟',
        qFr: 'Puis-je utiliser l\'app en invité ?',
        qEn: 'Can I use the app as a guest?',
        aAr:
            'نعم. يمكنك التصفح والبحث كزائر.\nلكن لن تتمكن من نشر إعلان أو مزامنة المفضلة إلا بعد تسجيل الدخول.',
        aFr:
            'Oui. Vous pouvez parcourir et rechercher en mode invité.\nPour publier ou synchroniser vos favoris, connectez-vous.',
        aEn:
            'Yes. You can browse and search as a guest.\nTo publish or sync favorites, you need to sign in.',
        keywords: ['زائر', 'invité', 'guest', 'تسجيل'],
      ),
      _Faq(
        id: 'otp',
        qAr: 'لماذا لا يعمل رمز OTP؟',
        qFr: 'Pourquoi le code OTP ne fonctionne pas ?',
        qEn: 'Why is the OTP code not working?',
        aAr:
            'تأكد من:\n• إدخال الرقم الصحيح\n• اتصال الإنترنت\n• انتظر دقيقة ثم أعد الإرسال\nإذا استمرت المشكلة، تواصل معنا عبر واتساب.',
        aFr:
            'Vérifiez:\n• Le code correct\n• Connexion internet\n• Attendez une minute puis renvoyez\nSi le problème persiste, contactez-nous via WhatsApp.',
        aEn:
            'Check:\n• Correct code\n• Internet connection\n• Wait a minute then resend\nIf it persists, contact us on WhatsApp.',
        keywords: ['OTP', 'رمز', 'code'],
      ),
    ],
  ),
  _Category(
    icon: Icons.notifications_outlined,
    titleAr: 'الإشعارات',
    titleFr: 'Notifications',
    titleEn: 'Notifications',
    items: const <_Faq>[
      _Faq(
        id: 'notif_about',
        qAr: 'ما هي الإشعارات داخل التطبيق؟',
        qFr: 'Quelles notifications dans l\'app ?',
        qEn: 'What notifications are in the app?',
        aAr:
            'ستظهر لك إشعارات مهمة فقط مثل:\n• التخفيضات والعروض\n• حالة إعلاناتك (نشر/رفض/مباع)\n• تنبيهات النظام ونصائح الأمان\nيمكنك تصفيتها من داخل صفحة الإشعارات.',
        aFr:
            'Vous verrez uniquement des notifications utiles :\n• Promotions\n• Statut de vos annonces (publiée/refusée/vendue)\n• Système & conseils sécurité\nVous pouvez les filtrer dans l\'écran Notifications.',
        aEn:
            'You will only see useful notifications:\n• Deals & discounts\n• Your listings status (published/rejected/sold)\n• System alerts & safety tips\nYou can filter them in the Notifications screen.',
        keywords: [
          'إشعارات',
          'notifications',
          'promo',
          'تخفيضات',
          'إعلاناتي',
          'system'
        ],
      ),
      _Faq(
        id: 'notif_badge',
        qAr: 'ماذا يعني الرقم على أيقونة الجرس؟',
        qFr: 'Que signifie le numéro sur la cloche ?',
        qEn: 'What does the badge number mean?',
        aAr:
            'الرقم يعني عدد الإشعارات غير المقروءة. عند فتح إشعار أو تحديد الكل كمقروء سيختفي الرقم.',
        aFr:
            'Le numéro indique les notifications non lues. Il disparaît après lecture ou “tout marquer comme lu”.',
        aEn:
            'It shows how many notifications are unread. It clears after reading or marking all as read.',
        keywords: ['رقم', 'badge', 'غير مقروء', 'unread', 'جرس'],
      ),
      _Faq(
        id: 'notif_push',
        qAr: 'هل تصل إشعارات للهاتف (Push)؟',
        qFr: 'Y a-t-il des notifications push ?',
        qEn: 'Are push notifications available?',
        aAr:
            'حالياً الإشعارات داخل التطبيق فقط. إشعارات الهاتف (Push) قيد الإطلاق قريباً.',
        aFr:
            'Pour le moment, notifications dans l\'app uniquement. Les push arrivent bientôt.',
        aEn:
            'For now, notifications are in-app only. Push notifications are coming soon.',
        keywords: ['push', 'هاتف', 'FCM', 'قريباً', 'bientôt', 'soon'],
      ),
      _Faq(
        id: 'notif_settings',
        qAr: 'هل يمكنني إيقاف نوع معيّن من الإشعارات؟',
        qFr: 'Puis-je désactiver un type de notification ?',
        qEn: 'Can I disable a specific notification type?',
        aAr:
            'الإعدادات المتقدمة (إيقاف التخفيضات أو النظام...) ستكون متاحة قريباً ضمن صفحة الإشعارات.',
        aFr:
            'Les réglages avancés (désactiver promos/système…) seront disponibles bientôt.',
        aEn:
            'Advanced settings (turn off deals/system…) will be available soon in Notifications.',
        keywords: ['إيقاف', 'settings', 'désactiver', 'disable', 'قريباً'],
      ),
    ],
  ),
];
