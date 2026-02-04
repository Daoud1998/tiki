import 'ma_search_dictionary.dart';

/// Build normalized query tokens from free text.
///
/// For search input (what the user typed):
/// - Keeps tokens strict (no heavy synonym expansion).
/// - Adds useful join variants like s 24 -> s24, iphone 13 -> iphone13.
List<String> maQueryTokens(String query, {int maxTokens = 12}) {
  final out = <String>{};
  final tokens = _tokenizeBasic(query);

  for (final t in tokens) {
    if (t.isEmpty) continue;
    out.add(t);
    if (out.length >= maxTokens) {
      return out.take(maxTokens).toList(growable: false);
    }
  }

  _addJoinCombos(tokens, out, maxAdds: 24, maxTokens: maxTokens);

  return out.take(maxTokens).toList(growable: false);
}

/// Build search tokens for a listing (product/ad).
///
/// Intended usage:
/// - Compute once at publish time and store on the document (Firestore array).
/// - In mock mode it is stored on [MockProduct.searchTokens].
List<String> maBuildSearchTokens({
  required List<String> fields,
  int maxTokens = 80,
}) {
  final out = <String>{};
  final pieces = <String>[];

  for (final f in fields) {
    final s = f.trim();
    if (s.isEmpty) continue;
    pieces.add(s);

    final tokens = _tokenizeBasic(s);
    for (final t in tokens) {
      if (t.isEmpty) continue;
      out.add(t);
      _addPrefixes(t, out, maxAdds: 8, maxTokens: maxTokens);
      if (out.length >= maxTokens) {
        return out.take(maxTokens).toList(growable: false);
      }
    }

    _addJoinCombos(tokens, out, maxAdds: 18, maxTokens: maxTokens);

    if (out.length >= maxTokens) {
      return out.take(maxTokens).toList(growable: false);
    }
  }

  final blob = pieces.join(' ');
  _expandFromDictionary(blob, out, maxTokens: maxTokens);

  return out.take(maxTokens).toList(growable: false);
}

List<String> _tokenizeBasic(String text) {
  final n = maNormalizeQuery(text);
  if (n.isEmpty) return const <String>[];
  final parts = n.split(' ');
  final out = <String>[];
  for (final p in parts) {
    final t = p.trim();
    if (t.isEmpty) continue;
    out.add(t);
  }
  return out;
}

/// Add short prefixes for "type-ahead" search.
///
/// Example: "sportage" -> sp, spo, spor...
///          "سبورتاج" -> سب, سبو, سبور...
void _addPrefixes(
  String token,
  Set<String> out, {
  required int maxAdds,
  required int maxTokens,
  int minPrefix = 2,
  int maxPrefix = 12,
}) {
  if (out.length >= maxTokens) return;
  final t = token.trim();
  if (t.length < (minPrefix + 1)) return;

  var adds = 0;
  final upTo = t.length < maxPrefix ? t.length : maxPrefix;
  for (var i = minPrefix; i <= upTo; i++) {
    if (adds >= maxAdds) return;
    if (out.length >= maxTokens) return;
    if (out.add(t.substring(0, i))) adds++;
  }
}

void _addJoinCombos(
  List<String> tokens,
  Set<String> out, {
  required int maxAdds,
  required int maxTokens,
}) {
  var adds = 0;
  if (tokens.length < 2) return;

  for (var i = 0; i < tokens.length - 1; i++) {
    if (adds >= maxAdds) return;
    if (out.length >= maxTokens) return;

    final a = tokens[i];
    final b = tokens[i + 1];
    if (a.isEmpty || b.isEmpty) continue;

    // Join letter-ish prefix + digits: iphone + 13 => iphone13, s + 24 => s24, a + 32 => a32
    if (_hasLetter(a) && _isDigits(b) && a.length <= 10 && b.length <= 4) {
      final j = a + b;
      if (out.add(j)) {
        adds++;
      }
      if (adds >= maxAdds || out.length >= maxTokens) return;

      // Join again with a following word: s24 + ultra => s24ultra, iphone13 + pro => iphone13pro
      if (i + 2 < tokens.length) {
        final c = tokens[i + 2];
        if (c.isNotEmpty && _hasLetter(c) && c.length <= 12) {
          final j2 = j + c;
          if (out.add(j2)) {
            adds++;
          }
        }
      }

      if (adds >= maxAdds || out.length >= maxTokens) return;
    }

    // Join digits + word: 13 + pro => 13pro
    if (_isDigits(a) && _hasLetter(b) && a.length <= 4 && b.length <= 12) {
      final j = a + b;
      if (out.add(j)) {
        adds++;
      }
      if (adds >= maxAdds || out.length >= maxTokens) return;
    }
  }
}

void _expandFromDictionary(
  String blob,
  Set<String> out, {
  required int maxTokens,
}) {
  final nb = maNormalizeQuery(blob);
  if (nb.isEmpty) return;

  for (final e in maSearchDictionary) {
    if (out.length >= maxTokens) return;

    var matched = false;
    for (final term in _termsOfEntry(e)) {
      final nt = maNormalizeQuery(term);
      if (nt.isEmpty) continue;
      if (nb.contains(nt)) {
        matched = true;
        break;
      }
    }

    if (!matched) continue;

    // Add terms + aliases tokens.
    for (final term in _termsOfEntry(e)) {
      if (out.length >= maxTokens) return;
      final toks = _tokenizeBasic(term);
      for (final t in toks) {
        if (t.isEmpty) continue;
        out.add(t);
        _addPrefixes(t, out, maxAdds: 6, maxTokens: maxTokens);
        if (out.length >= maxTokens) return;
      }

      _addJoinCombos(toks, out, maxAdds: 10, maxTokens: maxTokens);
      if (out.length >= maxTokens) return;
    }

    // Add tags (category hints).
    for (final tag in e.tags) {
      final nt = maNormalizeQuery(tag);
      if (nt.isEmpty) continue;
      out.add(nt);
      _addPrefixes(nt, out, maxAdds: 4, maxTokens: maxTokens);
      if (out.length >= maxTokens) return;
    }
  }
}

Iterable<String> _termsOfEntry(MaSearchEntry e) sync* {
  yield e.ar;
  yield e.fr;
  yield e.en;
  for (final a in e.aliases) {
    yield a;
  }
}

bool _isDigits(String s) {
  if (s.isEmpty) return false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 48 || c > 57) return false;
  }
  return true;
}

bool _hasLetter(String s) {
  return RegExp(r'[\p{L}]', unicode: true).hasMatch(s);
}
