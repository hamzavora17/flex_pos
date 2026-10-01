import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/models/return_model.dart';
import 'package:flex_pos/services/return_service.dart';

void main() {
  group('ReturnItemSelection & Inspection Tests', () {
    test('calculates line refund correctly', () {
      final selection = ReturnItemSelection(
        productId: 'p1',
        productName: 'Amul Butter 500g',
        selectedQuantity: 2,
        maxQuantity: 5,
        unitPrice: 285.00,
      );

      expect(selection.lineRefund, 570.00);
    });

    test('rejects return if product is damaged', () async {
      final returnService = ReturnService();

      final items = [
        ReturnItemSelection(
          productId: 'p1',
          productName: 'Amul Milk 1L',
          selectedQuantity: 1,
          maxQuantity: 2,
          unitPrice: 45.20,
        ),
      ];

      final result = await returnService.processReturn(
        saleId: 's1',
        items: items,
        isDamaged: true, // Damaged inspection = YES
      );

      expect(result.isApproved, isFalse);
      expect(result.refundAmount, 0.0);
      expect(result.message, contains('Damaged or broken items are not eligible'));
    });

    test('approves return, calculates refund and restores inventory if product is not damaged', () async {
      final returnService = ReturnService();

      final items = [
        ReturnItemSelection(
          productId: 'p1',
          productName: 'Amul Milk 1L',
          selectedQuantity: 2,
          maxQuantity: 2,
          unitPrice: 45.20,
        ),
      ];

      final result = await returnService.processReturn(
        saleId: 's1',
        items: items,
        isDamaged: false, // Damaged inspection = NO (Intact)
      );

      expect(result.isApproved, isTrue);
      expect(result.refundAmount, 90.40); // 45.20 * 2
      expect(result.message, contains('Return Approved'));
    });
  });
}
