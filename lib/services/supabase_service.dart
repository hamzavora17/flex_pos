import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';

/// Service providing a centralized access point to the Supabase client instance.
class SupabaseService {
  const SupabaseService._();

  /// Gets the initialized [SupabaseClient] instance.
  ///
  /// Throws a [StateError] if Supabase has not been configured with valid credentials.
  static SupabaseClient get client {
    if (!SupabaseConfig.isConfigured) {
      throw StateError(
        'Supabase client accessed before valid configuration. '
        'Set SUPABASE_URL and SUPABASE_ANON_KEY in lib/core/config/supabase_config.dart '
        'or pass them via --dart-define flags.',
      );
    }
    return Supabase.instance.client;
  }

  /// Indicates whether the Supabase client is initialized and ready for database operations.
  static bool get isReady => SupabaseConfig.isConfigured;
}
