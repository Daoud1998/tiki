import 'package:flutter/material.dart';

void showQuickSnack(
  BuildContext context,
  String msg, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final m = ScaffoldMessenger.of(context);

  // امسح أي رسائل قديمة (أقوى من hideCurrentSnackBar)
  m.clearSnackBars();

  final controller = m.showSnackBar(
    SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
      margin:
          const EdgeInsets.fromLTRB(12, 0, 12, kBottomNavigationBarHeight + 12),
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ),
  );

  // ✅ إغلاق إجباري بعد ثانية (حل “الثبات” نهائيًا)
  Future.delayed(const Duration(seconds: 1), () {
    controller.close();
  });
}
