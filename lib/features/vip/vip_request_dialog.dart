import 'package:flutter/material.dart';

import '../../core/i18n/tikki_tr.dart';

import 'vip_request_service.dart';

/// Dialog to request VIP for a product.
Future<void> showProductVipRequestDialog({
  required BuildContext context,
  required String productId,
  String? productTitle,
}) async {
  final noteCtl = TextEditingController();
  String plan = 'vip_7d';
  int rank = 1;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tikkiTr(ctx, ar: 'طلب ترويج VIP', fr: 'Demande VIP', en: 'VIP request')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((productTitle ?? '').trim().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                productTitle!.trim(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: plan,
            decoration: InputDecoration(
              labelText: tikkiTr(ctx, ar: 'الخطة', fr: 'Forfait', en: 'Plan'),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(value: 'vip_7d', child: Text(tikkiTr(ctx, ar: 'VIP لمدة 7 أيام', fr: 'VIP 7 jours', en: 'VIP 7 days'))),
              DropdownMenuItem(
                  value: 'vip_30d', child: Text(tikkiTr(ctx, ar: 'VIP لمدة 30 يوم', fr: 'VIP 30 jours', en: 'VIP 30 days'))),
            ],
            onChanged: (v) => plan = v ?? 'vip_7d',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: rank,
            decoration: InputDecoration(
              labelText: tikkiTr(ctx, ar: 'المرتبة (Rank)', fr: 'Rang (Rank)', en: 'Rank'),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(value: 1, child: Text(tikkiTr(ctx, ar: 'Rank 1 (عادي)', fr: 'Rank 1 (normal)', en: 'Rank 1 (normal)'))),
              DropdownMenuItem(value: 2, child: Text(tikkiTr(ctx, ar: 'Rank 2 (أقوى)', fr: 'Rank 2 (fort)', en: 'Rank 2 (strong)'))),
              DropdownMenuItem(value: 3, child: Text(tikkiTr(ctx, ar: 'Rank 3 (الأعلى)', fr: 'Rank 3 (max)', en: 'Rank 3 (top)'))),
            ],
            onChanged: (v) => rank = v ?? 1,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: tikkiTr(ctx, ar: 'ملاحظة (اختياري)', fr: 'Note (optionnel)', en: 'Note (optional)'),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tikkiTr(ctx, ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tikkiTr(ctx, ar: 'إرسال الطلب', fr: 'Envoyer', en: 'Send request')),
        ),
      ],
    ),
  );

  if (ok != true) return;

  try {
    final days = plan == 'vip_30d' ? 30 : 7;
    await VipRequestService().requestProductVip(
      productId: productId,
      planId: plan,
      days: days,
      rank: rank,
      note: noteCtl.text,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tikkiTr(context, ar: 'تم إرسال طلب VIP وسيتم مراجعته قريبًا', fr: 'Votre demande VIP a été envoyée.', en: 'VIP request sent.'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tikkiTr(context, ar: 'تعذر إرسال الطلب: $e', fr: 'Envoi échoué: $e', en: 'Request failed: $e'))),
      );
    }
  }
}
