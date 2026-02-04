import 'package:flutter/material.dart';

import 'package:flutter_riverpod/legacy.dart';

import '../../core/storage/local_store.dart';

/// Theme (System/Light/Dark)
final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  final store = ref.watch(localStoreProvider);
  return ThemeModeController(store);
});

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._store) : super(_store.getThemeMode());
  final LocalStore _store;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _store.setThemeMode(mode);
  }
}

/// Locale override (null = follow device)
final localeOverrideProvider =
    StateNotifierProvider<LocaleOverrideController, Locale?>((ref) {
  final store = ref.watch(localStoreProvider);
  return LocaleOverrideController(store);
});

class LocaleOverrideController extends StateNotifier<Locale?> {
  LocaleOverrideController(this._store) : super(_store.getLocaleOverride());
  final LocalStore _store;

  Future<void> setLocaleOverride(Locale? locale) async {
    state = locale;
    await _store.setLocaleOverride(locale);
  }
}
