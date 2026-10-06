import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/models/user_role.dart';

void main() {
  group('UserRole Enum Parsing & Properties', () {
    test('fromString parses admin correctly', () {
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('ADMIN'), UserRole.admin);
      expect(UserRole.fromString(' Admin '), UserRole.admin);
      expect(UserRole.admin.isAdmin, isTrue);
      expect(UserRole.admin.isManager, isFalse);
      expect(UserRole.admin.isCashier, isFalse);
      expect(UserRole.admin.label, 'Admin');
      expect(UserRole.admin.toDbString(), 'admin');
    });

    test('fromString parses manager correctly', () {
      expect(UserRole.fromString('manager'), UserRole.manager);
      expect(UserRole.fromString('MANAGER'), UserRole.manager);
      expect(UserRole.fromString(' Manager '), UserRole.manager);
      expect(UserRole.manager.isManager, isTrue);
      expect(UserRole.manager.isAdmin, isFalse);
      expect(UserRole.manager.isCashier, isFalse);
      expect(UserRole.manager.label, 'Manager');
      expect(UserRole.manager.toDbString(), 'manager');
    });

    test('fromString parses cashier and legacy employee correctly', () {
      expect(UserRole.fromString('cashier'), UserRole.cashier);
      expect(UserRole.fromString('CASHIER'), UserRole.cashier);
      expect(UserRole.fromString('employee'), UserRole.cashier);
      expect(UserRole.fromString('EMPLOYEE'), UserRole.cashier);
      expect(UserRole.fromString(null), isNull);
      expect(UserRole.fromString(''), isNull);
      expect(UserRole.fromString('unknown_role'), isNull);
      expect(UserRole.cashier.isCashier, isTrue);
      expect(UserRole.cashier.isAdmin, isFalse);
      expect(UserRole.cashier.isManager, isFalse);
      expect(UserRole.cashier.label, 'Cashier');
      expect(UserRole.cashier.toDbString(), 'cashier');
    });

    test('DB role string to UserRole mapping verification', () {
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('manager'), UserRole.manager);
      expect(UserRole.fromString('cashier'), UserRole.cashier);
      expect(UserRole.fromString('employee'), UserRole.cashier);
    });
  });

  group('Role Security & Privilege Escalation Checks', () {
    test('Cashier / Employee cannot self-promote to Manager or Admin', () {
      const cashier = UserRole.cashier;
      expect(cashier.canManageRoles, isFalse);
      expect(cashier.canPromoteTo(UserRole.manager), isFalse);
      expect(cashier.canPromoteTo(UserRole.admin), isFalse);
      expect(cashier.canPromoteTo(UserRole.cashier), isFalse);
    });

    test('Manager cannot self-promote to Admin', () {
      const manager = UserRole.manager;
      expect(manager.canManageRoles, isFalse);
      expect(manager.canPromoteTo(UserRole.admin), isFalse);
      expect(manager.canPromoteTo(UserRole.manager), isFalse);
    });

    test('Admin has full role management authority', () {
      const admin = UserRole.admin;
      expect(admin.canManageRoles, isTrue);
      expect(admin.canPromoteTo(UserRole.manager), isTrue);
      expect(admin.canPromoteTo(UserRole.cashier), isTrue);
      expect(admin.canPromoteTo(UserRole.admin), isTrue);
    });
  });
}
