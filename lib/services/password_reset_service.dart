import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../models/admin_models.dart';
import 'exceptions.dart';

/// Service managing user password reset requests and admin password reset operations.
class PasswordResetService {
  final SupabaseClient? customClient;

  PasswordResetService({SupabaseClient? client}) : customClient = client;

  SupabaseClient? get client {
    if (customClient != null) return customClient;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Submits a new password reset request from the login page after verifying user existence.
  Future<void> submitPasswordResetRequest(String rawInput) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw const FlexPOSException('Please enter a valid email address or username.');
    }

    final c = client;
    if (c == null) {
      debugPrint('[PasswordResetService] Supabase unconfigured. Simulated password reset request for $trimmed');
      return;
    }

    try {
      // 1. Primary attempt: Call the secure submit_password_reset_request RPC
      try {
        final res = await c.rpc('submit_password_reset_request', params: {
          'p_email': trimmed,
        });
        debugPrint('[PasswordResetService] submit_password_reset_request RPC response: $res');
        return;
      } on PostgrestException catch (e) {
        if (e.message.contains('No user account found') || e.message.contains('Failed to reset password')) {
          throw FlexPOSException(e.message);
        }
        debugPrint('[PasswordResetService] RPC error (${e.message}), trying fallback check...');
      } catch (e) {
        if (e is FlexPOSException) rethrow;
        debugPrint('[PasswordResetService] RPC exception ($e), trying fallback check...');
      }

      // 2. Fallback check if RPC is not deployed yet
      bool userExists = false;

      try {
        final profile = await c
            .from('profiles')
            .select('id, email')
            .ilike('email', trimmed)
            .maybeSingle();
        if (profile != null) {
          userExists = true;
        }
      } catch (_) {}

      if (!userExists) {
        try {
          final existsRes = await c.rpc('check_user_exists', params: {'p_email': trimmed});
          if (existsRes == true || existsRes == 1) {
            userExists = true;
          }
        } catch (_) {}
      }

      if (!userExists) {
        throw FlexPOSException('Failed to reset password: No user account found for "$trimmed".');
      }

      // 3. User exists, insert into password_reset_requests
      await c.from('password_reset_requests').insert({
        'email': trimmed,
        'status': 'pending',
      });
    } on FlexPOSException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('[PasswordResetService] Error submitting reset request: ${e.message}');
      throw FlexPOSException('Failed to submit password reset request: ${e.message}');
    } catch (e) {
      debugPrint('[PasswordResetService] Unexpected error submitting reset request: $e');
      throw FlexPOSException('Failed to submit password reset request: ${e.toString()}');
    }
  }

  /// Fetches count of all pending password reset requests for the live notification badge.
  Future<int> getPendingRequestsCount() async {
    final c = client;
    if (c == null) return 0;

    try {
      final res = await c
          .from('password_reset_requests')
          .select('id')
          .eq('status', 'pending');
      if (res is List) {
        return res.length;
      }
      return 0;
    } catch (e) {
      debugPrint('[PasswordResetService] Error getting pending requests count: $e');
      return 0;
    }
  }

  /// Fetches all password reset requests for the Admin Notifications tab.
  Future<List<PasswordResetRequestModel>> getAllRequests() async {
    final c = client;
    if (c == null) return [];

    try {
      final res = await c
          .from('password_reset_requests')
          .select()
          .order('created_at', ascending: false);

      if (res is List) {
        return res
            .map((e) => PasswordResetRequestModel.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[PasswordResetService] Error fetching password reset requests: $e');
      return [];
    }
  }

  /// Resets a user's password using the admin_reset_user_password RPC and resolves the request.
  Future<void> adminResetUserPassword({
    required String requestId,
    required String email,
    required String newPassword,
  }) async {
    if (newPassword.trim().length < 6) {
      throw const FlexPOSException('Password must be at least 6 characters.');
    }

    final c = client;
    if (c == null) {
      debugPrint('[PasswordResetService] Supabase unconfigured. Simulated password reset for $email');
      return;
    }

    try {
      final res = await c.rpc('admin_reset_user_password', params: {
        'p_request_id': requestId.isNotEmpty ? requestId : null,
        'p_email': email.trim(),
        'p_new_password': newPassword.trim(),
      });

      debugPrint('[PasswordResetService] admin_reset_user_password response: $res');
    } on PostgrestException catch (e) {
      debugPrint('[PasswordResetService] RPC error during password reset: ${e.message}');
      // Fallback: update request status directly if RPC fails
      try {
        if (requestId.isNotEmpty) {
          await c.from('password_reset_requests').update({
            'status': 'resolved',
            'admin_notes': 'Marked resolved by Admin',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', requestId);
        }
      } catch (_) {}
      throw FlexPOSException('Failed to reset password: ${e.message}');
    } catch (e) {
      debugPrint('[PasswordResetService] Unexpected error during password reset: $e');
      throw FlexPOSException('Error resetting password: ${e.toString()}');
    }
  }

  /// Dismisses / rejects a password reset request.
  Future<void> rejectRequest(String requestId) async {
    final c = client;
    if (c == null) return;

    try {
      await c.from('password_reset_requests').update({
        'status': 'rejected',
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', requestId);
    } catch (e) {
      debugPrint('[PasswordResetService] Error rejecting request: $e');
    }
  }
}
