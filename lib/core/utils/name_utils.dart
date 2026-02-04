import 'package:flutter/foundation.dart';

/// Small helper for UI: turn "Mohamed Ahmed" into "Mohamed".
/// Safe for empty/whitespace.
@immutable
class NameUtils {
  const NameUtils._();

  static String firstName(String? fullName, {String fallback = ''}) {
    final s = (fullName ?? '').trim();
    if (s.isEmpty) return fallback;
    final parts = s.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty);
    return parts.isEmpty ? fallback : parts.first;
  }
}
