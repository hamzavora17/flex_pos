import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import 'exceptions.dart';

/// Reusable service for resolving the current authenticated user's store business ID.
class BusinessService {
  final SupabaseClient? customClient;
  String? _cachedBusinessId;
  String? _cachedUserId;

  BusinessService({SupabaseClient? client}) : customClient = client;

  SupabaseClient? get client {
    if (customClient != null) return customClient;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Resets the cached business ID and user ID session binding.
  void clearCache() {
    _cachedBusinessId = null;
    _cachedUserId = null;
  }

  /// Resolves and returns the active business ID for the current authenticated user.
  ///
  /// For Admins: Finds business where `owner_id = auth.uid()`.
  /// For Employees: Finds `employees.business_id` where `profile_id = auth.uid()` and status is 'active'.
  /// For Members: Finds `business_memberships.business_id` where `user_id = auth.uid()` and active is true.
  ///
  /// Throws [BusinessNotFoundException] if no active business assignment is found or if associations conflict.
  Future<String> getBusinessId({bool forceRefresh = false}) async {
    final c = client;
    if (c == null) {
      clearCache();
      throw const BusinessNotFoundException('No authenticated user session found.');
    }

    final userId = c.auth.currentUser?.id;
    if (userId == null) {
      clearCache();
      throw const BusinessNotFoundException('No authenticated user session found.');
    }

    // Invalidate cache immediately if session user changed or forced refresh requested
    if (forceRefresh || _cachedUserId != userId) {
      clearCache();
    }

    if (_cachedBusinessId != null && _cachedBusinessId!.isNotEmpty) {
      return _cachedBusinessId!;
    }

    try {
      // 1. Attempt server-side RPC resolution via get_user_business_id()
      try {
        final rpcResult = await c.rpc('get_user_business_id');
        if (rpcResult != null && rpcResult.toString().trim().isNotEmpty) {
          _cachedBusinessId = rpcResult.toString().trim();
          _cachedUserId = userId;
          return _cachedBusinessId!;
        }
        // RPC executed successfully and returned null -> fail closed without fallback
        throw const BusinessNotFoundException('No active store business association found for current user.');
      } on PostgrestException catch (e) {
        if (e.message.contains('Conflicting')) {
          throw const BusinessNotFoundException('Conflicting store associations detected for current user.');
        }
        // Fall back to direct query ONLY if function does not exist on database yet (Error 42883)
        if (e.code != '42883') {
          rethrow;
        }
      }

      // 2. Direct query fallback ONLY when RPC is unmigrated (Error 42883)
      final ownedBusiness = await c
          .from('businesses')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      final employeeRecord = await c
          .from('employees')
          .select('business_id')
          .eq('profile_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      dynamic membershipRecord;
      try {
        membershipRecord = await c
            .from('business_memberships')
            .select('business_id')
            .eq('user_id', userId)
            .eq('active', true)
            .maybeSingle();
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST116') {
          // Multiple active membership rows found for user -> conflicting associations!
          throw const BusinessNotFoundException('Conflicting store associations detected for current user.');
        }
        // Ignore ONLY 42P01 (relation business_memberships does not exist)
        if (e.code != '42P01') {
          rethrow;
        }
      }

      final ownerBid = ownedBusiness?['id']?.toString();
      final empBid = employeeRecord?['business_id']?.toString();
      final memberBid = membershipRecord?['business_id']?.toString();

      final activeBids = <String>{
        if (ownerBid != null && ownerBid.isNotEmpty) ownerBid,
        if (empBid != null && empBid.isNotEmpty) empBid,
        if (memberBid != null && memberBid.isNotEmpty) memberBid,
      };

      if (activeBids.length > 1) {
        throw const BusinessNotFoundException('Conflicting store associations detected for current user.');
      } else if (activeBids.length == 1) {
        _cachedBusinessId = activeBids.first;
        _cachedUserId = userId;
        return _cachedBusinessId!;
      }

      throw const BusinessNotFoundException('No active store business association found for current user.');
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw BusinessNotFoundException('Error resolving business ID for user', e);
    }
  }
}
