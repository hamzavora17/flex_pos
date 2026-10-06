import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../models/attendance_model.dart';
import '../models/recent_activity_model.dart';
import '../models/shift_model.dart';
import '../models/user_role.dart';
import 'business_service.dart';
import 'exceptions.dart';

/// Custom exception containing detailed Supabase error information.
class DashboardException implements Exception {
  final String message;
  final String? code;
  final String? details;
  final String? hint;
  final String? failingTable;
  final dynamic cause;

  const DashboardException({
    required this.message,
    this.code,
    this.details,
    this.hint,
    this.failingTable,
    this.cause,
  });

  @override
  String toString() {
    final buffer = StringBuffer('DashboardException: $message');
    if (code != null) buffer.write(' (Code: $code)');
    if (failingTable != null) buffer.write(' [Table: $failingTable]');
    if (details != null && details!.isNotEmpty) buffer.write('\nDetails: $details');
    if (hint != null && hint!.isNotEmpty) buffer.write('\nHint: $hint');
    return buffer.toString();
  }
}

/// Aggregated data model containing all real data for the cashier dashboard.
class CashierDashboardData {
  final String userId;
  final String fullName;
  final String email;
  final String role;
  final String position;
  final String terminalId;
  final double todaySales;
  final double todayEarnings;
  final int todayBills;
  final ShiftModel? activeShift;
  final AttendanceModel? todayAttendance;
  final List<RecentActivityModel> recentActivities;

  // Optional partial section errors
  final String? overviewError;
  final String? shiftError;
  final String? activityError;

  const CashierDashboardData({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.position,
    required this.terminalId,
    required this.todaySales,
    required this.todayEarnings,
    required this.todayBills,
    this.activeShift,
    this.todayAttendance,
    required this.recentActivities,
    this.overviewError,
    this.shiftError,
    this.activityError,
  });
}

/// Service providing database-driven data for the Cashier Dashboard.
class CashierDashboardService {
  final SupabaseClient? customClient;
  final BusinessService? customBusinessService;

  CashierDashboardService({
    SupabaseClient? client,
    BusinessService? businessService,
  })  : customClient = client,
        customBusinessService = businessService;

  SupabaseClient? get client {
    if (customClient != null) return customClient;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  BusinessService get businessService =>
      customBusinessService ?? BusinessService(client: customClient);

  static String _formatWorkDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  void _logErrorDetails({
    required String step,
    required String table,
    required String userId,
    required String businessId,
    required dynamic error,
  }) {
    debugPrint('\n==================================================');
    debugPrint('DASHBOARD LOAD ERROR at Step: $step');
    debugPrint('Table/Operation: $table');
    debugPrint('User ID: $userId');
    debugPrint('Business ID: $businessId');

    if (error is PostgrestException) {
      debugPrint('Supabase Error Message: ${error.message}');
      debugPrint('Supabase Error Code: ${error.code}');
      debugPrint('Supabase Details: ${error.details}');
      debugPrint('Supabase Hint: ${error.hint}');
    } else {
      debugPrint('Error: ${error.toString()}');
    }
    debugPrint('==================================================\n');
  }

  /// Automatically starts or resumes an active shift upon successful login.
  /// Sets SHIFT STARTED to the exact authentication time.
  Future<ShiftModel> startShiftOnLogin(String userId, {double openingFloat = 150.0}) async {
    final c = client;

    if (!SupabaseConfig.isConfigured || c == null) {
      throw const DashboardException(message: 'Supabase is not configured.');
    }

    final businessId = await businessService.getBusinessId();
    if (businessId.isEmpty) {
      throw const DashboardException(
        message: 'Unable to start shift: No active store business assignment found for user.',
      );
    }

    // 1. Check if an active shift already exists for this user
    try {
      final existingRes = await c
          .from('shifts')
          .select('*')
          .eq('employee_id', userId)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existingRes != null) {
        return ShiftModel.fromMap(existingRes);
      }

      // 2. Insert new active shift using real schema
      final shiftRes = await c.from('shifts').insert({
        'employee_id': userId,
        'expected_cash': openingFloat,
        'status': 'active',
      }).select().single();

      final shift = ShiftModel.fromMap(shiftRes);

      // Attendance table does not exist in production schema.
      // Skipping attendance recording to prevent crashes.

      return shift;
    } catch (e) {
      _logErrorDetails(
        step: 'startShiftOnLogin',
        table: 'shifts / attendance',
        userId: userId,
        businessId: businessId,
        error: e,
      );
      throw DashboardException(
        message: 'Failed to start shift or record attendance on database: ${e.toString()}',
      );
    }
  }

  /// Fetches complete real dashboard metrics and data for the current authenticated user.
  /// Uses the exact same underlying sales query for Today's Overview and Recent Activity.
  Future<CashierDashboardData> getDashboardData() async {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      throw const DashboardException(message: 'Supabase is not configured.');
    }

    final user = c.auth.currentUser;
    if (user == null) {
      throw const DashboardException(message: 'No authenticated user session found.');
    }

    final userId = user.id;
    debugPrint('--- [DASHBOARD] Loading data for User ID: $userId ---');

    // ------------------------------------------------------------------------
    // STEP 1: USER PROFILE & ROLE RESOLUTION (MUST FAIL CLOSED)
    // ------------------------------------------------------------------------
    final Map<String, dynamic>? profileRes;
    try {
      profileRes = await c
          .from('profiles')
          .select('id, email, full_name, role')
          .eq('id', userId)
          .maybeSingle();
    } catch (e) {
      _logErrorDetails(
        step: '1. Profile Query',
        table: 'profiles',
        userId: userId,
        businessId: '',
        error: e,
      );
      throw DashboardException(
        message: 'Failed to query user profile from database: ${e.toString()}',
      );
    }

    if (profileRes == null) {
      throw const DashboardException(
        message: 'User profile row does not exist in public.profiles.',
      );
    }

    final rawRole = profileRes['role']?.toString();
    final parsedRole = UserRole.fromString(rawRole);

    if (parsedRole == null) {
      throw DashboardException(
        message: 'Invalid or unresolved profile role "$rawRole" for user $userId.',
      );
    }

    final String userEmail = profileRes['email']?.toString() ?? user.email ?? '';
    String userFullName = profileRes['full_name']?.toString() ?? '';
    final String userRoleStr = parsedRole == UserRole.cashier
        ? 'EMPLOYEE'
        : parsedRole.toDbString().toUpperCase();

    if (userFullName.isEmpty) {
      final emailPrefix = userEmail.split('@').first;
      userFullName = emailPrefix.isNotEmpty
          ? emailPrefix[0].toUpperCase() + emailPrefix.substring(1)
          : 'Cashier';
    }

    // ------------------------------------------------------------------------
    // STEP 2: BUSINESS & EMPLOYEE POSITION
    // ------------------------------------------------------------------------
    final String businessId;
    try {
      businessId = await businessService.getBusinessId();
    } on FlexPOSException catch (e) {
      _logErrorDetails(
        step: '2. Business Resolution',
        table: 'businesses / employees',
        userId: userId,
        businessId: '',
        error: e,
      );
      throw DashboardException(
        message: e.message,
        failingTable: 'employees / businesses',
        cause: e,
      );
    } catch (e) {
      _logErrorDetails(
        step: '2. Business Resolution',
        table: 'businesses / employees',
        userId: userId,
        businessId: '',
        error: e,
      );
      throw DashboardException(
        message: 'Failed to resolve store business assignment: ${e.toString()}',
        failingTable: 'employees / businesses',
        cause: e,
      );
    }

    String position = 'Cashier';
    try {
      final empRes = await c
          .from('employees')
          .select('position')
          .eq('profile_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (empRes != null && empRes['position'] != null) {
        position = empRes['position'].toString();
      }
    } catch (e) {
      _logErrorDetails(
        step: '2. Business / Employee Query',
        table: 'employees / businesses',
        userId: userId,
        businessId: businessId,
        error: e,
      );
      throw DashboardException(
        message: 'Failed to query employee position from database: ${e.toString()}',
      );
    }

    // ------------------------------------------------------------------------
    // STEP 3: UNIFIED COMPLETED SALES QUERY
    // ------------------------------------------------------------------------
    List<dynamic> salesList = [];
    try {
      final salesRes = await c
          .from('sales')
          .select('id, invoice_number, total, status, created_at, payments(amount, payment_method)')
          .eq('business_id', businessId)
          .eq('employee_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false);

      salesList = salesRes as List<dynamic>? ?? [];
    } catch (e) {
      _logErrorDetails(
        step: '3. Completed Sales Query',
        table: 'sales / payments',
        userId: userId,
        businessId: businessId,
        error: e,
      );
      throw DashboardException(
        message: 'Failed to query completed sales from database: ${e.toString()}',
      );
    }

    final now = DateTime.now();
    final todayStr = _formatWorkDate(now);

    String targetWorkDate = todayStr;
    if (salesList.isNotEmpty) {
      final latestCreatedAt = DateTime.tryParse(salesList.first['created_at']?.toString() ?? '')?.toLocal();
      if (latestCreatedAt != null) {
        final latestDateStr = _formatWorkDate(latestCreatedAt);
        if (latestDateStr == todayStr || now.difference(latestCreatedAt).inHours < 24) {
          targetWorkDate = latestDateStr;
        }
      }
    }

    final todaysSalesList = salesList.where((sale) {
      final createdAtRaw = sale['created_at']?.toString();
      if (createdAtRaw == null) return false;
      final dt = DateTime.parse(createdAtRaw).toLocal();
      return _formatWorkDate(dt) == targetWorkDate;
    }).toList();

    double todaySales = 0.0;
    double todayEarnings = 0.0;
    int todayBills = todaysSalesList.length;

    for (var sale in todaysSalesList) {
      final totalVal = (sale['total'] is num)
          ? (sale['total'] as num).toDouble()
          : double.tryParse(sale['total']?.toString() ?? '0.0') ?? 0.0;
      todaySales += totalVal;

      final paymentsList = sale['payments'] as List<dynamic>? ?? [];
      for (var p in paymentsList) {
        final pAmt = (p['amount'] is num)
            ? (p['amount'] as num).toDouble()
            : double.tryParse(p['amount']?.toString() ?? '0.0') ?? 0.0;
        todayEarnings += pAmt;
      }
    }

    // ------------------------------------------------------------------------
    // STEP 4: ACTIVE SHIFT QUERY
    // ------------------------------------------------------------------------
    ShiftModel? activeShift;
    try {
      final shiftRes = await c
          .from('shifts')
          .select('*')
          .eq('employee_id', userId)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (shiftRes != null) {
        activeShift = ShiftModel.fromMap(shiftRes);
      }
    } catch (e) {
      _logErrorDetails(
        step: '4. Active Shift Query',
        table: 'shifts',
        userId: userId,
        businessId: businessId,
        error: e,
      );
      throw DashboardException(
        message: 'Failed to query active shift from database: ${e.toString()}',
      );
    }

    // ------------------------------------------------------------------------
    // STEP 5: TODAY'S ATTENDANCE QUERY (Removed due to missing table)
    // ------------------------------------------------------------------------
    AttendanceModel? todayAttendance;
    // (Attendance table is missing in production schema, leaving as null)

    // ------------------------------------------------------------------------
    // STEP 6: RECENT ACTIVITY
    // ------------------------------------------------------------------------
    List<RecentActivityModel> recentActivities = [];
    try {
      recentActivities = await _buildRecentActivitiesFromData(
        userId: userId,
        businessId: businessId,
        salesList: salesList,
      );
    } catch (e) {
      _logErrorDetails(
        step: '6. Recent Activity Processing',
        table: 'held_sales / shifts',
        userId: userId,
        businessId: businessId,
        error: e,
      );
      // Fallback to recent activities from salesList only rather than failing the dashboard
      recentActivities = salesList.take(5).map((s) {
        final inv = s['invoice_number']?.toString() ?? 'SALE';
        final total = (s['total'] is num)
            ? (s['total'] as num).toDouble()
            : double.tryParse(s['total']?.toString() ?? '0.0') ?? 0.0;
        final payments = s['payments'] as List<dynamic>? ?? [];
        String method = 'Cash';
        if (payments.isNotEmpty) {
          final mRaw = payments.first['payment_method']?.toString() ?? 'cash';
          method = mRaw[0].toUpperCase() + mRaw.substring(1);
        }
        final createdAt = DateTime.parse(s['created_at'].toString()).toLocal();

        return RecentActivityModel(
          id: s['id'].toString(),
          title: 'Completed Sale #$inv',
          details: '₹${total.toStringAsFixed(2)} • $method Payment',
          timestamp: createdAt,
          icon: Icons.check_circle_outline,
          iconColor: const Color(0xFF8DB600),
          type: 'sale',
        );
      }).toList();
    }

    return CashierDashboardData(
      userId: userId,
      fullName: userFullName,
      email: userEmail,
      role: userRoleStr,
      position: position.toUpperCase(),
      terminalId: 'POS-TERM-01',
      todaySales: todaySales,
      todayEarnings: todayEarnings,
      todayBills: todayBills,
      activeShift: activeShift,
      todayAttendance: todayAttendance,
      recentActivities: recentActivities,
    );
  }

  /// Builds recent activity logs using the already-fetched salesList + held_sales and shifts.
  Future<List<RecentActivityModel>> _buildRecentActivitiesFromData({
    required String userId,
    required String businessId,
    required List<dynamic> salesList,
  }) async {
    final activities = <RecentActivityModel>[];
    final c = client;
    if (c == null) {
      throw const DashboardException(message: 'Supabase client is uninitialized.');
    }

    // 1. Process Completed Sales
    for (var s in salesList.take(5)) {
      final inv = s['invoice_number']?.toString() ?? 'SALE';
      final total = (s['total'] is num)
          ? (s['total'] as num).toDouble()
          : double.tryParse(s['total']?.toString() ?? '0.0') ?? 0.0;
      final payments = s['payments'] as List<dynamic>? ?? [];
      String method = 'Cash';
      if (payments.isNotEmpty) {
        final mRaw = payments.first['payment_method']?.toString() ?? 'cash';
        method = mRaw[0].toUpperCase() + mRaw.substring(1);
      }
      final createdAt = DateTime.parse(s['created_at'].toString()).toLocal();

      activities.add(RecentActivityModel(
        id: s['id'].toString(),
        title: 'Completed Sale #$inv',
        details: '₹${total.toStringAsFixed(2)} • $method Payment',
        timestamp: createdAt,
        icon: Icons.check_circle_outline,
        iconColor: const Color(0xFF8DB600),
        type: 'sale',
      ));
    }

    if (businessId.isNotEmpty) {
      // 2. Recent Held Sales (safe against missing held_sales table)
      try {
        final heldRes = await c
            .from('held_sales')
            .select('id, reference_number, created_at, held_sale_items(quantity)')
            .eq('business_id', businessId)
            .eq('employee_id', userId)
            .eq('status', 'held')
            .order('created_at', ascending: false)
            .limit(5);

        for (var h in (heldRes as List<dynamic>? ?? [])) {
          final ref = h['reference_number']?.toString() ?? 'HOLD';
          final items = h['held_sale_items'] as List<dynamic>? ?? [];
          int totalQty = 0;
          for (var item in items) {
            totalQty += (item['quantity'] as num? ?? 1).toInt();
          }
          final createdAt = DateTime.parse(h['created_at'].toString()).toLocal();

          activities.add(RecentActivityModel(
            id: h['id'].toString(),
            title: 'Held Sale #$ref',
            details: '$totalQty items • Paused Cart',
            timestamp: createdAt,
            icon: Icons.pause_circle_outline,
            iconColor: Colors.amber.shade800,
            type: 'held_sale',
          ));
        }
      } catch (e) {
        // Table public.held_sales does not exist in production schema; ignore gracefully
      }

      // 3. Recent Shifts (safe against query error)
      try {
        final shiftRes = await c
            .from('shifts')
            .select('id, status, created_at, updated_at')
            .eq('employee_id', userId)
            .order('created_at', ascending: false)
            .limit(3);

        for (var sh in (shiftRes as List<dynamic>? ?? [])) {
          final startTime = DateTime.parse(sh['created_at'].toString()).toLocal();
          activities.add(RecentActivityModel(
            id: '${sh['id']}_start',
            title: 'Shift Session Started',
            details: 'Shift session opened',
            timestamp: startTime,
            icon: Icons.access_time,
            iconColor: const Color(0xFF003366),
            type: 'shift',
          ));

          if (sh['status'] == 'ended' && sh['updated_at'] != null) {
            final endTime = DateTime.parse(sh['updated_at'].toString()).toLocal();
            activities.add(RecentActivityModel(
              id: '${sh['id']}_end',
              title: 'Shift Session Ended',
              details: 'Shift completed and closed',
              timestamp: endTime,
              icon: Icons.stop_circle_outlined,
              iconColor: Colors.red[800]!,
              type: 'shift',
            ));
          }
        }
      } catch (e) {
        // Ignore shift query failure gracefully
      }
    }

    // Sort all activities by timestamp descending
    activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return activities.take(5).toList();
  }

  /// Starts a new active cashier shift and records attendance if missing.
  Future<ShiftModel> startShift({double openingFloat = 150.0}) async {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      throw const DashboardException(message: 'Supabase is not configured.');
    }

    final user = c.auth.currentUser;
    if (user == null) {
      throw const DashboardException(message: 'No authenticated user session found.');
    }

    return startShiftOnLogin(user.id, openingFloat: openingFloat);
  }

  /// Ends the specified active cashier shift.
  Future<void> endShift(String shiftId) async {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      throw const DashboardException(message: 'Supabase is not configured.');
    }

    try {
      await c.from('shifts').update({
        'status': 'ended',
        // updated_at is handled by DB or just tracking by created_at/updated_at
      }).eq('id', shiftId);
    } catch (e) {
      _logErrorDetails(
        step: 'endShift',
        table: 'shifts',
        userId: c.auth.currentUser?.id ?? '',
        businessId: '',
        error: e,
      );
      throw DashboardException(
        message: 'Failed to end shift on database: ${e.toString()}',
      );
    }
  }

  /// Subscribes to Realtime database changes on sales, payments, shifts, and held_sales tables.
  RealtimeChannel? subscribeToDashboardChanges({
    required String userId,
    required VoidCallback onDataChanged,
  }) {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) return null;

    try {
      final channel = c.channel('public:cashier_dashboard_$userId');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sales',
        callback: (payload) => onDataChanged(),
      );

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'payments',
        callback: (payload) => onDataChanged(),
      );

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'shifts',
        callback: (payload) => onDataChanged(),
      );

      try {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'held_sales',
          callback: (payload) => onDataChanged(),
        );
      } catch (_) {}

      channel.subscribe();
      return channel;
    } catch (_) {
      return null;
    }
  }
}
