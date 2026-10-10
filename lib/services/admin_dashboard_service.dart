import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../models/admin_models.dart';
import 'exceptions.dart';

/// Comprehensive service for Admin Panel analytics, live realtime updates,
/// business unit controls, activity logs, user management, and system settings.
class AdminDashboardService {
  final SupabaseClient? customClient;
  RealtimeChannel? _realtimeChannel;

  AdminDashboardService({SupabaseClient? client}) : customClient = client;

  SupabaseClient? get client {
    if (customClient != null) return customClient;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Fetches real-time aggregated system-wide metrics from `get_admin_dashboard_stats` RPC.
  Future<AdminDashboardStats> getDashboardStats() async {
    final c = client;
    if (c == null) {
      throw const FlexPOSException('Supabase is not configured.');
    }

    try {
      final response = await c.rpc('get_admin_dashboard_stats');
      if (response == null) {
        throw const FlexPOSException('No response received from database RPC get_admin_dashboard_stats.');
      }

      final map = Map<String, dynamic>.from(response as Map);
      return AdminDashboardStats.fromMap(map);
    } on PostgrestException catch (e) {
      debugPrint('[AdminDashboardService] PostgrestError fetching stats: ${e.message}');
      throw FlexPOSException('Failed to load admin statistics: ${e.message}');
    } catch (e) {
      if (e is FlexPOSException) rethrow;
      throw FlexPOSException('Error fetching dashboard statistics', e);
    }
  }

  /// Fetches time-series chart data for revenue analytics from `get_admin_revenue_chart_data` RPC.
  Future<List<RevenueChartPoint>> getRevenueChartData({
    String period = 'last_7_days',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final c = client;
    if (c == null) return [];

    try {
      final params = <String, dynamic>{
        'p_period': period,
        if (startDate != null) 'p_start_date': startDate.toUtc().toIso8601String(),
        if (endDate != null) 'p_end_date': endDate.toUtc().toIso8601String(),
      };

      final response = await c.rpc('get_admin_revenue_chart_data', params: params);
      if (response is List) {
        return (response)
            .map((e) => RevenueChartPoint.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[AdminDashboardService] Error fetching revenue chart data: $e');
      return [];
    }
  }

  /// Fetches recent system activity logs from `activity_logs` table.
  Future<List<AdminActivityLog>> getActivityLogs({
    int limit = 20,
    int offset = 0,
    String? typeFilter,
  }) async {
    final c = client;
    if (c == null) return [];

    try {
      var query = c
          .from('activity_logs')
          .select('*, businesses(name), profiles(full_name, email)');

      if (typeFilter != null && typeFilter != 'all' && typeFilter.isNotEmpty) {
        query = query.eq('type', typeFilter);
      }

      final dynamic response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      if (response is List) {
        return response
            .map((json) => AdminActivityLog.fromMap(Map<String, dynamic>.from(json as Map)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[AdminDashboardService] Error fetching activity logs: $e');
      return [];
    }
  }

  /// Fetches list of business units with operational statistics.
  Future<List<BusinessUnitModel>> getBusinessUnits({
    String? searchQuery,
    String statusFilter = 'all',
  }) async {
    final c = client;
    if (c == null) return [];

    try {
      var query = c.from('businesses').select('*, profiles!businesses_owner_id_fkey(full_name, email)');

      if (statusFilter != 'all' && statusFilter.isNotEmpty) {
        query = query.eq('status', statusFilter);
      }

      final dynamic response = await query.order('created_at', ascending: false);
      final List<dynamic> list = response is List ? response : [];

      final todayStart = DateTime.now().toUtc().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
      final monthStart = DateTime.now().toUtc().copyWith(day: 1, hour: 0, minute: 0, second: 0, millisecond: 0);

      final result = <BusinessUnitModel>[];

      for (var item in list) {
        final bMap = Map<String, dynamic>.from(item as Map);
        final bId = bMap['id']?.toString() ?? '';

        // Fetch user count
        int userCount = 0;
        try {
          final empResp = await c.from('employees').select('id').eq('business_id', bId);
          userCount = (empResp as List).length;
        } catch (_) {}

        // Fetch Today Sales
        double todaySales = 0.0;
        try {
          final salesResp = await c
              .from('sales')
              .select('total')
              .eq('business_id', bId)
              .eq('status', 'completed')
              .gte('created_at', todayStart.toIso8601String());

          for (var s in (salesResp as List)) {
            todaySales += (s['total'] as num? ?? 0).toDouble();
          }
        } catch (_) {}

        // Fetch Monthly Sales
        double monthSales = 0.0;
        try {
          final mResp = await c
              .from('sales')
              .select('total')
              .eq('business_id', bId)
              .eq('status', 'completed')
              .gte('created_at', monthStart.toIso8601String());

          for (var s in (mResp as List)) {
            monthSales += (s['total'] as num? ?? 0).toDouble();
          }
        } catch (_) {}

        final model = BusinessUnitModel.fromMap(
          bMap,
          userCount: userCount,
          todaySales: todaySales,
          monthlyRevenue: monthSales,
        );

        if (searchQuery != null && searchQuery.trim().isNotEmpty) {
          final q = searchQuery.trim().toLowerCase();
          final nameMatch = model.businessName.toLowerCase().contains(q);
          final emailMatch = (model.email ?? '').toLowerCase().contains(q);
          final ownerMatch = (model.ownerName ?? '').toLowerCase().contains(q);
          if (!nameMatch && !emailMatch && !ownerMatch) {
            continue;
          }
        }

        result.add(model);
      }

      return result;
    } catch (e) {
      debugPrint('[AdminDashboardService] Error fetching business units: $e');
      throw FlexPOSException('Unable to load business units: $e');
    }
  }

  /// Fetches comprehensive details for a single selected business.
  Future<Map<String, dynamic>> getBusinessDetails(String businessId) async {
    final c = client;
    if (c == null) throw const FlexPOSException('Supabase not configured');

    try {
      final bResp = await c
          .from('businesses')
          .select('*, profiles!businesses_owner_id_fkey(full_name, email)')
          .eq('id', businessId)
          .single();

      final employeesResp = await c
          .from('employees')
          .select('*, profiles(full_name, email, role)')
          .eq('business_id', businessId);

      final todayStart = DateTime.now().toUtc().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
      final monthStart = DateTime.now().toUtc().copyWith(day: 1, hour: 0, minute: 0, second: 0, millisecond: 0);

      final salesTodayResp = await c
          .from('sales')
          .select('total')
          .eq('business_id', businessId)
          .eq('status', 'completed')
          .gte('created_at', todayStart.toIso8601String());

      double todayRevenue = 0.0;
      int todayTxCount = (salesTodayResp as List).length;
      for (var s in salesTodayResp) {
        todayRevenue += (s['total'] as num? ?? 0).toDouble();
      }

      final salesMonthResp = await c
          .from('sales')
          .select('total')
          .eq('business_id', businessId)
          .eq('status', 'completed')
          .gte('created_at', monthStart.toIso8601String());

      double monthlyRevenue = 0.0;
      int monthlyTxCount = (salesMonthResp as List).length;
      for (var s in salesMonthResp) {
        monthlyRevenue += (s['total'] as num? ?? 0).toDouble();
      }

      final recentSalesResp = await c
          .from('sales')
          .select('*, profiles(full_name, email)')
          .eq('business_id', businessId)
          .order('created_at', ascending: false)
          .limit(5);

      return {
        'business': BusinessUnitModel.fromMap(
          Map<String, dynamic>.from(bResp),
          userCount: (employeesResp as List).length,
          todaySales: todayRevenue,
          monthlyRevenue: monthlyRevenue,
        ),
        'employees': employeesResp,
        'today_revenue': todayRevenue,
        'today_transactions': todayTxCount,
        'monthly_revenue': monthlyRevenue,
        'monthly_transactions': monthlyTxCount,
        'recent_sales': recentSalesResp,
      };
    } catch (e) {
      throw FlexPOSException('Failed to load business details: $e');
    }
  }

  /// Updates status of a business unit (active / inactive / suspended / archived).
  Future<void> manageBusinessStatus(String businessId, String newStatus) async {
    final c = client;
    if (c == null) throw const FlexPOSException('Supabase not configured');

    try {
      await c.rpc('manage_business_status', params: {
        'p_business_id': businessId,
        'p_status': newStatus,
      });
    } catch (e) {
      throw FlexPOSException('Failed to update business status: $e');
    }
  }

  /// Registers a new business unit (Disabled in single-business mode).
  Future<void> createBusiness({
    required String name,
    String? ownerId,
    String? email,
    String? phone,
    String? address,
  }) async {
    throw const FlexPOSException('FlexPOS operates exclusively as a single-business application. Additional business creation is disabled.');
  }

  /// Fetches system settings list.
  Future<List<SystemSettingModel>> getSystemSettings() async {
    final c = client;
    if (c == null) return [];

    try {
      final dynamic response = await c.from('system_settings').select().order('key');
      if (response is List) {
        return response
            .map((json) => SystemSettingModel.fromMap(Map<String, dynamic>.from(json as Map)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[AdminDashboardService] Error fetching system settings: $e');
      return [];
    }
  }

  /// Updates a single system setting value.
  Future<void> updateSystemSetting(String key, String value) async {
    final c = client;
    if (c == null) throw const FlexPOSException('Supabase not configured');

    try {
      await c.from('system_settings').upsert({
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': c.auth.currentUser?.id,
      });
    } catch (e) {
      throw FlexPOSException('Failed to update system setting: $e');
    }
  }

  /// Fetches user summaries for User Management tab.
  Future<List<AdminUserSummary>> getAdminUsers({
    String? searchQuery,
    String roleFilter = 'all',
  }) async {
    final c = client;
    if (c == null) {
      throw const FlexPOSException('Supabase is not configured.');
    }

    try {
      var query = c.from('profiles').select('*, employees(*, businesses(*))');

      if (roleFilter != 'all' && roleFilter.isNotEmpty) {
        if (roleFilter == 'cashier') {
          query = query.inFilter('role', ['cashier', 'employee']);
        } else {
          query = query.eq('role', roleFilter);
        }
      }

      final dynamic response = await query.order('created_at', ascending: false);

      final List<dynamic> rawList;
      if (response is List) {
        rawList = response;
      } else if (response is Map) {
        final map = Map<String, dynamic>.from(response);
        if (map['data'] is List) {
          rawList = map['data'] as List;
        } else if (map['users'] is List) {
          rawList = map['users'] as List;
        } else if (map['profiles'] is List) {
          rawList = map['profiles'] as List;
        } else if (map['results'] is List) {
          rawList = map['results'] as List;
        } else if (map['result'] is List) {
          rawList = map['result'] as List;
        } else if (map.containsKey('id') || map.containsKey('email') || map.containsKey('role') || map.containsKey('full_name')) {
          rawList = [map];
        } else if (map.containsKey('error') || map.containsKey('message')) {
          final msg = map['message']?.toString() ?? map['error']?.toString() ?? 'Database query error';
          throw FlexPOSException('Failed to load user list: $msg');
        } else {
          debugPrint('[AdminDashboardService] Unrecognized map response structure for admin users: $map');
          rawList = [];
        }
      } else if (response == null) {
        rawList = [];
      } else {
        debugPrint('[AdminDashboardService] Unexpected response type for admin users: ${response.runtimeType}');
        rawList = [];
      }

      final list = rawList
          .map((json) => AdminUserSummary.fromMap(Map<String, dynamic>.from(json as Map)))
          .toList();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        return list.where((u) {
          final emailMatch = u.email.toLowerCase().contains(q);
          final nameMatch = u.fullName.toLowerCase().contains(q);
          final bMatch = (u.businessName ?? '').toLowerCase().contains(q);
          return emailMatch || nameMatch || bMatch;
        }).toList();
      }

      return list;
    } on PostgrestException catch (e) {
      debugPrint('[AdminDashboardService] Postgrest error fetching admin users: ${e.message}');
      throw FlexPOSException('Failed to load user list: ${e.message}');
    } catch (e) {
      debugPrint('[AdminDashboardService] Error fetching admin users: $e');
      if (e is FlexPOSException) rethrow;
      throw FlexPOSException('An error occurred while loading users: $e');
    }
  }

  /// Subscribes to Realtime database changes across sales, returns, businesses, profiles, and activity logs.
  void subscribeToRealtimeChanges(VoidCallback onUpdate) {
    final c = client;
    if (c == null) return;

    unsubscribeRealtime();

    try {
      _realtimeChannel = c.channel('admin_dashboard_updates');

      _realtimeChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'sales',
            callback: (payload) {
              debugPrint('[AdminDashboardService] Realtime event on sales: ${payload.eventType}');
              onUpdate();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'sale_returns',
            callback: (payload) {
              debugPrint('[AdminDashboardService] Realtime event on sale_returns: ${payload.eventType}');
              onUpdate();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'businesses',
            callback: (payload) {
              debugPrint('[AdminDashboardService] Realtime event on businesses: ${payload.eventType}');
              onUpdate();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'profiles',
            callback: (payload) {
              debugPrint('[AdminDashboardService] Realtime event on profiles: ${payload.eventType}');
              onUpdate();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'activity_logs',
            callback: (payload) {
              debugPrint('[AdminDashboardService] Realtime event on activity_logs: ${payload.eventType}');
              onUpdate();
            },
          )
          .subscribe((status, error) {
            debugPrint('[AdminDashboardService] Realtime channel status: $status, error: $error');
          });
    } catch (e) {
      debugPrint('[AdminDashboardService] Failed to set up realtime subscription: $e');
    }
  }

  /// Cleans up Realtime subscription cleanly on page/component disposal.
  void unsubscribeRealtime() {
    final c = client;
    if (c != null && _realtimeChannel != null) {
      try {
        c.removeChannel(_realtimeChannel!);
      } catch (e) {
        debugPrint('[AdminDashboardService] Error unsubscribing realtime channel: $e');
      } finally {
        _realtimeChannel = null;
      }
    }
  }
}
