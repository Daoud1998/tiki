import 'package:flutter/material.dart';

/// Direction-aware chevrons that also work on older Flutter versions
/// (no reliance on Icon.matchTextDirection).
///
/// NOTE: Some projects accidentally end up with a wrong Directionality in a few
/// places. To make RTL reliable, we also treat Arabic locale as RTL.
class DirChevrons {
  static const Set<String> _rtlLangs = <String>{
    'ar', // Arabic
    'fa', // Persian
    'ur', // Urdu
    'he', // Hebrew
  };

  static bool _isRtl(BuildContext context) {
    final dir = Directionality.maybeOf(context);
    if (dir == TextDirection.rtl) return true;
    try {
      final code = Localizations.localeOf(context).languageCode.toLowerCase();
      return _rtlLangs.contains(code);
    } catch (_) {
      return false;
    }
  }

  /// Forward (navigate into a page).
  /// LTR: >  RTL: <
  static Widget forward(
    BuildContext context, {
    Color? color,
    double? size,
  }) {
    return _mirrorIfRtl(
      context,
      Icon(Icons.chevron_right_rounded, color: color, size: size),
    );
  }

  /// Back (navigate to previous page).
  /// LTR: <  RTL: >
  static Widget back(
    BuildContext context, {
    Color? color,
    double? size,
  }) {
    return _mirrorIfRtl(
      context,
      Icon(Icons.chevron_left_rounded, color: color, size: size),
    );
  }

  /// iOS-style back arrow.
  /// LTR: <-  RTL: ->
  static Widget backIos(
    BuildContext context, {
    Color? color,
    double? size,
  }) {
    // arrow_back_ios_new points left by default.
    return _mirrorIfRtl(
      context,
      Icon(Icons.arrow_back_ios_new_rounded, color: color, size: size),
    );
  }

  static Widget _mirrorIfRtl(BuildContext context, Widget child) {
    if (!_isRtl(context)) return child;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
      child: child,
    );
  }
}
