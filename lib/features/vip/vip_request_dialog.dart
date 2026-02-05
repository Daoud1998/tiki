import 'package:flutter/material.dart';

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
      title: const Text('طلب ترويج VIP'),
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
            decoration: const InputDecoration(
              labelText: 'الخطة',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'vip_7d', child: Text('VIP لمدة 7 أيام')),
              DropdownMenuItem(
                  value: 'vip_30d', child: Text('VIP لمدة 30 يوم')),
            ],
            onChanged: (v) => plan = v ?? 'vip_7d',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: rank,
            decoration: const InputDecoration(
              labelText: 'المرتبة (Rank)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Rank 1 (عادي)')),
              DropdownMenuItem(value: 2, child: Text('Rank 2 (أقوى)')),
              DropdownMenuItem(value: 3, child: Text('Rank 3 (الأعلى)')),
            ],
            onChanged: (v) => rank = v ?? 1,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'ملاحظة (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('إرسال الطلب'),
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
        const SnackBar(content: Text('تم إرسال طلب VIP وسيتم مراجعته قريبًا')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إرسال الطلب: $e')),
      );
    }
  }
}
