import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/core/utils/currency_formatter.dart';
import 'package:flex_pos/models/product_model.dart';

void main() {
  group('CurrencyFormatter Tests', () {
    test('formats numbers as INR currency', () {
      expect(CurrencyFormatter.format(285), '₹285.00');
      expect(CurrencyFormatter.format(1245.5), '₹1,245.50');
      expect(CurrencyFormatter.format(38), '₹38.00');
      expect(CurrencyFormatter.format(870), '₹870.00');
    });

    test('has correct symbol and code', () {
      expect(CurrencyFormatter.symbol, '₹');
      expect(CurrencyFormatter.code, 'INR');
    });
  });

  group('Product Catalog Ordering Logic Tests', () {
    test('in-stock products appear first A-Z, out-of-stock second A-Z', () {
      const pAashirvaad = Product(id: '1', businessId: 'b1', name: 'Aashirvaad Atta 5kg', price: 250);
      const pAmulButter = Product(id: '2', businessId: 'b1', name: 'Amul Butter 500g', price: 285);
      const pBisleri = Product(id: '3', businessId: 'b1', name: 'Bisleri Mineral Water 1L', price: 20);
      const pBread = Product(id: '4', businessId: 'b1', name: 'Bread', price: 40);

      final stockMap = <String, int>{
        '1': 0,  // Aashirvaad Atta is OUT OF STOCK
        '2': 15, // Amul Butter is IN STOCK
        '3': 50, // Bisleri is IN STOCK
        '4': 10, // Bread is IN STOCK
      };

      final products = [pAashirvaad, pAmulButter, pBisleri, pBread];

      products.sort((a, b) {
        final stockA = stockMap[a.id] ?? 0;
        final stockB = stockMap[b.id] ?? 0;
        final hasStockA = stockA > 0;
        final hasStockB = stockB > 0;

        if (hasStockA && !hasStockB) {
          return -1;
        } else if (!hasStockA && hasStockB) {
          return 1;
        } else {
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        }
      });

      // Expected order:
      // In-stock A-Z: Amul Butter, Bisleri, Bread
      // Out-of-stock A-Z: Aashirvaad Atta
      expect(products[0].name, 'Amul Butter 500g');
      expect(products[1].name, 'Bisleri Mineral Water 1L');
      expect(products[2].name, 'Bread');
      expect(products[3].name, 'Aashirvaad Atta 5kg');
    });
  });
}
