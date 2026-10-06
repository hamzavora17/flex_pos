import 'package:supabase_flutter/supabase_flutter.dart';
import 'exceptions.dart';

/// Reusable service for resolving the current authenticated user's store business ID.
class BusinessService {
  final SupabaseClient? customClient;
  String? _cachedBusinessId;

  BusinessService({SupabaseClient? client}) : customClient = client;

  SupabaseClient get client => customClient ?? Supabase.instance.client;

  /// Resets the cached business ID (useful on logout or session changes).
  void clearCache() {
    _cachedBusinessId = null;
  }

  /// Resolves and returns the active business ID for the current authenticated user.
  ///
  /// For Admins: Finds business where `owner_id = auth.uid()`.
  /// For Employees: Finds `employees.business_id` where `profile_id = auth.uid()` and status is 'active'.
  ///
  /// Throws [BusinessNotFoundException] if no active business assignment is found.
  Future<String> getBusinessId({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedBusinessId != null && _cachedBusinessId!.isNotEmpty) {
      return _cachedBusinessId!;
    }

    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw const BusinessNotFoundException('No authenticated user session found.');
    }

    try {
      // 1. Attempt server-side RPC resolution via get_user_business_id()
      try {
        final rpcResult = await client.rpc('get_user_business_id');
        if (rpcResult != null && rpcResult.toString().trim().isNotEmpty) {
          _cachedBusinessId = rpcResult.toString().trim();
          return _cachedBusinessId!;
        }
      } catch (_) {
        // Fall back to direct query if RPC is unavailable in current context
      }

      // 2. Check if user is an Admin owning a business
      final ownedBusiness = await client
          .from('businesses')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      if (ownedBusiness != null && ownedBusiness['id'] != null) {
        _cachedBusinessId = ownedBusiness['id'].toString();
        return _cachedBusinessId!;
      }

      // 3. Check if user is an Employee assigned to an active business
      final employeeRecord = await client
          .from('employees')
          .select('business_id')
          .eq('profile_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (employeeRecord != null && employeeRecord['business_id'] != null) {
        _cachedBusinessId = employeeRecord['business_id'].toString();
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
