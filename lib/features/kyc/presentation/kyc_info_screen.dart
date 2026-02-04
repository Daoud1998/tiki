import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/tikki_tr.dart';
import '../../../core/widgets/dir_chevrons.dart';

import '../data/kyc_settings_repository.dart';
import '../domain/kyc_models.dart';
import 'kyc_ui.dart';

class KycInfoScreen extends ConsumerWidget {
  const KycInfoScreen({super.key});

  String _modeLabel(BuildContext context, String mode) {
    switch (mode) {
      case 'optional':
        return tikkiTr(context, ar: 'اختياري', fr: 'Optionnel', en: 'Optional');
      case 'high_risk_only':
        return tikkiTr(context, ar: 'فئات/سعر عالي', fr: 'Risque élevé', en: 'High risk');
      case 'after_grace':
        return tikkiTr(context, ar: 'بعد فترة سماح', fr: 'Après délai', en: 'After grace');
      case 'on_publish':
        return tikkiTr(context, ar: 'عند النشر', fr: 'À la publication', en: 'On publish');
      case 'payments_only':
        return tikkiTr(context, ar: 'للمدفوعات فقط', fr: 'Paiements seulement', en: 'Payments only');
      default:
        return mode;
    }
  }

  String _catsLabel(BuildContext context, List<String> cats) {
    if (cats.isEmpty) return '-';
    String one(String id) {
      switch (id) {
        case 'vehicles':
          return tikkiTr(context, ar: 'مركبات', fr: 'Véhicules', en: 'Vehicles');
        case 'real_estate':
          return tikkiTr(context, ar: 'عقارات', fr: 'Immobilier', en: 'Real estate');
        default:
          return id;
      }
    }

    return cats.map(one).join('، ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = tikkiTr(context, ar: 'إعدادات التوثيق', fr: 'Paramètres KYC', en: 'KYC settings');
    final settingsAsync = ref.watch(kycSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(icon: DirChevrons.backIos(context), onPressed: () => context.pop()),
      ),
      body: settingsAsync.when(
        data: (KycSettings s) {
          final enabledLabel = s.enabled
              ? tikkiTr(context, ar: 'مفعّل', fr: 'Actif', en: 'Enabled')
              : tikkiTr(context, ar: 'مطفأ', fr: 'Désactivé', en: 'Disabled');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              KycHintCard(
                icon: Icons.info_outline,
                text: tikkiTr(
                  context,
                  ar: 'هذه صفحة عرض فقط. التحكم الحقيقي سيتم لاحقاً من تطبيق الإدارة (Admin).',
                  fr: "Page d'affichage فقط. Contrôle via Admin لاحقاً.",
                  en: 'Read-only screen. Admin will control these later.',
                ),
              ),
              const SizedBox(height: 14),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      KycValueRow(
                        label: tikkiTr(context, ar: 'التفعيل', fr: 'Activation', en: 'Enabled'),
                        value: enabledLabel,
                        icon: s.enabled ? Icons.toggle_on : Icons.toggle_off,
                      ),
                      const Divider(height: 1),
                      KycValueRow(
                        label: tikkiTr(context, ar: 'الوضع', fr: 'Mode', en: 'Mode'),
                        value: _modeLabel(context, s.mode),
                        icon: Icons.tune_rounded,
                      ),
                      const Divider(height: 1),
                      KycValueRow(
                        label: tikkiTr(context, ar: 'سماح قبل الإلزام', fr: 'Grace', en: 'Grace'),
                        value: s.graceAdsCount.toString(),
                        icon: Icons.timelapse_rounded,
                      ),
                      const Divider(height: 1),
                      KycValueRow(
                        label: tikkiTr(context, ar: 'حد السعر (MRU)', fr: 'Seuil (MRU)', en: 'Price threshold (MRU)'),
                        value: s.priceThresholdMru.toString(),
                        icon: Icons.payments_outlined,
                      ),
                      const Divider(height: 1),
                      KycValueRow(
                        label: tikkiTr(context, ar: 'فئات عالية المخاطر', fr: 'Catégories risque', en: 'High-risk categories'),
                        value: _catsLabel(context, s.requiredCategories),
                        icon: Icons.warning_amber_rounded,
                      ),
                      const Divider(height: 1),
                      KycValueRow(
                        label: tikkiTr(context, ar: 'حد الإعلانات لغير الموثّق', fr: 'Limite non vérifié', en: 'Unverified ads limit'),
                        value: s.unverifiedAdsLimit.toString(),
                        icon: Icons.block_outlined,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        error: (e, _) => Center(child: Text(e.toString())),
      ),
    );
  }
}
