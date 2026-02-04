import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tiki/features/content/presentation/content_data.dart';

import '../../../core/utils/formatters.dart';
import '../domain/service_receipt.dart';
import '../services/receipt_pdf_service.dart';
import 'receipts_controller.dart';

class ReceiptDetailsScreen extends ConsumerWidget {
  const ReceiptDetailsScreen({super.key, required this.receiptId});

  final String receiptId;

  String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    return tikkiTr(context, ar: ar, fr: fr, en: en);
  }

  String _kindLabel(BuildContext context, ServiceReceiptKind kind) {
    switch (kind) {
      case ServiceReceiptKind.productVip:
        return _tr(context,
            ar: 'VIP للمنتج', fr: 'VIP produit', en: 'Product VIP');
      case ServiceReceiptKind.promoAdVip:
        return _tr(context, ar: 'VIP للإعلان', fr: 'VIP pub', en: 'Ad VIP');
      case ServiceReceiptKind.productActivation:
        return _tr(context,
            ar: 'تفعيل المنتج', fr: 'Activation', en: 'Activation');
    }
  }

  String _statusLabel(BuildContext context, ServiceReceiptStatus status) {
    switch (status) {
      case ServiceReceiptStatus.pending:
        return _tr(context,
            ar: 'قيد المراجعة', fr: 'En attente', en: 'Pending');
      case ServiceReceiptStatus.active:
        return _tr(context, ar: 'نشط', fr: 'Actif', en: 'Active');
      case ServiceReceiptStatus.expired:
        return _tr(context, ar: 'منتهي', fr: 'Expiré', en: 'Expired');
      case ServiceReceiptStatus.cancelled:
        return _tr(context, ar: 'ملغي', fr: 'Annulé', en: 'Cancelled');
      case ServiceReceiptStatus.failed:
        return _tr(context, ar: 'فشل', fr: 'Échec', en: 'Failed');
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _pricingBlock(BuildContext context, ServiceReceipt r) {
    final m = r.meta;
    if (m.isEmpty) return const SizedBox.shrink();
    final model = '${m['pricingModel'] ?? ''}'.trim();
    if (model.isEmpty) return const SizedBox.shrink();

    String line(String k, String v) => '$k: $v';

    final tier = '${m['tier'] ?? ''}'.trim();
    final days = '${m['days'] ?? ''}'.trim();
    final pct = m['percent'];
    final mult = m['durationMultiplier'];
    final usedPrice = '${m['usedPriceMru'] ?? ''}'.trim();
    final fallback = m['usedFallbackPrice'] == true;

    final raw = m['rawAmountMru'];
    final clamped = m['clampedAmountMru'];
    final finalAmt = m['finalAmountMru'];
    final minAmt = m['minMru'];
    final maxAmt = m['maxMru'];

    final items = <String>[];
    items.add(line(
        _tr(context, ar: 'نموذج التسعير', fr: 'Modèle', en: 'Model'), model));
    if (tier.isNotEmpty) {
      items
          .add(line(_tr(context, ar: 'الفئة', fr: 'Niveau', en: 'Tier'), tier));
    }
    if (days.isNotEmpty) {
      items.add(line(_tr(context, ar: 'المدة', fr: 'Durée', en: 'Days'), days));
    }
    if (pct is num) {
      items.add(line(
          _tr(context, ar: 'النسبة', fr: 'Pourcentage', en: 'Percent'),
          '${(pct * 100).toStringAsFixed(1)}%'));
    }
    if (mult is num) {
      items.add(line(
          _tr(context,
              ar: 'معامل المدة', fr: 'Facteur durée', en: 'Duration factor'),
          mult.toStringAsFixed(2)));
    }
    if (usedPrice.isNotEmpty) {
      items.add(line(
          _tr(context,
              ar: 'سعر المنتج المستخدم', fr: 'Prix utilisé', en: 'Used price'),
          '$usedPrice MRU'));
    }
    if (raw is num) {
      items.add(line(
          _tr(context,
              ar: 'المبلغ الخام', fr: 'Montant brut', en: 'Raw amount'),
          '${(raw).toInt()} MRU'));
    }
    final minV = (minAmt is num) ? (minAmt).toInt() : null;
    final maxV = (maxAmt is num) ? (maxAmt).toInt() : null;
    if (minV != null || maxV != null) {
      final bounds = [
        if (minV != null)
          '${_tr(context, ar: 'حد أدنى', fr: 'Min', en: 'Min')}: $minV',
        if (maxV != null)
          '${_tr(context, ar: 'حد أقصى', fr: 'Max', en: 'Max')}: $maxV',
      ].join(' • ');
      items.add(
          line(_tr(context, ar: 'الحدود', fr: 'Bornes', en: 'Bounds'), bounds));
    }
    if (clamped is num) {
      items.add(line(
          _tr(context,
              ar: 'بعد الحدود', fr: 'Après bornes', en: 'After bounds'),
          '${(clamped).toInt()} MRU'));
    }
    if (finalAmt is num) {
      items.add(line(
          _tr(context,
              ar: 'المبلغ النهائي', fr: 'Montant final', en: 'Final amount'),
          '${(finalAmt).toInt()} MRU'));
    }
    if (fallback) {
      items.add(_tr(context,
          ar: 'تم استخدام سعر مرجعي (لا يوجد سعر واضح)',
          fr: 'Prix de référence utilisé',
          en: 'Fallback used'));
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr(context,
                ar: 'تفاصيل التسعير',
                fr: 'Détails prix',
                en: 'Pricing details'),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          for (final s in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(s),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref
        .watch(receiptsControllerProvider
            .select((list) => list.where((e) => e.id == receiptId).toList()))
        .firstOrNull;

    final cs = Theme.of(context).colorScheme;

    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(
          title:
              Text(_tr(context, ar: 'الفاتورة', fr: 'Facture', en: 'Receipt')),
        ),
        body: Center(
          child: Text(
            _tr(context,
                ar: 'لم يتم العثور على الفاتورة',
                fr: 'Facture introuvable',
                en: 'Receipt not found'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    final locale = Localizations.localeOf(context).languageCode.toLowerCase();
    final title = (locale == 'fr')
        ? (receipt.subjectTitleFr ??
            receipt.subjectTitleAr ??
            receipt.subjectTitleEn)
        : (locale == 'en')
            ? (receipt.subjectTitleEn ??
                receipt.subjectTitleAr ??
                receipt.subjectTitleFr)
            : (receipt.subjectTitleAr ??
                receipt.subjectTitleEn ??
                receipt.subjectTitleFr);

    final amount = Formatters.priceMRU(receipt.amountMru);

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr(context, ar: 'الفاتورة', fr: 'Facture', en: 'Receipt')),
        actions: [
          IconButton(
            tooltip: _tr(context,
                ar: 'مشاركة PDF', fr: 'Partager PDF', en: 'Share PDF'),
            onPressed: () async {
              await ReceiptPdfService.sharePdf(receipt, localeCode: locale);
            },
            icon: const Icon(Icons.share_rounded),
          ),
          IconButton(
            tooltip: _tr(context, ar: 'طباعة', fr: 'Imprimer', en: 'Print'),
            onPressed: () async {
              await ReceiptPdfService.printPdf(receipt, localeCode: locale);
            },
            icon: const Icon(Icons.print_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        children: [
          _HeaderCard(
            title: title ?? _kindLabel(context, receipt.kind),
            subtitle: '${_kindLabel(context, receipt.kind)} · $amount',
            chipText: _statusLabel(context, receipt.status),
          ),
          const SizedBox(height: 12),
          _InfoCard(
            rows: [
              _InfoRow(
                label: _tr(context,
                    ar: 'رقم الفاتورة', fr: 'N° facture', en: 'Receipt #'),
                value: receipt.id,
              ),
              _InfoRow(
                label: _tr(context,
                    ar: 'تاريخ الإنشاء', fr: 'Créée le', en: 'Created'),
                value: _fmt(receipt.createdAt),
              ),
              _InfoRow(
                label: _tr(context,
                    ar: 'رقم العملية', fr: 'Transaction', en: 'TX id'),
                value: receipt.transactionId ?? '-',
              ),
              _InfoRow(
                label:
                    _tr(context, ar: 'بداية الخدمة', fr: 'Début', en: 'Starts'),
                value: _fmt(receipt.startsAt),
              ),
              _InfoRow(
                label: _tr(context, ar: 'نهاية الخدمة', fr: 'Fin', en: 'Ends'),
                value: _fmt(receipt.endsAt),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _pricingBlock(context, receipt),
          const SizedBox(height: 12),
          if (receipt.kind == ServiceReceiptKind.productVip ||
              receipt.kind == ServiceReceiptKind.promoAdVip)
            _ActionsCard(
              onRenew: () {
                context.push('/you/listings');
              },
              renewLabel: _tr(context,
                  ar: 'تجديد / طلب VIP',
                  fr: 'Renouveler / VIP',
                  en: 'Renew / VIP'),
            ),
          const SizedBox(height: 14),
          Text(
            _tr(context,
                ar: 'ملاحظة: هذه الفاتورة مرجعية داخل التطبيق (وضع تجريبي).',
                fr: "Note : facture de référence (mode démo).",
                en: 'Note: Reference receipt (demo mode).'),
            style: TextStyle(
              color: cs.onSurface.withAlpha(170),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNullExt<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.chipText,
  });

  final String title;
  final String subtitle;
  final String chipText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(18),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.receipt_long_rounded, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primary.withAlpha(16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cs.primary.withAlpha(70)),
                      ),
                      child: Text(
                        chipText,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface.withAlpha(180),
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

class _InfoRow {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    rows[i].label,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface.withAlpha(190),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: SelectableText(
                    rows[i].value,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withAlpha(170),
                    ),
                  ),
                ),
              ],
            ),
            if (i != rows.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: cs.outlineVariant),
              ),
          ]
        ],
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.onRenew, required this.renewLabel});
  final VoidCallback onRenew;
  final String renewLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onRenew,
              icon: const Icon(Icons.autorenew_rounded),
              label: Text(renewLabel),
            ),
          ),
        ],
      ),
    );
  }
}
