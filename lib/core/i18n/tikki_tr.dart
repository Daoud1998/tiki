import 'package:flutter/widgets.dart';

/// Lightweight inline translation helper (AR/FR/EN).
///
/// Use this for screen-specific text where you don't want to create a key yet.
/// For shared, reusable strings across the app, prefer [AppStrings] in
/// `lib/app/localization/l10n.dart`.
String tikkiTr(
  BuildContext context, {
  required String ar,
  required String fr,
  required String en,
}) {
  final code = Localizations.localeOf(context).languageCode.toLowerCase();
  if (code == 'fr') return fr;
  if (code == 'en') return en;
  return ar;
}
