import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/models/attendance_model.dart';
import 'package:flex_pos/models/shift_model.dart';
import 'package:flex_pos/services/cashier_dashboard_service.dart';

void main() {
  group('ShiftModel and AttendanceModel Tests', () {
    test('ShiftModel.fromMap parses correct fields', () {
      final map = {
        'id': 'shift-101',
        'business_id': 'b-1',
        'employee_id': 'emp-1',
        'start_time': '2026-03-30T08:00:00.000Z',
        'opening_float': 150.0,
        'status': 'active',
      };

      final shift = ShiftModel.fromMap(map);
      expect(shift.id, 'shift-101');
      expect(shift.businessId, 'b-1');
      expect(shift.employeeId, 'emp-1');
      expect(shift.openingFloat, 150.0);
      expect(shift.status, 'active');
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

  group('CashierDashboardService Demo Mode Tests', () {
    late CashierDashboardService service;

    setUp(() {
      service = CashierDashboardService(client: null);
    });

    test('getDashboardData returns non-null metrics in demo mode', () async {
      final data = await service.getDashboardData();
      expect(data, isNotNull);
      expect(data.terminalId, 'POS-TERM-01');
      expect(data.role, 'EMPLOYEE');
    });

    test('startShift creates an active shift in demo mode', () async {
      final shift = await service.startShift(openingFloat: 200.0);
      expect(shift.isActive, isTrue);
      expect(shift.openingFloat, 200.0);
    });

    test('endShift ends current active shift in demo mode', () async {
      await service.endShift('demo-shift-1');
      final data = await service.getDashboardData();
      expect(data.activeShift, isNull);
    });
  });
}
