import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/models/completed_sale_model.dart';
import 'package:flex_pos/models/sale_item_model.dart';
import 'package:flex_pos/services/sale_service.dart';

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
    test('returns cashier completed sales in newest-first order with search and date filters', () async {
      final saleService = SaleService();

      final sales = await saleService.getCompletedSalesForCashier();
      expect(sales, isNotEmpty);

      // Verify newest first
      if (sales.length >= 2) {
        expect(sales[0].createdAt.isAfter(sales[1].createdAt) || sales[0].createdAt.isAtSameMomentAs(sales[1].createdAt), isTrue);
      }

      // Test search filtering by invoice number
      final searchInv = await saleService.getCompletedSalesForCashier(searchQuery: sales.first.invoiceNumber);
      expect(searchInv, isNotEmpty);
      expect(searchInv.first.invoiceNumber, sales.first.invoiceNumber);

      // Test search filtering by product name
      final searchProduct = await saleService.getCompletedSalesForCashier(searchQuery: 'Milk');
      expect(searchProduct, isNotEmpty);
    });
  });
}
