import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/services/sale_service.dart';
import 'package:flex_pos/services/exceptions.dart';

void main() {
  group('SaleService Validation Tests', () {
    late SaleService saleService;

    setUp(() {
      // Initialize with null client to test synchronous validation logic
      // before it reaches the actual Supabase client.
      saleService = SaleService(client: null);
    });

    test('checkout rejects empty cart', () async {
      expect(
        () => saleService.checkout(
          branchId: 'test-branch-id',
          items: [],
          paymentMethod: 'cash',
        ),
        throwsA(isA<SaleException>().having(
          (e) => e.message,
          'message',
          contains('Cart cannot be empty'),
        )),
      );
    });

    test('checkout rejects negative or zero quantity', () async {
      expect(
        () => saleService.checkout(
          branchId: 'test-branch-id',
          items: [
            const CartItem(productId: 'prod-1', quantity: 0),
          ],
          paymentMethod: 'cash',
        ),
        throwsA(isA<SaleException>().having(
          (e) => e.message,
          'message',
          contains('Quantity must be positive'),
        )),
      );

      expect(
        () => saleService.checkout(
          branchId: 'test-branch-id',
          items: [
            const CartItem(productId: 'prod-2', quantity: -5),
          ],
          paymentMethod: 'upi',
        ),
        throwsA(isA<SaleException>().having(
          (e) => e.message,
          'message',
          contains('Quantity must be positive'),
        )),
      );
    });

    test('checkout rejects negative discount', () async {
      expect(
        () => saleService.checkout(
          branchId: 'test-branch-id',
          items: [
            const CartItem(productId: 'prod-1', quantity: 1),
          ],
          paymentMethod: 'cash',
          discount: -10.0,
        ),
        throwsA(isA<SaleException>().having(
          (e) => e.message,
          'message',
          contains('Discount cannot be negative'),
        )),
      );
    });

    test('checkout rejects unsupported payment method', () async {
      expect(
        () => saleService.checkout(
          branchId: 'test-branch-id',
          items: [
            const CartItem(productId: 'prod-1', quantity: 1),
          ],
          paymentMethod: 'crypto', // Not supported
        ),
        throwsA(isA<SaleException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported payment method'),
        )),
      );
    });
  });
}
