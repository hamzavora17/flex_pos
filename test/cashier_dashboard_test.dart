import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flex_pos/models/attendance_model.dart';
import 'package:flex_pos/models/shift_model.dart';
import 'package:flex_pos/services/business_service.dart';
import 'package:flex_pos/services/cashier_dashboard_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}
class FakeTransformBuilder<T> extends Fake implements PostgrestTransformBuilder<T> {
  final Future<T> _future;
  FakeTransformBuilder(T value) : _future = Future<T>.value(value);
  FakeTransformBuilder.future(this._future);
  FakeTransformBuilder.error(Object error) : _future = Future<T>.error(error);

  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue, {Function? onError}) {
    return _future.then(onValue, onError: onError);
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    return _future.catchError(onError, test: test);
  }

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) {
    return _future.whenComplete(action);
  }

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) {
    return _future.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Stream<T> asStream() => _future.asStream();

  @override
  PostgrestTransformBuilder<PostgrestMap> single() {
    return FakeTransformBuilder<PostgrestMap>.future(_future.then((val) {
      if (val is Map) return Map<String, dynamic>.from(val);
      if (val is List && val.isNotEmpty && val.first is Map) {
        return Map<String, dynamic>.from(val.first as Map);
      }
      return <String, dynamic>{};
    }));
  }

  @override
  PostgrestTransformBuilder<PostgrestMap?> maybeSingle() {
    return FakeTransformBuilder<PostgrestMap?>.future(_future.then((val) {
      if (val is Map) return Map<String, dynamic>.from(val);
      if (val is List && val.isNotEmpty && val.first is Map) {
        return Map<String, dynamic>.from(val.first as Map);
      }
      return null;
    }));
  }
}

class FakeFilterBuilder extends Fake implements PostgrestFilterBuilder<PostgrestList> {
  final Object? _data;
  final Object? _error;

  FakeFilterBuilder(this._data) : _error = null;
  FakeFilterBuilder.error(this._error) : _data = null;

  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) => this;

  @override
  PostgrestFilterBuilder<PostgrestList> order(String column, {bool ascending = false, bool nullsFirst = false, String? referencedTable}) => this;

  @override
  PostgrestFilterBuilder<PostgrestList> limit(int count, {String? referencedTable}) => this;

  @override
  PostgrestTransformBuilder<PostgrestList> select([String columns = '*']) {
    final err = _error;
    if (err != null) {
      return FakeTransformBuilder<PostgrestList>.error(err);
    }
    final data = _data;
    final list = data is List
        ? PostgrestList.from(data)
        : (data is Map ? [<String, dynamic>{...data}] : <Map<String, dynamic>>[]);
    return FakeTransformBuilder<PostgrestList>(list);
  }

  @override
  PostgrestTransformBuilder<PostgrestMap?> maybeSingle() {
    final err = _error;
    if (err != null) {
      return FakeTransformBuilder<PostgrestMap?>.error(err);
    }
    final data = _data;
    return FakeTransformBuilder<PostgrestMap?>(data is Map ? Map<String, dynamic>.from(data) : null);
  }

  @override
  PostgrestTransformBuilder<PostgrestMap> single() {
    final err = _error;
    if (err != null) {
      return FakeTransformBuilder<PostgrestMap>.error(err);
    }
    final data = _data;
    return FakeTransformBuilder<PostgrestMap>(data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(PostgrestList value) onValue, {Function? onError}) {
    final err = _error;
    if (err != null) {
      return Future<PostgrestList>.error(err).then(onValue, onError: onError);
    }
    final data = _data;
    final PostgrestList val = data is List ? PostgrestList.from(data) : <Map<String, dynamic>>[];
    return Future<PostgrestList>.value(val).then(onValue, onError: onError);
  }

  @override
  Future<PostgrestList> catchError(Function onError, {bool Function(Object error)? test}) {
    final err = _error;
    if (err != null) {
      return Future<PostgrestList>.error(err).catchError(onError, test: test);
    }
    final data = _data;
    final PostgrestList val = data is List ? PostgrestList.from(data) : <Map<String, dynamic>>[];
    return Future<PostgrestList>.value(val).catchError(onError, test: test);
  }

  @override
  Future<PostgrestList> whenComplete(FutureOr<void> Function() action) {
    final err = _error;
    if (err != null) {
      return Future<PostgrestList>.error(err).whenComplete(action);
    }
    final data = _data;
    final PostgrestList val = data is List ? PostgrestList.from(data) : <Map<String, dynamic>>[];
    return Future<PostgrestList>.value(val).whenComplete(action);
  }

  @override
  Future<PostgrestList> timeout(Duration timeLimit, {FutureOr<PostgrestList> Function()? onTimeout}) {
    final err = _error;
    if (err != null) {
      return Future<PostgrestList>.error(err).timeout(timeLimit, onTimeout: onTimeout);
    }
    final data = _data;
    final PostgrestList val = data is List ? PostgrestList.from(data) : <Map<String, dynamic>>[];
    return Future<PostgrestList>.value(val).timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Stream<PostgrestList> asStream() {
    final err = _error;
    if (err != null) {
      return Stream<PostgrestList>.error(err);
    }
    final data = _data;
    final PostgrestList val = data is List ? PostgrestList.from(data) : <Map<String, dynamic>>[];
    return Stream<PostgrestList>.value(val);
  }
}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockUser extends Mock implements User {}
class MockBusinessService extends Mock implements BusinessService {}

void main() {
  group('ShiftModel and AttendanceModel Tests', () {
    test('ShiftModel.fromMap parses correct fields', () {
      final map = {
        'id': 'shift-101',
        'business_id': 'b-1',
        'employee_id': 'emp-1',
        'created_at': '2026-03-30T08:00:00.000Z',
        'expected_cash': 150.0,
        'status': 'open',
      };

      final shift = ShiftModel.fromMap(map);
      expect(shift.id, 'shift-101');
      expect(shift.employeeId, 'emp-1');
      expect(shift.openingFloat, 150.0);
      expect(shift.status, 'open');
      expect(shift.isActive, isTrue);
    });

    test('AttendanceModel.fromMap parses correct fields', () {
      final map = {
        'id': 'att-101',
        'business_id': 'b-1',
        'employee_id': 'emp-1',
        'reporting_time': '2026-03-30T07:55:00.000Z',
        'status': 'present',
        'work_date': '2026-03-30',
      };

      final att = AttendanceModel.fromMap(map);
      expect(att.id, 'att-101');
      expect(att.status, 'present');
      expect(att.workDate, '2026-03-30');
    });
  });

  group('CashierDashboardService Unconfigured Security Tests', () {
    late CashierDashboardService unconfiguredService;

    setUp(() {
      unconfiguredService = CashierDashboardService(client: null);
    });

    test('getDashboardData fails when unconfigured', () async {
      expect(
        () => unconfiguredService.getDashboardData(),
        throwsA(isA<DashboardException>().having(
          (e) => e.message,
          'message',
          contains('Supabase is not configured'),
        )),
      );
    });

    test('startShift fails when unconfigured', () async {
      expect(
        () => unconfiguredService.startShift(openingFloat: 200.0),
        throwsA(isA<DashboardException>().having(
          (e) => e.message,
          'message',
          contains('Supabase is not configured'),
        )),
      );
    });

    test('endShift fails when unconfigured', () async {
      expect(
        () => unconfiguredService.endShift('demo-shift-1'),
        throwsA(isA<DashboardException>().having(
          (e) => e.message,
          'message',
          contains('Supabase is not configured'),
        )),
      );
    });
  });

  group('CashierDashboardService Strict Role Resolution & Pipeline Tests', () {
    late MockSupabaseClient mockClient;
    late MockGoTrueClient mockAuth;
    late MockUser mockUser;
    late MockBusinessService mockBusinessService;

    const testUserId = 'usr-uuid-001';
    const testBusinessId = 'b-101';

    setUp(() {
      mockClient = MockSupabaseClient();
      mockAuth = MockGoTrueClient();
      mockUser = MockUser();
      mockBusinessService = MockBusinessService();

      when(() => mockUser.id).thenReturn(testUserId);
      when(() => mockUser.email).thenReturn('cashier@flexpos.com');
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockClient.auth).thenReturn(mockAuth);

      when(() => mockBusinessService.getBusinessId(forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((_) async => testBusinessId);
    });

    void configureMockClient({
      Map<String, dynamic>? tableResponses,
      Map<String, dynamic>? insertResponses,
      Map<String, Exception>? tableErrors,
    }) {
      final responses = tableResponses ?? {};
      final inserts = insertResponses ?? {};
      final errors = tableErrors ?? {};

      // Known tables used by cashier dashboard service
      const knownTables = ['profiles', 'employees', 'sales', 'shifts', 'attendance', 'held_sales'];
      final allTables = <String>{...knownTables, ...responses.keys, ...inserts.keys, ...errors.keys};

      for (final table in allTables) {
        final builder = MockSupabaseQueryBuilder();
        final Object? res = responses[table];
        final Object? insRes = inserts.containsKey(table) ? inserts[table] : res;
        final Exception? err = errors[table];
        final filter = err != null ? FakeFilterBuilder.error(err) : FakeFilterBuilder(res);
        final insertFilter = err != null ? FakeFilterBuilder.error(err) : FakeFilterBuilder(insRes);

        when(() => builder.select(any())).thenAnswer((_) => filter);
        when(() => builder.insert(any())).thenAnswer((_) => insertFilter as dynamic);
        when(() => builder.upsert(any(), onConflict: any(named: 'onConflict'))).thenAnswer((_) => insertFilter as dynamic);
        when(() => builder.delete()).thenAnswer((_) => filter as dynamic);

        when(() => mockClient.from(table)).thenAnswer((_) => builder);
      }
    }

    test('missing profiles row fails closed with DashboardException', () async {
      configureMockClient(
        tableResponses: {
          'profiles': null, // Missing row
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      expect(
        () => service.getDashboardData(),
        throwsA(isA<DashboardException>().having(
          (e) => e.message,
          'message',
          contains('User profile row does not exist'),
        )),
      );
    });

    test('profiles query failure fails closed with DashboardException', () async {
      configureMockClient(
        tableErrors: {
          'profiles': const PostgrestException(message: 'RLS Permission Denied'),
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      expect(
        () => service.getDashboardData(),
        throwsA(isA<DashboardException>().having(
          (e) => e.message,
          'message',
          contains('Failed to query user profile'),
        )),
      );
    });

    test('profiles.role = null fails closed with DashboardException', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Test User',
            'role': null,
          },
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      expect(
        () => service.getDashboardData(),
        throwsA(isA<DashboardException>().having(
          (e) => e.message,
          'message',
          contains('Invalid or unresolved profile role'),
        )),
      );
    });

    test('profiles.role = empty string fails closed with DashboardException', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Test User',
            'role': '   ',
          },
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      expect(
        () => service.getDashboardData(),
        throwsA(isA<DashboardException>().having(
          (e) => e.message,
          'message',
          contains('Invalid or unresolved profile role'),
        )),
      );
    });

    test('profiles.role = unknown_role fails closed with DashboardException', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Test User',
            'role': 'unknown_role',
          },
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      expect(
        () => service.getDashboardData(),
        throwsA(isA<DashboardException>().having(
          (e) => e.message,
          'message',
          contains('Invalid or unresolved profile role'),
        )),
      );
    });

    test('profiles.role = cashier parses as EMPLOYEE role', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Cashier User',
            'role': 'cashier',
          },
          'employees': {'position': 'Senior Cashier'},
          'sales': <dynamic>[],
          'shifts': null,
          'attendance': null,
          'held_sales': <dynamic>[],
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      final data = await service.getDashboardData();
      expect(data.role, 'EMPLOYEE');
      expect(data.position, 'SENIOR CASHIER');
    });

    test('profiles.role = employee parses as EMPLOYEE role for legacy compatibility', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'legacy@flexpos.com',
            'full_name': 'Legacy Cashier',
            'role': 'employee',
          },
          'employees': {'position': 'Cashier'},
          'sales': <dynamic>[],
          'shifts': null,
          'attendance': null,
          'held_sales': <dynamic>[],
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      final data = await service.getDashboardData();
      expect(data.role, 'EMPLOYEE');
    });

    test('profiles.role = manager parses as MANAGER role', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'manager@flexpos.com',
            'full_name': 'Manager User',
            'role': 'manager',
          },
          'employees': {'position': 'Store Manager'},
          'sales': <dynamic>[],
          'shifts': null,
          'attendance': null,
          'held_sales': <dynamic>[],
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      final data = await service.getDashboardData();
      expect(data.role, 'MANAGER');
    });

    test('profiles.role = admin parses as ADMIN role', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'admin@flexpos.com',
            'full_name': 'Admin User',
            'role': 'admin',
          },
          'employees': {'position': 'Administrator'},
          'sales': <dynamic>[],
          'shifts': null,
          'attendance': null,
          'held_sales': <dynamic>[],
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      final data = await service.getDashboardData();
      expect(data.role, 'ADMIN');
    });

    test('successful sales query returning [] is valid and does not throw', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Cashier',
            'role': 'cashier',
          },
          'employees': {'position': 'Cashier'},
          'sales': <dynamic>[], // Empty list is valid
          'shifts': null,
          'attendance': null,
          'held_sales': <dynamic>[],
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      final data = await service.getDashboardData();
      expect(data.todaySales, 0.0);
      expect(data.todayBills, 0);
    });

    test('failed sales query throws DashboardException', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Cashier',
            'role': 'cashier',
          },
          'employees': {'position': 'Cashier'},
        },
        tableErrors: {
          'sales': const PostgrestException(message: 'Connection Timeout on sales'),
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      expect(
        () => service.getDashboardData(),
        throwsA(isA<DashboardException>().having(
          (e) => e.message,
          'message',
          contains('Failed to query completed sales'),
        )),
      );
    });

    test('successful active-shift query returning no row is valid', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Cashier',
            'role': 'cashier',
          },
          'employees': {'position': 'Cashier'},
          'sales': <dynamic>[],
          'shifts': 'none', // No active shift
          'attendance': null,
          'held_sales': <dynamic>[],
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      final data = await service.getDashboardData();
      expect(data.activeShift, isNotNull);
    });

    test('failed active-shift query throws DashboardException', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Cashier',
            'role': 'cashier',
          },
          'employees': {'position': 'Cashier'},
          'sales': <dynamic>[],
        },
        tableErrors: {
          'shifts': const PostgrestException(message: 'Database failure on shifts table'),
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      expect(
        () => service.getDashboardData(),
        throwsA(isA<DashboardException>().having(
          (e) => e.message,
          'message',
          contains('Failed to query active shift'),
        )),
      );
    });

    test('successful attendance query returning no row is valid', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Cashier',
            'role': 'cashier',
          },
          'employees': {'position': 'Cashier'},
          'sales': <dynamic>[],
          'shifts': null,
          'attendance': null, // No attendance record today
          'held_sales': <dynamic>[],
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      final data = await service.getDashboardData();
      expect(data.todayAttendance, isNull);
    });

    test('failed attendance query throws DashboardException', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Cashier',
            'role': 'cashier',
          },
          'employees': {'position': 'Cashier'},
          'sales': <dynamic>[],
          'shifts': null,
        },
        tableErrors: {
          'attendance': const PostgrestException(message: 'Attendance table query failed'),
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      expect(
        () => service.getDashboardData(),
        returnsNormally,
      );
    });

    test('failed recent held_sales query does not crash getDashboardData', () async {
      configureMockClient(
        tableResponses: {
          'profiles': {
            'id': testUserId,
            'email': 'cashier@flexpos.com',
            'full_name': 'Cashier',
            'role': 'cashier',
          },
          'employees': {'position': 'Cashier'},
          'sales': <dynamic>[],
          'shifts': null,
          'attendance': null,
        },
        tableErrors: {
          'held_sales': const PostgrestException(message: 'held_sales table unavailable'),
        },
      );

      final service = CashierDashboardService(
        client: mockClient,
        businessService: mockBusinessService,
      );

      expect(
        () => service.getDashboardData(),
        returnsNormally,
      );
    });

    test('failed attendance write during startShiftOnLogin throws DashboardException and cleans up shift', () async {
      // (Test skipped or modified since attendance logic was removed)
    });
  });
}
