import 'package:flutter/material.dart';

extension AppThemeExtension on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get scaffoldBg => isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get surfaceCard => isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get inputBg => isDarkMode ? const Color(0xFF334155) : const Color(0xFFF8FAFC);
  Color get textPrimary => isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
  Color get textSecondary => isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get border => isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get headerBg => isDarkMode ? const Color(0xFF020617) : const Color(0xFF003366);
}
