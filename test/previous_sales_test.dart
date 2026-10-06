import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/models/completed_sale_model.dart';
import 'package:flex_pos/models/sale_item_model.dart';
import 'package:flex_pos/services/sale_service.dart';
import 'package:flex_pos/services/exceptions.dart';

void main() {
  group('CompletedSaleModel Tests', () {
    test('calculates item count correctly and parses fields', () {
      const item1 = SaleItem(
        id: 'si1',
        saleId: 's1',
        productNameSnapshot: 'Amul Milk 1L',
        skuSnapshot: 'DAI002',
        quantity: 2,
        unitPrice: 45.20,
        lineTotal: 90.40,
      );

      const item2 = SaleItem(
        id: 'si2',
        saleId: 's1',
        productNameSnapshot: 'Bread',
        skuSnapshot: 'BAK001',
        quantity: 1,
        unitPrice: 40.00,
        lineTotal: 40.00,
      );

      final sale = CompletedSaleModel(
        id: 's1',
        businessId: 'b1',
        branchId: 'br1',
        employeeId: 'emp1',
        invoiceNumber: 'INV-20260930-A81F2C',
        subtotal: 130.40,
        discount: 0.0,
        tax: 0.0,
        total: 130.40,
        status: 'completed',
        paymentMethod: 'cash',
        createdAt: DateTime.now(),
        items: const [item1, item2],
      );

      expect(sale.itemCount, 3); // 2 + 1
      expect(sale.invoiceNumber, 'INV-20260930-A81F2C');
      expect(sale.paymentMethod, 'cash');
      expect(sale.total, 130.40);
    });
  });

  group('SaleService Previous Sales Tests', () {
    test('throws SaleException when Supabase is unconfigured', () {
      final saleService = SaleService();
      expect(
        () => saleService.getCompletedSalesForCashier(),
        throwsA(isA<SaleException>().having(
          (e) => e.message,
          'message',
          contains('Supabase is not configured'),
        )),
      );
    });
  });
}
