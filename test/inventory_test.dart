import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/models/inventory_model.dart';
import 'package:flex_pos/services/inventory_service.dart';
import 'package:flex_pos/services/exceptions.dart';

void main() {
  group('Inventory Model Tests', () {
    test('InventoryItem.fromMap correctly parses Supabase row JSON', () {
      final map = {
        'id': 'inv-101',
        'product_id': 'prod-789',
        'business_id': 'biz-456',
        'branch_id': 'branch-01',
        'quantity': 50,
        'low_stock_threshold': 10,
        'created_at': '2026-01-01T12:00:00Z',
        'updated_at': '2026-01-02T12:00:00Z',
      };

      final item = InventoryItem.fromMap(map);

      expect(item.id, 'inv-101');
      expect(item.productId, 'prod-789');
      expect(item.businessId, 'biz-456');
      expect(item.branchId, 'branch-01');
      expect(item.quantity, 50);
      expect(item.lowStockThreshold, 10);
      expect(item.createdAt, isNotNull);
      expect(item.updatedAt, isNotNull);
    });

    test('InventoryItem.toMap produces valid map for Supabase persistence', () {
      const item = InventoryItem(
        id: 'inv-101',
        productId: 'prod-789',
        businessId: 'biz-456',
        quantity: 25,
        lowStockThreshold: 5,
      );

      final map = item.toMap();

      expect(map['id'], 'inv-101');
      expect(map['product_id'], 'prod-789');
      expect(map['business_id'], 'biz-456');
      expect(map['quantity'], 25);
      expect(map['low_stock_threshold'], 5);
    });

    test('InventoryItem.copyWith enforces business ID isolation', () {
      const untrustedItem = InventoryItem(
        id: 'inv-1',
        productId: 'prod-1',
        businessId: 'untrusted-biz-id',
        quantity: 10,
      );

      final isolatedItem = untrustedItem.copyWith(businessId: 'resolved-auth-biz-id');

      expect(isolatedItem.businessId, 'resolved-auth-biz-id');
      expect(isolatedItem.toMap()['business_id'], 'resolved-auth-biz-id');
    });
  });

  group('Inventory Service Validation & Security Tests', () {
    test('InventoryService throws InventoryException for empty product ID', () {
      final service = InventoryService();

      expect(
        () => service.createInventory(const InventoryItem(
          id: '',
          productId: '   ',
          businessId: 'biz-1',
          quantity: 10,
        )),
        throwsA(isA<InventoryException>().having(
          (e) => e.message,
          'message',
          contains('Product ID is required'),
        )),
      );
    });

    test('InventoryService throws InventoryException for negative low stock threshold', () {
      final service = InventoryService();

      expect(
        () => service.createInventory(const InventoryItem(
          id: '',
          productId: 'prod-1',
          businessId: 'biz-1',
          quantity: 10,
          lowStockThreshold: -1,
        )),
        throwsA(isA<InventoryException>().having(
          (e) => e.message,
          'message',
          contains('Low stock threshold cannot be negative'),
        )),
      );
    });

    test('InventoryService throws InventoryException when updating without ID', () {
      final service = InventoryService();

      expect(
        () => service.updateInventory(const InventoryItem(
          id: '  ',
          productId: 'prod-1',
          businessId: 'biz-1',
          quantity: 10,
        )),
        throwsA(isA<InventoryException>().having(
          (e) => e.message,
          'message',
          contains('Inventory ID is required'),
        )),
      );
    });

    test('InventoryService throws InventoryException for empty product ID in adjustStock', () {
      final service = InventoryService();

      expect(
        () => service.adjustStock(productId: '  ', branchId: 'branch-1', adjustmentQuantity: 5),
        throwsA(isA<InventoryException>().having(
          (e) => e.message,
          'message',
          contains('Product ID is required'),
        )),
      );
    });

    test('InventoryService throws InventoryException for empty inventory ID in deleteInventory', () {
      final service = InventoryService();

      expect(
        () => service.deleteInventory('   '),
        throwsA(isA<InventoryException>().having(
          (e) => e.message,
          'message',
          contains('Inventory ID is required'),
        )),
      );
    });
  });
}
