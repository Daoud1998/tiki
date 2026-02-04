import 'package:flutter/widgets.dart';

/// Lightweight localizer used only by Notifications feature.
/// Usage:
///   tr(context, ar: '...', fr: '...', en: '...')
String tr(
  BuildContext context, {
  required String ar,
  required String fr,
  required String en,
}) {
  final code = Localizations.localeOf(context).languageCode.toLowerCase();
  if (code.startsWith('ar')) return ar;
  if (code.startsWith('fr')) return fr;
  return en;
}

/// Small value object to store 3-language text.
class LocalizedText {
  final String ar;
  final String fr;
  final String en;

  const LocalizedText({
    required this.ar,
    required this.fr,
    required this.en,
  });

  String pick(BuildContext context) => tr(context, ar: ar, fr: fr, en: en);
}
