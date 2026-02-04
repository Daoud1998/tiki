import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/service_receipt.dart';

class ReceiptPdfService {
  static Future<Uint8List> buildPdf(
    ServiceReceipt r, {
    required String localeCode,
  }) async {
    final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final arRegular =
        await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf');
    final arBold =
        await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf');

    final baseFont = pw.Font.ttf(regular);
    final boldFont = pw.Font.ttf(bold);

    final arBase = pw.Font.ttf(arRegular);
    final arBoldFont = pw.Font.ttf(arBold);

    final theme = pw.ThemeData.withFont(
      base: baseFont,
      bold: boldFont,
      fontFallback: [arBase],
    );

    String tr({required String ar, required String fr, required String en}) {
      if (localeCode == 'fr') return fr;
      if (localeCode == 'en') return en;
      return ar;
    }

    String? subjTitle() {
      if (localeCode == 'fr') {
        return r.subjectTitleFr ?? r.subjectTitleAr ?? r.subjectTitleEn;
      }
      if (localeCode == 'en') {
        return r.subjectTitleEn ?? r.subjectTitleAr ?? r.subjectTitleFr;
      }
      return r.subjectTitleAr ?? r.subjectTitleEn ?? r.subjectTitleFr;
    }

    String kindLabel() {
      switch (r.kind) {
        case ServiceReceiptKind.productVip:
          return tr(ar: 'VIP للمنتج', fr: 'VIP produit', en: 'Product VIP');
        case ServiceReceiptKind.promoAdVip:
          return tr(ar: 'VIP للإعلان', fr: 'VIP pub', en: 'Ad VIP');
        case ServiceReceiptKind.productActivation:
          return tr(ar: 'تفعيل المنتج', fr: 'Activation', en: 'Activation');
      }
    }

    String statusLabel() {
      switch (r.status) {
        case ServiceReceiptStatus.pending:
          return tr(ar: 'قيد المراجعة', fr: 'En attente', en: 'Pending');
        case ServiceReceiptStatus.active:
          return tr(ar: 'نشط', fr: 'Actif', en: 'Active');
        case ServiceReceiptStatus.expired:
          return tr(ar: 'منتهي', fr: 'Expiré', en: 'Expired');
        case ServiceReceiptStatus.cancelled:
          return tr(ar: 'ملغي', fr: 'Annulé', en: 'Cancelled');
        case ServiceReceiptStatus.failed:
          return tr(ar: 'فشل', fr: 'Échec', en: 'Failed');
      }
    }

    String fmt(DateTime? dt) {
      if (dt == null) return '-';
      final d = dt.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
    }

    List<String> pricingLines() {
      final m = r.meta;
      if (m.isEmpty) return const <String>[];
      final model = '${m['pricingModel'] ?? ''}'.trim();
      if (model.isEmpty) return const <String>[];

      String line(String k, String v) => '$k: $v';

      final out = <String>[];
      out.add(line(tr(ar: 'نموذج التسعير', fr: 'Modèle', en: 'Model'), model));

      final tier = '${m['tier'] ?? ''}'.trim();
      if (tier.isNotEmpty)
        out.add(line(tr(ar: 'الفئة', fr: 'Niveau', en: 'Tier'), tier));

      final days = '${m['days'] ?? ''}'.trim();
      if (days.isNotEmpty)
        out.add(line(tr(ar: 'المدة', fr: 'Durée', en: 'Days'), days));

      final pct = m['percent'];
      if (pct is num) {
        out.add(line(tr(ar: 'النسبة', fr: 'Pourcentage', en: 'Percent'),
            '${(pct * 100).toStringAsFixed(1)}%'));
      }

      final mult = m['durationMultiplier'];
      if (mult is num) {
        out.add(line(
            tr(ar: 'معامل المدة', fr: 'Facteur durée', en: 'Duration factor'),
            '${mult.toStringAsFixed(2)}'));
      }

      final usedPrice = m['usedPriceMru'];
      if (usedPrice is num) {
        out.add(line(
            tr(ar: 'سعر المنتج المستخدم', fr: 'Prix utilisé', en: 'Used price'),
            '${usedPrice.toInt()} MRU'));
      }

      if (m['usedFallbackPrice'] == true) {
        out.add(tr(
            ar: 'تم استخدام سعر مرجعي',
            fr: 'Prix de référence utilisé',
            en: 'Fallback used'));
      }

      return out;
    }

    final doc = pw.Document(theme: theme);

    final title = subjTitle() ?? kindLabel();

    final isAr = localeCode != 'fr' && localeCode != 'en';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) {
          final t = pw.TextStyle(fontSize: 12);
          final h = pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold);

          pw.Widget cardRow(String k, String v) {
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 4,
                    child: pw.Text(
                      k,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        font: isAr ? arBoldFont : null,
                      ),
                      textDirection:
                          isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    flex: 7,
                    child: pw.Text(
                      v,
                      style: pw.TextStyle(font: isAr ? arBase : null),
                      textDirection:
                          isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                    ),
                  ),
                ],
              ),
            );
          }

          return pw.Directionality(
            textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Tikki', style: h),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            tr(
                              ar: 'فاتورة خدمة',
                              fr: 'Facture de service',
                              en: 'Service receipt',
                            ),
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              font: isAr ? arBoldFont : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400),
                        borderRadius: pw.BorderRadius.circular(999),
                      ),
                      child: pw.Text(
                        statusLabel(),
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          font: isAr ? arBoldFont : null,
                        ),
                      ),
                    )
                  ],
                ),
                pw.SizedBox(height: 18),
                pw.Text(title,
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      font: isAr ? arBoldFont : null,
                    )),
                pw.SizedBox(height: 6),
                pw.Text(kindLabel(), style: t),
                pw.SizedBox(height: 16),
                pw.Container(
                  padding: const pw.EdgeInsets.all(14),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(14),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      cardRow(
                        tr(
                            ar: 'رقم الفاتورة',
                            fr: 'N° facture',
                            en: 'Receipt #'),
                        r.id,
                      ),
                      cardRow(
                        tr(ar: 'تاريخ الإنشاء', fr: 'Créée le', en: 'Created'),
                        fmt(r.createdAt),
                      ),
                      cardRow(
                        tr(ar: 'المبلغ', fr: 'Montant', en: 'Amount'),
                        '${r.amountMru} MRU',
                      ),
                      cardRow(
                        tr(ar: 'رقم العملية', fr: 'Transaction', en: 'TX id'),
                        (r.transactionId ?? '-'),
                      ),
                      cardRow(
                        tr(ar: 'بداية الخدمة', fr: 'Début', en: 'Starts'),
                        fmt(r.startsAt),
                      ),
                      cardRow(
                        tr(ar: 'نهاية الخدمة', fr: 'Fin', en: 'Ends'),
                        fmt(r.endsAt),
                      ),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Text(
                  tr(
                    ar: 'ملاحظة: هذه فاتورة مرجعية داخل التطبيق (وضع تجريبي).',
                    fr: 'Note : facture de référence dans l\'app (mode démo).',
                    en: 'Note: Reference receipt inside the app (demo mode).',
                  ),
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                    font: isAr ? arBase : null,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  static Future<void> sharePdf(ServiceReceipt r,
      {required String localeCode}) async {
    final bytes = await buildPdf(r, localeCode: localeCode);
    await Printing.sharePdf(bytes: bytes, filename: 'Tikki_${r.id}.pdf');
  }

  static Future<void> printPdf(ServiceReceipt r,
      {required String localeCode}) async {
    await Printing.layoutPdf(
      onLayout: (_) => buildPdf(r, localeCode: localeCode),
    );
  }
}
