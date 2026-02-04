import 'package:flutter/material.dart';

class AppTheme {
  /// Temu primary orange (brand).
  /// Public brand assets commonly list: #FB7701.
  /// Used for bottom nav selected color, CTAs, highlights, etc.
  static const Color brandOrange = Color(0xFFFB7701);

  /// A slightly darker tone for pressed states (optional).
  static const Color brandOrangeDark = Color(0xFFE56B00);

  /// Backwards-compatible alias (older code may still reference `temuRed`).
  // ignore: constant_identifier_names
  static const Color temuRed = brandOrange;

  /// Use Arabic font when the current locale is Arabic.
  /// Fonts are already included in assets: NotoSans / NotoSansArabic.
  static ThemeData light({required bool isArabic}) {
    final cs = ColorScheme.fromSeed(
      seedColor: brandOrange,
      brightness: Brightness.light,
    ).copyWith(
      primary: brandOrange,
      secondary: brandOrange,
      tertiary: brandOrange,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: cs,
      fontFamily: isArabic ? 'NotoSansArabic' : 'NotoSans',
    );

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF7F7FA),

      // AppBar consistency across pages
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: const Color(0xFFF7F7FA),
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: cs.onSurface,
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        color: cs.surface,
      ),

      dividerTheme: DividerThemeData(
        thickness: 1,
        space: 1,
        color: cs.outlineVariant.withValues(alpha: 0.45),
      ),

      // Temu-like bottom bar: white background, no pill indicator,
      // selected = red, unselected = near-black.
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: Colors.white,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? temuRed : Colors.black87,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return (base.textTheme.labelSmall ?? const TextStyle(fontSize: 11))
              .copyWith(
            fontWeight: FontWeight.w900,
            color: selected ? temuRed : Colors.black87,
          );
        }),
      ),

      // In case some screens still use BottomNavigationBar.
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: temuRed,
        unselectedItemColor: Colors.black87,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w900),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w800),
        type: BottomNavigationBarType.fixed,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.onSurface.withValues(alpha: 0.92),
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: cs.surface,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: temuRed,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: temuRed,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: temuRed,
        foregroundColor: Colors.white,
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  static ThemeData dark({required bool isArabic}) {
    final cs = ColorScheme.fromSeed(
      seedColor: brandOrange,
      brightness: Brightness.dark,
    ).copyWith(
      primary: brandOrange,
      secondary: brandOrange,
      tertiary: brandOrange,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      fontFamily: isArabic ? 'NotoSansArabic' : 'NotoSans',
    );

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F1115),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: const Color(0xFF0F1115),
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: cs.onSurface,
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        color: cs.surface,
      ),
      dividerTheme: DividerThemeData(
        thickness: 1,
        space: 1,
        color: cs.outlineVariant.withValues(alpha: 0.45),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: const Color(0xFF0F1115),
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? temuRed
                : cs.onSurfaceVariant.withValues(alpha: 0.80),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return (base.textTheme.labelSmall ?? const TextStyle(fontSize: 11))
              .copyWith(
            fontWeight: FontWeight.w900,
            color: selected
                ? temuRed
                : cs.onSurfaceVariant.withValues(alpha: 0.80),
          );
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFF0F1115),
        selectedItemColor: temuRed,
        unselectedItemColor: cs.onSurfaceVariant.withValues(alpha: 0.80),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
        type: BottomNavigationBarType.fixed,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.onSurface.withValues(alpha: 0.92),
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: cs.surface,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: temuRed,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: temuRed,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: temuRed,
        foregroundColor: Colors.white,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
