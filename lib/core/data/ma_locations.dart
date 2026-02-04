import 'package:flutter/widgets.dart';

import 'ma_catalog.dart';

String _maNorm2(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');

const L10n3 _nouakchottUmbrella =
    L10n3(ar: 'نواكشوط', fr: 'Nouakchott', en: 'Nouakchott');

bool _isNouakchottAny(String raw) {
  final n = _maNorm2(raw);
  // Minimal but practical: covers most stored variants.
  return n == _maNorm2('نواكشوط') ||
      n == _maNorm2('nouakchott') ||
      n == _maNorm2('nouakchott-nord') ||
      n == _maNorm2('nouakchott-ouest') ||
      n == _maNorm2('nouakchott-sud') ||
      n == _maNorm2('nouakchott_nord') ||
      n == _maNorm2('nouakchott_ouest') ||
      n == _maNorm2('nouakchott_sud') ||
      n == _maNorm2('نواكشوط الشمالية') ||
      n == _maNorm2('نواكشوط الغربية') ||
      n == _maNorm2('نواكشوط الجنوبية');
}

/// Smarter wilaya label resolver:
/// - Accepts id OR any localized label.
/// - Handles older stored values like 'نواكشوط' (umbrella) or a city name.
/// - Returns label in the current locale; falls back to [raw] if not found.
String resolveWilayaLabelSmart(BuildContext context, String raw) {
  final v = raw.trim();
  if (v.isEmpty) return v;

  if (_isNouakchottAny(v)) return _nouakchottUmbrella.of(context);

  final n = _maNorm2(v);

  // 1) Try exact wilaya match (id OR localized label)
  for (final w in maWilayas) {
    if (n == _maNorm2(w.id) ||
        n == _maNorm2(w.name.ar) ||
        n == _maNorm2(w.name.fr) ||
        n == _maNorm2(w.name.en)) {
      // Treat the 3 Nouakchott sub-wilayas as a single umbrella label.
      if (w.id.startsWith('nouakchott_'))
        return _nouakchottUmbrella.of(context);
      return w.name.of(context);
    }
  }

  // 2) Old mock items sometimes stored a city/moughataa label in the wilaya field.
  // If [raw] matches a moughataa anywhere, show its parent wilaya label.
  for (final w in maWilayas) {
    for (final m in w.moughataas) {
      if (n == _maNorm2(m.id) ||
          n == _maNorm2(m.name.ar) ||
          n == _maNorm2(m.name.fr) ||
          n == _maNorm2(m.name.en)) {
        if (w.id.startsWith('nouakchott_'))
          return _nouakchottUmbrella.of(context);
        return w.name.of(context);
      }
    }
  }

  return v;
}

Iterable<Wilaya> _scopeWilayasFor(String? wilayaRaw) {
  final v = (wilayaRaw ?? '').trim();
  if (v.isEmpty) return maWilayas;

  if (_isNouakchottAny(v)) {
    return maWilayas.where((w) => w.id.startsWith('nouakchott_'));
  }

  final n = _maNorm2(v);

  // Try to match a wilaya.
  for (final w in maWilayas) {
    if (n == _maNorm2(w.id) ||
        n == _maNorm2(w.name.ar) ||
        n == _maNorm2(w.name.fr) ||
        n == _maNorm2(w.name.en)) {
      return <Wilaya>[w];
    }
  }

  // Try to match a moughataa and use its parent wilaya.
  for (final w in maWilayas) {
    for (final m in w.moughataas) {
      if (n == _maNorm2(m.id) ||
          n == _maNorm2(m.name.ar) ||
          n == _maNorm2(m.name.fr) ||
          n == _maNorm2(m.name.en)) {
        return <Wilaya>[w];
      }
    }
  }

  return maWilayas;
}

/// Smarter moughataa label resolver (id OR localized label).
/// Optionally pass [wilayaRaw] (id/label) to narrow the search.
String resolveMoughataaLabelSmart(BuildContext context, String raw,
    {String? wilayaRaw}) {
  final v = raw.trim();
  if (v.isEmpty) return v;

  final n = _maNorm2(v);
  final scope = _scopeWilayasFor(wilayaRaw);

  for (final w in scope) {
    for (final m in w.moughataas) {
      if (n == _maNorm2(m.id) ||
          n == _maNorm2(m.name.ar) ||
          n == _maNorm2(m.name.fr) ||
          n == _maNorm2(m.name.en)) {
        return m.name.of(context);
      }
    }
  }

  // Fallback: search globally
  for (final w in maWilayas) {
    for (final m in w.moughataas) {
      if (n == _maNorm2(m.id) ||
          n == _maNorm2(m.name.ar) ||
          n == _maNorm2(m.name.fr) ||
          n == _maNorm2(m.name.en)) {
        return m.name.of(context);
      }
    }
  }

  return v;
}

/// Format a product location label that remains correct after language switching.
///
/// Uses ids when available in [attrs] (recommended keys: 'wilaya_id', 'moughataa_id').
/// Falls back to the stored string fields otherwise.
String formatMaLocationSmart(
  BuildContext context, {
  required String wilayaRaw,
  required String moughataaRaw,
  Map<String, String>? attrs,
  String separator = ' · ',
}) {
  final wid = (attrs?['wilaya_id'] ?? '').trim();
  final mid = (attrs?['moughataa_id'] ?? '').trim();

  final wLabel =
      resolveWilayaLabelSmart(context, wid.isNotEmpty ? wid : wilayaRaw);
  final mLabel = resolveMoughataaLabelSmart(
    context,
    mid.isNotEmpty ? mid : moughataaRaw,
    wilayaRaw: wid.isNotEmpty ? wid : wilayaRaw,
  );

  final w = wLabel.trim();
  final m = mLabel.trim();
  if (w.isEmpty) return m;
  if (m.isEmpty) return w;
  return '$w$separator$m';
}
