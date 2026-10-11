import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Global controller managing the dynamic Application / Store Display Name
/// with persistent local preference storage and live database synchronization.
class AppNameController extends ValueNotifier<String> {
  static final AppNameController instance = AppNameController._();

  static const String defaultAppName = 'FlexPOS';
  static const String prefKey = 'flexpos_app_name';

  AppNameController._() : super(defaultAppName) {
    _initAppName();
  }

  Future<void> _initAppName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedName = prefs.getString(prefKey);
      if (cachedName != null && cachedName.trim().isNotEmpty) {
        value = cachedName.trim();
      }

      if (SupabaseConfig.isConfigured) {
        try {
          final res = await Supabase.instance.client
              .from('system_settings')
              .select('value')
              .eq('key', 'app_name')
              .maybeSingle();

          if (res != null && res['value'] != null) {
            final remoteName = res['value'].toString().trim();
            final nameToUse = remoteName.isEmpty ? defaultAppName : remoteName;
            if (nameToUse != value) {
              value = nameToUse;
              await prefs.setString(prefKey, nameToUse);
            }
          }
        } catch (e) {
          debugPrint('[AppNameController] Error syncing remote app name: $e');
        }
      }
    } catch (e) {
      debugPrint('[AppNameController] Error loading app name preference: $e');
    }
  }

  Future<void> updateName(String newName) async {
    final trimmed = newName.trim();
    final nameToUse = trimmed.isEmpty ? defaultAppName : trimmed;

    value = nameToUse;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, nameToUse);
    } catch (e) {
      debugPrint('[AppNameController] Error saving app name preference: $e');
    }
  }

  Future<void> resetToDefault() async {
    await updateName(defaultAppName);
  }

  String get appName => value;
}

/// Reactive text widget displaying the dynamic application / store name
/// with optional prefix, suffix, and custom text styling.
class AppNameText extends StatelessWidget {
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final int? maxLines;

  const AppNameText({
    super.key,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.overflow,
    this.textAlign,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppNameController.instance,
      builder: (context, currentName, _) {
        final displayName = currentName.trim().isEmpty ? AppNameController.defaultAppName : currentName.trim();
        return Text(
          '$prefix$displayName$suffix',
          style: style,
          overflow: overflow,
          textAlign: textAlign,
          maxLines: maxLines,
        );
      },
    );
  }
}
