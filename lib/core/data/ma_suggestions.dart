import 'package:flutter/widgets.dart';

import 'ma_catalog.dart';

/// Lightweight suggestion item for pickers (model, neighborhood, ...).
///
/// - [label] is localized (AR/FR/EN)
/// - [aliases] helps matching common spellings (Arabic/French/English)
@immutable
class MaSuggestion {
  const MaSuggestion({
    required this.id,
    required this.label,
    this.aliases = const <String>[],
  });

  /// Stable id (not shown to user).
  final String id;

  /// UI label.
  final L10n3 label;

  /// Search helpers (e.g. transliterations, common misspellings).
  final List<String> aliases;

  String display(BuildContext context) => label.of(context);

  bool matches(String query) {
    final q = MaSuggestionNorm.norm(query);
    if (q.isEmpty) return true;

    final hay = <String>{
      MaSuggestionNorm.norm(label.ar),
      MaSuggestionNorm.norm(label.fr),
      MaSuggestionNorm.norm(label.en),
      for (final a in aliases) MaSuggestionNorm.norm(a),
    };

    for (final h in hay) {
      if (h.contains(q)) return true;
    }
    return false;
  }
}

/// Small normalization helper used by suggestion pickers.
class MaSuggestionNorm {
  static String norm(String input) {
    var s = (input).toLowerCase().trim();
    if (s.isEmpty) return '';

    // Collapse whitespace and remove most punctuation.
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '');
    s = s.replaceAll(RegExp(r"[^0-9a-z\u0600-\u06FF ]"), '');
    s = s.replaceAll(' ', '');

    return s;
  }
}
