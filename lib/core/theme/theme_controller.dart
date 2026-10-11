import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global controller managing light/dark theme state with persistent preference storage.
class ThemeController extends ValueNotifier<ThemeMode> {
  static final ThemeController instance = ThemeController._();

  ThemeController._() : super(ThemeMode.light) {
    _loadThemeMode();
  }

  static const String _prefKey = 'flexpos_theme_mode';

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeIndex = prefs.getInt(_prefKey);
      if (modeIndex != null && modeIndex < ThemeMode.values.length) {
        value = ThemeMode.values[modeIndex];
      }
    } catch (e) {
      debugPrint('Error loading theme mode: $e');
    }
  }

  Future<void> toggleTheme() async {
    final nextMode = value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    value = nextMode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKey, nextMode.index);
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }

  bool get isDarkMode => value == ThemeMode.dark;
}
