import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../models/user_role.dart';
import 'exceptions.dart';

/// Service managing user role assignments and Auth user discovery for Admins.
class AdminUserService {
  final SupabaseClient? customClient;

  AdminUserService({SupabaseClient? client}) : customClient = client;

  SupabaseClient? get client {
    if (customClient != null) return customClient;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static bool isValidUuid(String uuid) {
    final uuidRegExp = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegExp.hasMatch(uuid.trim());
  }

  /// Fetches assignable Auth users using the secure Admin-only RPC get_assignable_auth_users.
  Future<List<Map<String, String>>> getAssignableUsers() async {
    final c = client;
    if (c == null) {
      throw const FlexPOSException('Supabase is not configured.');
    }

    try {
      final response = await c.rpc('get_assignable_auth_users');
      final List<Map<String, String>> users = [];
      for (var item in (response as List<dynamic>)) {
        final itemMap = Map<String, dynamic>.from(item as Map);
        final id = itemMap['id']?.toString() ?? '';
        final email = itemMap['email']?.toString() ?? 'No email';
        final fullName = itemMap['full_name']?.toString() ?? '';
        final role = itemMap['role']?.toString() ?? 'unassigned';

        final displayName = fullName.isNotEmpty
            ? '$fullName ($email) - Role: ${role.toUpperCase()}'
            : '$email - Role: ${role.toUpperCase()}';

        if (id.isNotEmpty) {
          users.add({
            'id': id,
            'email': email,
            'name': displayName,
            'role': role,
          });
        }
      }
      return users;
    } on PostgrestException catch (e) {
      debugPrint('[AdminUserService] Postgrest error fetching assignable users: ${e.message}');
      throw FlexPOSException('Failed to load assignable users: ${e.message}');
    } catch (e) {
      debugPrint('[AdminUserService] Error fetching assignable users: $e');
      if (e is FlexPOSException) rethrow;
      throw FlexPOSException('An error occurred while loading assignable users: $e');
    }
  }

  /// Assigns a manager or cashier role to a target user profile using the secure RPC.
  ///
  /// Requires an active authenticated Admin session.
  Future<Map<String, dynamic>> assignUserRole({
    required String targetUserId,
    required UserRole role,
  }) async {
    final trimmedUserId = targetUserId.trim();
    if (trimmedUserId.isEmpty) {
      throw const FlexPOSException('Target User ID cannot be empty.');
    }

    if (!isValidUuid(trimmedUserId)) {
      throw const FlexPOSException('Invalid Target User ID format. Must be a valid 36-character UUID.');
    }

    if (role == UserRole.admin) {
      throw const FlexPOSException('Role assignment is restricted to store staff roles (manager, cashier). Admin promotion is not allowed.');
    }

    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      debugPrint('[AdminUserService] Supabase unconfigured. Simulated role assignment for $trimmedUserId as ${role.toDbString()}');
      return {
        'success': true,
        'profile_id': trimmedUserId,
        'role': role.toDbString(),
        'position': role == UserRole.manager ? 'manager' : 'cashier',
      };
    }

    final currentUserId = c.auth.currentUser?.id;
    if (currentUserId == null) {
      throw const FlexPOSException('No authenticated Admin session found.');
    }

    try {
      final response = await c.rpc('assign_user_role', params: {
        'p_target_user_id': trimmedUserId,
        'p_role': role.toDbString(),
      });

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {'success': true};
    } on PostgrestException catch (e) {
      throw FlexPOSException('Failed to assign user role: ${e.message}');
    } catch (e) {
      throw FlexPOSException('An error occurred while assigning user role: $e');
    }
  }
}
