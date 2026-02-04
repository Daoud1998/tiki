import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local (device-only) analytics for "Hot Searches".
/// No Firebase required.
///
/// Storage key per language:
///   tikki_hot_terms_<langCode>
/// Value:
///   JSON map { "term": count }
class SearchAnalyticsService {
  const SearchAnalyticsService();

  static final Map<String, StreamController<List<String>>> _controllers = {};

  String _lang(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'ar' || code == 'fr' || code == 'en') return code;
    return 'en';
  }

  String _key(String lang) => 'tikki_hot_terms_$lang';

  String _normalize(String input) {
    final s = input.trim();
    if (s.isEmpty) return '';
    // Keep it simple & safe: lowercase + collapse spaces.
    return s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Stream<List<String>> watchHotTerms({
    required BuildContext context,
    int limit = 10,
  }) {
    final lang = _lang(context);
    final c = _controllers.putIfAbsent(lang, () {
      final sc = StreamController<List<String>>.broadcast();
      // Emit initial snapshot
      _loadHot(lang, limit).then(sc.add);
      return sc;
    });

    // Refresh on each subscription too (so UI updates after restart)
    _loadHot(lang, limit).then((v) {
      if (!c.isClosed) c.add(v);
    });

    return c.stream;
  }

  Future<void> recordTerm(BuildContext context, String term) {
    return trackSearch(context: context, term: term);
  }

  Future<void> trackSearch({
    required BuildContext context,
    required String term,
  }) async {
    final lang = _lang(context);
    final norm = _normalize(term);
    if (norm.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(lang));
    final Map<String, dynamic> m =
        raw == null ? {} : (jsonDecode(raw) as Map<String, dynamic>);

    final current =
        (m[norm] is int) ? m[norm] as int : int.tryParse('${m[norm]}') ?? 0;
    m[norm] = current + 1;

    await prefs.setString(_key(lang), jsonEncode(m));

    // Push update to listeners
    final c = _controllers[lang];
    if (c != null && !c.isClosed) {
      c.add(_topTermsFromMap(m, limit: 10));
    }
  }

  Future<List<String>> _loadHot(String lang, int limit) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(lang));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final Map<String, dynamic> m = jsonDecode(raw) as Map<String, dynamic>;
      return _topTermsFromMap(m, limit: limit);
    } catch (_) {
      return const [];
    }
  }

  List<String> _topTermsFromMap(Map<String, dynamic> m, {required int limit}) {
    final entries = <MapEntry<String, int>>[];
    for (final e in m.entries) {
      final v =
          (e.value is int) ? e.value as int : int.tryParse('${e.value}') ?? 0;
      if (v > 0) entries.add(MapEntry(e.key, v));
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList(growable: false);
  }
}
