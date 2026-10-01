import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../models/attendance_model.dart';
import '../models/recent_activity_model.dart';
import '../models/shift_model.dart';
import 'business_service.dart';

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

  // Partial section errors (if an isolated query failed)
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

  // In-memory shift store for unconfigured or demo state
  static ShiftModel? _demoActiveShift = ShiftModel(
    id: 'demo-shift-1',
    businessId: 'demo-business',
    employeeId: 'demo-user',
    startTime: DateTime.now().subtract(const Duration(hours: 3, minutes: 45)),
    openingFloat: 150.0,
    status: 'active',
  );

  static AttendanceModel? _demoAttendance = AttendanceModel(
    id: 'demo-att-1',
    businessId: 'demo-business',
    employeeId: 'demo-user',
    reportingTime: DateTime.now().subtract(const Duration(hours: 4, minutes: 0)),
    status: 'present',
    workDate: _formatWorkDate(DateTime.now()),
  );

  CashierDashboardService({
    SupabaseClient? client,
    BusinessService? businessService,
  })  : customClient = client,
        customBusinessService = businessService;

  SupabaseClient? get client {
    if (customClient != null) return customClient;
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
  /// Sets REPORTING TIME to SHIFT STARTED - 15 MINUTES.
  Future<ShiftModel> startShiftOnLogin(String userId, {double openingFloat = 150.0}) async {
    final c = client;
    final now = DateTime.now();

    if (!SupabaseConfig.isConfigured || c == null) {
      _demoActiveShift = ShiftModel(
        id: 'demo-shift-${now.millisecondsSinceEpoch}',
        businessId: 'demo-business',
        employeeId: userId,
        startTime: now,
        openingFloat: openingFloat,
        status: 'active',
      );
      _demoAttendance = AttendanceModel(
        id: 'demo-att-${now.millisecondsSinceEpoch}',
        businessId: 'demo-business',
        employeeId: userId,
        reportingTime: now.subtract(const Duration(minutes: 15)),
        status: 'present',
        workDate: _formatWorkDate(now),
      );
      return _demoActiveShift!;
    }

    String businessId = '';
    try {
      businessId = await businessService.getBusinessId();
    } catch (e) {
      debugPrint('Business ID resolution warning on shift start: $e');
    }

    if (businessId.isEmpty) {
      return ShiftModel(
        id: 'temp-shift',
        businessId: 'temp',
        employeeId: userId,
        startTime: now,
        openingFloat: openingFloat,
        status: 'active',
      );
    }

    // 1. Check if an active shift already exists for this user
    try {
      final existingRes = await c
          .from('shifts')
          .select('*')
          .eq('business_id', businessId)
          .eq('employee_id', userId)
          .eq('status', 'active')
          .order('start_time', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existingRes != null) {
        return ShiftModel.fromMap(existingRes);
      }

      // 2. Insert new active shift using exact login timestamp
      final shiftRes = await c.from('shifts').insert({
        'business_id': businessId,
        'employee_id': userId,
        'start_time': now.toIso8601String(),
        'opening_float': openingFloat,
        'status': 'active',
      }).select().single();

      final shift = ShiftModel.fromMap(shiftRes);

      // 3. Record attendance for today with reporting_time = shift_start - 15 minutes
      try {
        final todayStr = _formatWorkDate(now);
        final reportingTime = now.subtract(const Duration(minutes: 15));
        await c.from('attendance').upsert({
          'business_id': businessId,
          'employee_id': userId,
          'reporting_time': reportingTime.toIso8601String(),
          'status': 'present',
          'work_date': todayStr,
        }, onConflict: 'employee_id, work_date');
      } catch (attErr) {
        debugPrint('Attendance upsert warning: $attErr');
      }

      return shift;
    } catch (e) {
      _logErrorDetails(
        step: 'startShiftOnLogin',
        table: 'shifts',
        userId: userId,
        businessId: businessId,
        error: e,
      );
      _demoActiveShift = ShiftModel(
        id: 'shift-${now.millisecondsSinceEpoch}',
        businessId: businessId,
        employeeId: userId,
        startTime: now,
        openingFloat: openingFloat,
        status: 'active',
      );
      return _demoActiveShift!;
    }
  }

  /// Fetches complete real dashboard metrics and data for the current authenticated user.
  /// Uses the exact same underlying sales query for Today's Overview and Recent Activity.
  Future<CashierDashboardData> getDashboardData() async {
    final c = client;
    final user = c?.auth.currentUser;
    if (!SupabaseConfig.isConfigured || c == null || user == null) {
      return _getDemoDashboardData(user);
    }

    final userId = user.id;
    debugPrint('--- [DASHBOARD] Loading data for User ID: $userId ---');

    // ------------------------------------------------------------------------
    // STEP 1: USER PROFILE
    // ------------------------------------------------------------------------
    String userEmail = user.email ?? '';
    String userFullName = '';
    String userRole = 'employee';

    try {
      final profileRes = await c
          .from('profiles')
          .select('id, email, full_name, role')
          .eq('id', userId)
          .maybeSingle();

      if (profileRes != null) {
        userEmail = profileRes['email']?.toString() ?? userEmail;
        userFullName = profileRes['full_name']?.toString() ?? '';
        userRole = profileRes['role']?.toString() ?? 'employee';
      }
    } catch (e) {
      _logErrorDetails(
        step: '1. Profile Query',
        table: 'profiles',
        userId: userId,
        businessId: '',
        error: e,
      );
    }

    if (userFullName.isEmpty) {
      final emailPrefix = userEmail.split('@').first;
      userFullName = emailPrefix.isNotEmpty
          ? emailPrefix[0].toUpperCase() + emailPrefix.substring(1)
          : 'Cashier';
    }

    // ------------------------------------------------------------------------
    // STEP 2: BUSINESS & EMPLOYEE POSITION
    // ------------------------------------------------------------------------
    String businessId = '';
    String position = 'Cashier';

    try {
      businessId = await businessService.getBusinessId();

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
    }

    // ------------------------------------------------------------------------
    // STEP 3: UNIFIED COMPLETED SALES QUERY (SAME DATA BASE AS RECENT ACTIVITY)
    // ------------------------------------------------------------------------
    List<dynamic> salesList = [];
    String? overviewError;

    if (businessId.isNotEmpty) {
      try {
        final salesRes = await c
            .from('sales')
            .select('id, invoice_number, total, status, created_at, payments(amount, payment_method, status)')
            .eq('business_id', businessId)
            .eq('employee_id', userId)
            .eq('status', 'completed')
            .order('created_at', ascending: false);

        salesList = salesRes as List<dynamic>? ?? [];
        debugPrint('--- [COMPLETED SALES QUERY SUCCESS] ${salesList.length} sales retrieved ---');
      } catch (e) {
        _logErrorDetails(
          step: '3. Completed Sales Query',
          table: 'sales / payments',
          userId: userId,
          businessId: businessId,
          error: e,
        );
        overviewError = e is PostgrestException ? '${e.message} (${e.code})' : e.toString();
      }
    }

    // Identify today's sales from salesList matching current active work date
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
        final pStatus = p['status']?.toString() ?? 'completed';
        if (pStatus == 'completed') {
          final pAmt = (p['amount'] is num)
              ? (p['amount'] as num).toDouble()
              : double.tryParse(p['amount']?.toString() ?? '0.0') ?? 0.0;
          todayEarnings += pAmt;
        }
      }
    }

    debugPrint('--- [TODAY\'S OVERVIEW SUMMARY] Sales: ₹$todaySales, Bills: $todayBills, Earnings: ₹$todayEarnings ---');

    // ------------------------------------------------------------------------
    // STEP 4: ACTIVE SHIFT
    // ------------------------------------------------------------------------
    ShiftModel? activeShift;
    String? shiftError;

    if (businessId.isNotEmpty) {
      try {
        final shiftRes = await c
            .from('shifts')
            .select('*')
            .eq('business_id', businessId)
            .eq('employee_id', userId)
            .eq('status', 'active')
            .order('start_time', ascending: false)
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
        shiftError = e is PostgrestException ? '${e.message} (${e.code})' : e.toString();
      }
    }

    activeShift ??= _demoActiveShift;

    // ------------------------------------------------------------------------
    // STEP 5: TODAY'S ATTENDANCE
    // ------------------------------------------------------------------------
    AttendanceModel? todayAttendance;

    if (businessId.isNotEmpty) {
      try {
        final todayStr = _formatWorkDate(now);
        final attRes = await c
            .from('attendance')
            .select('*')
            .eq('business_id', businessId)
            .eq('employee_id', userId)
            .eq('work_date', todayStr)
            .limit(1)
            .maybeSingle();

        if (attRes != null) {
          todayAttendance = AttendanceModel.fromMap(attRes);
        }
      } catch (e) {
        _logErrorDetails(
          step: '5. Attendance Query',
          table: 'attendance',
          userId: userId,
          businessId: businessId,
          error: e,
        );
      }
    }

    todayAttendance ??= _demoAttendance;

    // ------------------------------------------------------------------------
    // STEP 6: RECENT ACTIVITY (BUILT FROM RECENT SALES, HELD SALES & SHIFTS)
    // ------------------------------------------------------------------------
    List<RecentActivityModel> recentActivities = [];
    String? activityError;

    try {
      recentActivities = await _buildRecentActivitiesFromData(
        userId: userId,
        businessId: businessId,
        salesList: salesList,
      );
    } catch (e) {
      _logErrorDetails(
        step: '6. Recent Activity Processing',
        table: 'sales / held_sales / shifts',
        userId: userId,
        businessId: businessId,
        error: e,
      );
      activityError = e is PostgrestException ? '${e.message} (${e.code})' : e.toString();
    }

    return CashierDashboardData(
      userId: userId,
      fullName: userFullName,
      email: userEmail,
      role: userRole.toUpperCase(),
      position: position.toUpperCase(),
      terminalId: 'POS-TERM-01',
      todaySales: todaySales,
      todayEarnings: todayEarnings,
      todayBills: todayBills,
      activeShift: activeShift,
      todayAttendance: todayAttendance,
      recentActivities: recentActivities,
      overviewError: overviewError,
      shiftError: shiftError,
      activityError: activityError,
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

    // 1. Process Completed Sales (from salesList)
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

    if (businessId.isNotEmpty && c != null) {
      // 2. Recent Held Sales
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
        debugPrint('Recent held sales activity query warning: $e');
      }

      // 3. Recent Shifts
      try {
        final shiftRes = await c
            .from('shifts')
            .select('id, status, start_time, end_time, created_at')
            .eq('business_id', businessId)
            .eq('employee_id', userId)
            .order('created_at', ascending: false)
            .limit(3);

        for (var sh in (shiftRes as List<dynamic>? ?? [])) {
          final startTime = DateTime.parse(sh['start_time'].toString()).toLocal();
          activities.add(RecentActivityModel(
            id: '${sh['id']}_start',
            title: 'Shift Session Started',
            details: 'Shift session opened',
            timestamp: startTime,
            icon: Icons.access_time,
            iconColor: const Color(0xFF003366),
            type: 'shift',
          ));

          if (sh['end_time'] != null) {
            final endTime = DateTime.parse(sh['end_time'].toString()).toLocal();
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
        debugPrint('Recent shift activity query warning: $e');
      }
    }

    // Sort all activities by timestamp descending
    activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return activities.take(5).toList();
  }

  /// Starts a new active cashier shift and records attendance if missing.
  Future<ShiftModel> startShift({double openingFloat = 150.0}) async {
    final c = client;
    final user = c?.auth.currentUser;
    final now = DateTime.now();

    if (!SupabaseConfig.isConfigured || c == null || user == null) {
      _demoActiveShift = ShiftModel(
        id: 'demo-shift-${now.millisecondsSinceEpoch}',
        businessId: 'demo-business',
        employeeId: 'demo-user',
        startTime: now,
        openingFloat: openingFloat,
        status: 'active',
      );
      _demoAttendance = AttendanceModel(
        id: 'demo-att-${now.millisecondsSinceEpoch}',
        businessId: 'demo-business',
        employeeId: 'demo-user',
        reportingTime: now.subtract(const Duration(minutes: 15)),
        status: 'present',
        workDate: _formatWorkDate(now),
      );
      return _demoActiveShift!;
    }

    return startShiftOnLogin(user.id, openingFloat: openingFloat);
  }

  /// Ends the specified active cashier shift.
  Future<void> endShift(String shiftId) async {
    final c = client;
    final now = DateTime.now();

    if (!SupabaseConfig.isConfigured || c == null) {
      _demoActiveShift = null;
      return;
    }

    try {
      await c.from('shifts').update({
        'end_time': now.toIso8601String(),
        'status': 'ended',
      }).eq('id', shiftId);
    } catch (e) {
      _demoActiveShift = null;
      _logErrorDetails(
        step: 'endShift',
        table: 'shifts',
        userId: c.auth.currentUser?.id ?? '',
        businessId: '',
        error: e,
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

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'held_sales',
        callback: (payload) => onDataChanged(),
      );

      channel.subscribe();
      return channel;
    } catch (_) {
      return null;
    }
  }

  CashierDashboardData _getDemoDashboardData(User? user) {
    final email = user?.email ?? 'cashier@flexpos.com';
    final nameFromEmail = email.split('@').first;
    final formattedName = nameFromEmail.isEmpty
        ? 'Cashier'
        : nameFromEmail[0].toUpperCase() + nameFromEmail.substring(1);

    return CashierDashboardData(
      userId: user?.id ?? 'demo-user',
      fullName: formattedName,
      email: email,
      role: 'EMPLOYEE',
      position: 'CASHIER',
      terminalId: 'POS-TERM-01',
      todaySales: 0.0,
      todayEarnings: 0.0,
      todayBills: 0,
      activeShift: _demoActiveShift,
      todayAttendance: _demoAttendance,
      recentActivities: const [],
    );
  }
}
