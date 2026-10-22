import 'package:flutter/material.dart';

import 'storage_service.dart';

/// 앱 전역 라이트/다크 모드. 기본값은 라이트.
class ThemeModeService extends ChangeNotifier {
  ThemeModeService._();
  static final ThemeModeService instance = ThemeModeService._();

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  void load() {
    final raw = StorageService.instance.themeModeName;
    _mode = switch (raw) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await StorageService.instance.setThemeModeName(mode.name);
    notifyListeners();
  }

  Future<void> toggleLightDark() async {
    await setMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}
