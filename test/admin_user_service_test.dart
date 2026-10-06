import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/models/user_role.dart';
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
}
