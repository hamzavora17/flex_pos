import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Global controller managing the application logo path or network URL
/// with persistent local preference storage and live database sync.
class AppLogoController extends ValueNotifier<String> {
  static final AppLogoController instance = AppLogoController._();

  static const String defaultLogoPath = 'assets/FlexPOS_logo_upscaled.png';
  static const String prefKey = 'flexpos_app_logo_url';

  AppLogoController._() : super(defaultLogoPath) {
    _initLogo();
  }

  Future<void> _initLogo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedLogo = prefs.getString(prefKey);
      if (cachedLogo != null && cachedLogo.trim().isNotEmpty) {
        value = cachedLogo.trim();
      }

      if (SupabaseConfig.isConfigured) {
        try {
          final res = await Supabase.instance.client
              .from('system_settings')
              .select('value')
              .eq('key', 'app_logo_url')
              .maybeSingle();

          if (res != null && res['value'] != null) {
            final remoteLogo = res['value'].toString().trim();
            if (remoteLogo.isNotEmpty && remoteLogo != value) {
              value = remoteLogo;
              await prefs.setString(prefKey, remoteLogo);
            }
          }
        } catch (e) {
          debugPrint('[AppLogoController] Error syncing remote logo: $e');
        }
      }
    } catch (e) {
      debugPrint('[AppLogoController] Error loading logo preference: $e');
    }
  }

  Future<void> updateLogo(String logoUrl) async {
    final trimmed = logoUrl.trim();
    final newLogo = trimmed.isEmpty ? defaultLogoPath : trimmed;

    value = newLogo;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, newLogo);
    } catch (e) {
      debugPrint('[AppLogoController] Error saving logo preference: $e');
    }
  }

  Future<void> resetToDefault() async {
    await updateLogo(defaultLogoPath);
  }
}
