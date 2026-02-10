import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/tikki_tr.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/widgets/dir_chevrons.dart';

import '../data/kyc_settings_repository.dart';
import '../domain/kyc_models.dart';
import '../state/kyc_controller.dart';
import 'kyc_ui.dart';

class VerificationScreen extends ConsumerWidget {
  const VerificationScreen({super.key});

  Future<void> _openWhatsApp(
    BuildContext context, {
    required String phoneE164,
    required String message,
  }) async {
    final phone = phoneE164.replaceAll('+', '').replaceAll(' ', '').trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tikkiTr(context,
              ar: 'رقم واتساب غير مضبوط',
              fr: 'Numéro WhatsApp manquant',
              en: 'WhatsApp number missing')),
        ),
      );
      return;
    }

    final uri =
        Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');

    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tikkiTr(context,
                ar: 'تعذر فتح واتساب',
                fr: "Impossible d'ouvrir WhatsApp",
                en: 'Cannot open WhatsApp')),
          ),
        );
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _buildWaMessage({
    required String template,
    required AuthState auth,
  }) {
    return template
        .replaceAll('{{uid}}', (auth.userId ?? '').trim())
        .replaceAll('{{name}}', (auth.name ?? '').trim())
        .replaceAll('{{phone}}', (auth.phoneE164 ?? '').trim());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final local = ref.watch(kycControllerProvider);
    final uiAsync = ref.watch(kycVerificationUiSettingsProvider);

    final title = tikkiTr(context,
        ar: 'موثّق تيكي', fr: 'Tikki Vérifié', en: 'Tikki Verified');

    IconData statusIcon(String status) {
      switch (status) {
        case 'approved':
          return Icons.verified_rounded;
        case 'pending':
          return Icons.hourglass_top_rounded;
        case 'rejected':
          return Icons.cancel_rounded;
        case 'wallet_verified':
          return Icons.verified_rounded;
        default:
          return Icons.info_outline_rounded;
      }
    }

    String statusLabel(String status) {
      switch (status) {
        case 'approved':
          return tikkiTr(context,
              ar: 'موثّق ✅', fr: 'Vérifié ✅', en: 'Verified ✅');
        case 'pending':
          return tikkiTr(context,
              ar: 'قيد المراجعة', fr: 'En attente', en: 'Pending');
        case 'rejected':
          return tikkiTr(context, ar: 'مرفوض', fr: 'Refusé', en: 'Rejected');
        case 'wallet_verified':
          return tikkiTr(context,
              ar: 'موثّق ✅', fr: 'Vérifié ✅', en: 'Verified ✅');
        default:
          return tikkiTr(context,
              ar: 'غير موثّق', fr: 'Non vérifié', en: 'Not verified');
      }
    }

    Widget buildBody(KycVerificationUiSettings ui) {
      final enabled = ui.allowInApp || ui.allowWhatsApp;
      final st = local.status;

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          KycHeaderCard(
            statusLabel: statusLabel(st),
            statusIcon: statusIcon(st),
            enabled: enabled,
          ),
          const SizedBox(height: 12),
          KycHintCard(
            icon: Icons.lock_outline,
            text: tikkiTr(
              context,
              ar: 'الوثائق لا تظهر للمستخدمين. تُراجع من الإدارة فقط.',
              fr: "Les documents ne sont pas visibles. Revue par l'admin uniquement.",
              en: 'Documents are not public. Reviewed by admin only.',
            ),
          ),
          const SizedBox(height: 14),

          // Benefits (admin-controlled)
          KycSection(
            title: tikkiTr(context,
                ar: 'مزايا التوثيق', fr: 'Avantages', en: 'Benefits'),
            subtitle: tikkiTr(
              context,
              ar: 'لماذا أوثّق حسابي؟',
              fr: 'Pourquoi vérifier ?',
              en: 'Why verify?',
            ),
            icon: Icons.stars_rounded,
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...ui.benefitsFor(Localizations.localeOf(context).languageCode).map((line) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(line),
                        )),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Methods (only two)
          KycSection(
            title: tikkiTr(context,
                ar: 'طرق التوثيق', fr: 'Méthodes', en: 'Methods'),
            subtitle: tikkiTr(   
              context,
              ar: 'اختر طريقة واحدة فقط: داخل التطبيق أو واتساب.',
              fr: "Choisissez une méthode : dans l'application ou WhatsApp.",
              en: 'Choose: in-app or WhatsApp.',
            ),
            icon: Icons.verified_user_outlined,
            child: Column(
              children: [
                // In-app
                KycOptionCard(
                  title: tikkiTr(context,
                      ar: 'توثيق داخل التطبيق',
                      fr: "Dans l'application",
                      en: 'In-app verification'),
                  subtitle: tikkiTr(context,
                      ar: 'ارفع صورة وثيقة (بطاقة/رخصة/إقامة) + سيلفي',
                      fr: 'Document + Selfie',
                      en: 'Document + Selfie'),
                  icon: Icons.upload_file_rounded,
                  badge: ui.allowInApp
                      ? tikkiTr(context,
                          ar: 'متاح', fr: 'Disponible', en: 'Available')
                      : tikkiTr(context,
                          ar: 'غير متاح',
                          fr: 'Indisponible',
                          en: 'Unavailable'),
                  enabled: ui.allowInApp,
                  onTap: () {
                    if (!auth.isSignedIn) {
                      context.push('/auth?next=%2Fyou%2Fverify%2Fsubmit');
                      return;
                    }
                    context.push('/you/verify/submit');
                  },
                ),

                const SizedBox(height: 10),

                // WhatsApp
                KycOptionCard(
                  title: tikkiTr(context,
                      ar: 'توثيق عبر واتساب',
                      fr: 'Via WhatsApp',
                      en: 'Via WhatsApp'),
                  subtitle: tikkiTr(context,
                      ar: 'أرسل الوثيقة + السيلفي للدعم',
                      fr: 'Envoyez au support',
                      en: 'Send to support'),
                  icon: Icons.chat_rounded,
                  badge: ui.allowWhatsApp
                      ? tikkiTr(context,
                          ar: 'متاح', fr: 'Disponible', en: 'Available')
                      : tikkiTr(context,
                          ar: 'غير متاح',
                          fr: 'Indisponible',
                          en: 'Unavailable'),
                  enabled: ui.allowWhatsApp,
                  onTap: ui.allowWhatsApp
                      ? () async {
                          final msg = _buildWaMessage(
                            template: ui.whatsAppTemplateFor(Localizations.localeOf(context).languageCode),
                            auth: auth,
                          );
                          await _openWhatsApp(
                            context,
                            phoneE164: ui.whatsAppNumber,
                            message: msg,
                          );
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: DirChevrons.backIos(context),
          onPressed: () => context.pop(),
        ),
      ),
      body: uiAsync.when(
        data: (ui) => buildBody(ui),
        loading: () => const Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator())),
        error: (e, _) => buildBody(KycVerificationUiSettings.defaults()),
      ),
    );
  }
}
