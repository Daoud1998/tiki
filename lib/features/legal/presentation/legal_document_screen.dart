import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Simple in-app legal document viewer (no Firestore yet).
///
/// It enforces “read before accept” by disabling the accept button until:
/// - user scrolls near the bottom, OR
/// - a short timer passes.
///
/// Returns `true` when user taps the accept button.
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({super.key, required this.docId});

  /// 'privacy' | 'terms'
  final String docId;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  final _ctl = ScrollController();
  bool _canAccept = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onScroll);

    // Safety timer: even if content is short, allow accept after a moment.
    Future<void>.delayed(const Duration(seconds: 3)).then((_) {
      if (!mounted || _disposed) return;
      setState(() => _canAccept = true);
    });
  }

  void _onScroll() {
    if (_canAccept) return;
    final pos = _ctl.position;
    if (!pos.hasPixels || !pos.hasContentDimensions) return;
    final nearBottom = (pos.maxScrollExtent - pos.pixels) < 120;
    if (nearBottom && mounted) setState(() => _canAccept = true);
  }

  @override
  void dispose() {
    _disposed = true;
    _ctl.removeListener(_onScroll);
    _ctl.dispose();
    super.dispose();
  }

  String _tr({required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final isPrivacy = widget.docId.toLowerCase() == 'privacy';

    void popOrHome() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    }

    final title = isPrivacy
        ? _tr(ar: 'سياسة الخصوصية', fr: 'Confidentialité', en: 'Privacy Policy')
        : _tr(
            ar: 'الشروط والأحكام', fr: 'Conditions', en: 'Terms & Conditions');

    final body = isPrivacy ? _privacyText() : _termsText();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        popOrHome();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: popOrHome,
            icon: Icon(
              rtl
                  ? Icons.arrow_forward_ios_rounded
                  : Icons.arrow_back_ios_new_rounded,
            ),
          ),
          title: Text(title),
        ),
        body: Column(
          children: [
            Expanded(
              child: Scrollbar(
                child: ListView(
                  controller: _ctl,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(18),
                        border:
                            Border.all(color: cs.outlineVariant.withAlpha(140)),
                      ),
                      child: Text(
                        body,
                        style: TextStyle(
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withAlpha(220),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _tr(
                        ar: 'ملاحظة: هذا نص تجريبي إلى أن تضيف نصك النهائي.',
                        fr: 'Note: texte provisoire en attendant votre version finale.',
                        en: 'Note: placeholder text until you add your final version.',
                      ),
                      style: TextStyle(
                        color: cs.onSurface.withAlpha(170),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: FilledButton.icon(
                  onPressed: !_canAccept
                      ? null
                      : () {
                          final nav = Navigator.of(context);
                          if (nav.canPop()) {
                            nav.pop(true);
                          } else {
                            popOrHome();
                          }
                        },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                      _tr(ar: 'قرأت وفهمت', fr: 'J’ai lu', en: 'I have read')),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  String _privacyText() {
    return _tr(
      ar: 'سياسة الخصوصية\n\n'
          '1) ما الذي نجمعه\n'
          '- قد نجمع معلومات أساسية عند النشر مثل رقم الهاتف، الولاية، وصور المنتج.\n\n'
          '2) كيف نستخدم المعلومات\n'
          '- عرض إعلانك للمستخدمين وتسهيل التواصل مع البائع.\n'
          '- تحسين تجربة البحث والفرز داخل التطبيق.\n\n'
          '3) المشاركة\n'
          '- لا نبيع بياناتك. قد نشارك الحد الأدنى اللازم لتشغيل الميزات (مثلاً: فتح واتساب).\n\n'
          '4) التحكم\n'
          '- يمكنك حذف إعلانك أو تعديل بياناته في أي وقت.\n\n'
          '5) التواصل\n'
          '- للدعم: من صفحة الدعم داخل التطبيق.',
      fr: 'Politique de confidentialité\n\n'
          '1) Données collectées\n'
          '- Informations de base lors de la publication: téléphone, région, photos.\n\n'
          '2) Utilisation\n'
          '- Afficher votre annonce et faciliter le contact.\n'
          '- Améliorer la recherche et le tri.\n\n'
          '3) Partage\n'
          '- Nous ne vendons pas vos données. Partage minimal pour les fonctionnalités.\n\n'
          '4) Contrôle\n'
          '- Vous pouvez modifier/supprimer votre annonce à tout moment.\n\n'
          '5) Contact\n'
          '- Support: via la page Support dans l’app.',
      en: 'Privacy Policy\n\n'
          '1) What we collect\n'
          '- Basic info when publishing: phone, region, product photos.\n\n'
          '2) How we use it\n'
          '- Show your listing and enable contact.\n'
          '- Improve search and sorting.\n\n'
          '3) Sharing\n'
          '- We do not sell your data. Minimal sharing to enable features.\n\n'
          '4) Control\n'
          '- You can edit or delete your listing anytime.\n\n'
          '5) Contact\n'
          '- Support: from the in-app Support page.',
    );
  }

  String _termsText() {
    return _tr(
      ar: 'الشروط والأحكام\n\n'
          '1) مسؤولية المحتوى\n'
          '- البائع مسؤول عن صحة معلومات الإعلان وصوره وسعره.\n\n'
          '2) المحتوى الممنوع\n'
          '- يمنع نشر أي محتوى مخالف للقانون أو مسيء أو احتيالي.\n\n'
          '3) التواصل\n'
          '- التواصل بين المشتري والبائع مباشر. التطبيق لا يضمن إتمام الصفقة.\n\n'
          '4) التعديلات\n'
          '- قد نقوم بتحديث هذه الشروط داخل التطبيق.\n\n'
          '5) الإبلاغ والحظر\n'
          '- يمكنك الإبلاغ عن إعلان وحظر البائع من داخل التطبيق.',
      fr: 'Conditions générales\n\n'
          '1) Responsabilité\n'
          '- Le vendeur est responsable des informations, photos et prix.\n\n'
          '2) Contenu interdit\n'
          '- Interdiction de publier du contenu illégal, offensant ou frauduleux.\n\n'
          '3) Contact\n'
          '- Contact direct acheteur-vendeur. L’application ne garantit pas la transaction.\n\n'
          '4) Mises à jour\n'
          '- Ces conditions peuvent être mises à jour dans l’application.\n\n'
          '5) Signalement\n'
          '- Vous pouvez signaler une annonce et bloquer un vendeur.',
      en: 'Terms & Conditions\n\n'
          '1) Content responsibility\n'
          '- Sellers are responsible for listing info, photos, and price.\n\n'
          '2) Prohibited content\n'
          '- No illegal, offensive, or fraudulent content.\n\n'
          '3) Communication\n'
          '- Buyer and seller communicate directly. The app does not guarantee deals.\n\n'
          '4) Changes\n'
          '- We may update these terms in-app.\n\n'
          '5) Report & block\n'
          '- You can report listings and block sellers in the app.',
    );
  }
}
