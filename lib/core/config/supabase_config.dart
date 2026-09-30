import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuration layer for Supabase integration.
/// 
/// Credentials can be passed at build/run time using `--dart-define`:
/// ```bash
/// flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key
/// ```
/// Or updated directly in the default constant placeholders below.
abstract class SupabaseConfig {
  /// Supabase Project URL
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://guetrlodubohesyoyyit.supabase.co',
  );

  /// Supabase Anonymous (Public) Key / Publishable Key
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_Oixym0USK9Q8GqX0QSUrsQ_TjVTbgaP',
  );

  /// Checks whether valid non-placeholder credentials have been configured.
  static bool get isConfigured {
    return url.isNotEmpty &&
        url != 'YOUR_SUPABASE_URL_HERE' &&
        anonKey.isNotEmpty &&
        anonKey != 'YOUR_SUPABASE_ANON_KEY_HERE';
  }

  /// Initializes the Supabase client SDK if credentials are valid.
  static Future<void> initialize() async {
    if (!isConfigured) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Supabase credentials not found. '
          'Please set SUPABASE_URL and SUPABASE_ANON_KEY in lib/core/config/supabase_config.dart '
          'or pass them via --dart-define flags.',
        );
      }
      return;
    }

    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
      debug: kDebugMode,
    );
  }
}
