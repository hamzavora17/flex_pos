import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/models/admin_models.dart';
import 'package:flex_pos/models/user_role.dart';
import 'package:flex_pos/services/admin_dashboard_service.dart';
import 'package:flex_pos/services/admin_user_service.dart';
import 'package:flex_pos/services/exceptions.dart';

void main() {
  group('AdminUserService Unit Tests', () {
    late AdminUserService service;
    const sampleValidUserUuid = 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d';

    setUp(() {
      service = AdminUserService(client: null);
    });

    test('assignUserRole throws FlexPOSException when targetUserId is empty', () {
      expect(
        () => service.assignUserRole(
          targetUserId: '   ',
          role: UserRole.manager,
        ),
        throwsA(isA<FlexPOSException>().having(
          (e) => e.message,
          'message',
          contains('Target User ID cannot be empty'),
        )),
      );
    });

    test('assignUserRole throws FlexPOSException when targetUserId is an invalid UUID format', () {
      expect(
        () => service.assignUserRole(
          targetUserId: 'invalid-user-uuid',
          role: UserRole.manager,
        ),
        throwsA(isA<FlexPOSException>().having(
          (e) => e.message,
          'message',
          contains('Invalid Target User ID format'),
        )),
      );
    });

    test('assignUserRole throws FlexPOSException if Admin role promotion is attempted', () {
      expect(
        () => service.assignUserRole(
          targetUserId: sampleValidUserUuid,
          role: UserRole.admin,
        ),
        throwsA(isA<FlexPOSException>().having(
          (e) => e.message,
          'message',
          contains('restricted to store staff roles'),
        )),
      );
    });

    test('assignUserRole simulates manager role assignment when Supabase is unconfigured', () async {
      final result = await service.assignUserRole(
        targetUserId: sampleValidUserUuid,
        role: UserRole.manager,
      );

      expect(result['success'], isTrue);
      expect(result['profile_id'], sampleValidUserUuid);
      expect(result['role'], 'manager');
      expect(result['position'], 'manager');
    });

    test('getAssignableUsers throws FlexPOSException when Supabase is unconfigured', () {
      expect(
        () => service.getAssignableUsers(),
        throwsA(isA<FlexPOSException>().having(
          (e) => e.message,
          'message',
          contains('Supabase is not configured'),
        )),
      );
    });
  });

  group('AdminUserSummary & AdminDashboardService Tests', () {
    test('AdminUserSummary.fromMap correctly parses profiles and employee business data', () {
      final map = {
        'id': 'usr-123',
        'email': 'cashier@flexpos.com',
        'full_name': 'Cashier One',
        'role': 'cashier',
        'created_at': '2026-01-01T10:00:00Z',
        'employees': [
          {
            'status': 'active',
            'businesses': {
              'business_name': 'Main Branch POS',
            }
          }
        ]
      };

      final summary = AdminUserSummary.fromMap(map);

      expect(summary.id, 'usr-123');
      expect(summary.email, 'cashier@flexpos.com');
      expect(summary.fullName, 'Cashier One');
      expect(summary.role, 'cashier');
      expect(summary.status, 'active');
      expect(summary.businessName, 'Main Branch POS');
    });

    test('AdminUserSummary.fromMap correctly parses 1-to-1 embedded employee Map (_JsonMap)', () {
      final map = {
        'id': 'usr-789',
        'email': 'staff@flexpos.com',
        'full_name': 'Staff Member',
        'role': 'cashier',
        'created_at': '2026-01-01T10:00:00Z',
        'employees': {
          'status': 'active',
          'businesses': {
            'business_name': 'Downtown Branch',
          }
        }
      };

      final summary = AdminUserSummary.fromMap(map);

      expect(summary.id, 'usr-789');
      expect(summary.email, 'staff@flexpos.com');
      expect(summary.fullName, 'Staff Member');
      expect(summary.role, 'cashier');
      expect(summary.status, 'active');
      expect(summary.businessName, 'Downtown Branch');
    });

    test('AdminUserSummary.fromMap falls back to email prefix when full_name is empty', () {
      final map = {
        'id': 'usr-456',
        'email': 'manager@flexpos.com',
        'full_name': '  ',
        'role': 'manager',
        'created_at': '2026-01-01T10:00:00Z',
      };

      final summary = AdminUserSummary.fromMap(map);

      expect(summary.fullName, 'manager');
      expect(summary.role, 'manager');
      expect(summary.businessName, 'FlexPOS');
    });

    test('AdminDashboardService.getAdminUsers throws FlexPOSException when Supabase is unconfigured', () {
      final adminService = AdminDashboardService(client: null);

      expect(
        () => adminService.getAdminUsers(),
        throwsA(isA<FlexPOSException>().having(
          (e) => e.message,
          'message',
          contains('Supabase is not configured'),
        )),
      );
    });
  });
}
