import 'package:flutter/material.dart';

/// Short "time ago" label (Temu/Voursa style).
///
/// - Arabic: الآن, 5 دقائق, 2 ساعة, 3 أيام, 1 أسبوع
/// - French: à l’instant, 5min, 2h, 3j, 1sem
/// - English: just now, 5m, 2h, 3d, 1w
String timeAgoShort(BuildContext context, DateTime dt) {
  final code = Localizations.localeOf(context).languageCode.toLowerCase();
  final d = DateTime.now().difference(dt);

  if (d.inMinutes < 1) {
    return code == 'fr'
        ? 'à l’instant'
        : code == 'en'
            ? 'just now'
            : 'الآن';
  }

  String unit(int n, String ar1, String ar2, String fr, String en) {
    if (code == 'fr') return '$n$fr';
    if (code == 'en') return '$n$en';
    return n == 1 ? '$n $ar1' : '$n $ar2';
  }

  if (d.inHours < 1) return unit(d.inMinutes, 'دقيقة', 'دقائق', 'min', 'm');
  if (d.inDays < 1) return unit(d.inHours, 'ساعة', 'ساعات', 'h', 'h');
  if (d.inDays < 7) return unit(d.inDays, 'يوم', 'أيام', 'j', 'd');

  final w = (d.inDays / 7).floor().clamp(1, 999);
  return unit(w, 'أسبوع', 'أسابيع', 'sem', 'w');
}
