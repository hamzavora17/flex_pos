import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/models/held_sale_model.dart';
import 'package:flex_pos/models/product_model.dart';
import 'package:flex_pos/services/held_sale_service.dart';
import 'package:flex_pos/features/cashier/presentation/new_sale_screen.dart';

void main() {
  group('HeldSaleModel Tests', () {
    test('calculates total value and item count correctly', () {
      final item1 = HeldSaleItemModel(
        id: 'i1',
        heldSaleId: 'hs1',
        productId: 'p1',
        productNameSnapshot: 'Amul Butter 500g',
        quantity: 2,
        unitPrice: 285.00,
      );

      final item2 = HeldSaleItemModel(
        id: 'i2',
        heldSaleId: 'hs1',
        productId: 'p2',
        productNameSnapshot: 'Cheddar Cheese Slices 200g',
        quantity: 1,
        unitPrice: 155.00,
      );

      final heldSale = HeldSaleModel(
        id: 'hs1',
        businessId: 'b1',
        employeeId: 'e1',
        referenceNumber: 'HOLD-1041',
        createdAt: DateTime.now(),
        items: [item1, item2],
      );

      expect(heldSale.itemCount, 3); // 2 + 1
      expect(heldSale.totalValue, 725.00); // (285*2) + (155*1)
    });
  });

  group('HeldSaleService Security Tests', () {
    test('holdSale fails when unauthenticated or unconfigured without creating fake fallback records', () async {
      final heldSaleService = HeldSaleService();

      const product = Product(
        id: 'p1',
        businessId: 'b1',
        name: 'Amul Milk 1L',
        price: 68.0,
      );

      final cart = [
        CartItemModel(product: product, quantity: 3, maxStock: 20),
      ];

      expect(
        () => heldSaleService.holdSale(branchId: 'br1', cartItems: cart),
        throwsA(isA<Exception>()),
      );
    });

    test('getHeldSales fails when unauthenticated or unconfigured', () async {
      final heldSaleService = HeldSaleService();
      expect(
        () => heldSaleService.getHeldSales(),
        throwsA(isA<Exception>()),
      );
    });
  });
}
