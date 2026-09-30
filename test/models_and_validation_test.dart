import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/models/category_model.dart';
import 'package:flex_pos/models/product_model.dart';
import 'package:flex_pos/services/category_service.dart';
import 'package:flex_pos/services/product_service.dart';
import 'package:flex_pos/services/exceptions.dart';

void main() {
  group('Category Model Tests', () {
    test('Category.fromMap correctly parses Supabase row JSON', () {
      final map = {
        'id': 'cat-123',
        'business_id': 'biz-456',
        'name': 'Beverages',
        'description': 'Cold drinks and juices',
        'created_at': '2026-01-01T12:00:00Z',
        'updated_at': '2026-01-02T12:00:00Z',
      };

      final category = Category.fromMap(map);

      expect(category.id, 'cat-123');
      expect(category.businessId, 'biz-456');
      expect(category.name, 'Beverages');
      expect(category.description, 'Cold drinks and juices');
      expect(category.createdAt, isNotNull);
      expect(category.updatedAt, isNotNull);
    });

    test('Category.toMap produces valid map for Supabase insertion', () {
      const category = Category(
        id: 'cat-123',
        businessId: 'biz-456',
        name: 'Snacks',
        description: 'Chips and cookies',
      );

      final map = category.toMap();

      expect(map['id'], 'cat-123');
      expect(map['business_id'], 'biz-456');
      expect(map['name'], 'Snacks');
      expect(map['description'], 'Chips and cookies');
    });
  });

  group('Product Model Tests', () {
    test('Product.fromMap correctly parses Supabase row JSON', () {
      final map = {
        'id': 'prod-789',
        'business_id': 'biz-456',
        'category_id': 'cat-123',
        'name': 'Mineral Water 500ml',
        'sku': 'SKU-WATER-500',
        'barcode': '8901234567890',
        'price': 20.0,
        'cost': 12.5,
        'active': true,
        'unit': 'bottle',
        'min_stock_alert': 10,
        'created_at': '2026-01-01T12:00:00Z',
      };

      final product = Product.fromMap(map);

      expect(product.id, 'prod-789');
      expect(product.businessId, 'biz-456');
      expect(product.categoryId, 'cat-123');
      expect(product.name, 'Mineral Water 500ml');
      expect(product.sku, 'SKU-WATER-500');
      expect(product.barcode, '8901234567890');
      expect(product.price, 20.0);
      expect(product.cost, 12.5);
      expect(product.active, isTrue);
      expect(product.unit, 'bottle');
      expect(product.minStockAlert, 10);
    });

    test('Product.toMap converts empty SKU/barcode strings to null', () {
      const product = Product(
        id: 'prod-1',
        businessId: 'biz-456',
        name: 'Generic Item',
        sku: '   ',
        barcode: '',
        price: 15.0,
      );

      final map = product.toMap();

      expect(map['sku'], isNull);
      expect(map['barcode'], isNull);
      expect(map['price'], 15.0);
      expect(map['name'], 'Generic Item');
    });

    test('Product.copyWith enforces business ID overriding for security isolation', () {
      const untrustedProduct = Product(
        id: 'prod-999',
        businessId: 'untrusted-biz-id',
        name: 'Protected Product',
        price: 99.0,
      );

      final isolatedProduct = untrustedProduct.copyWith(businessId: 'resolved-auth-biz-id');

      expect(isolatedProduct.businessId, 'resolved-auth-biz-id');
      expect(isolatedProduct.toMap()['business_id'], 'resolved-auth-biz-id');
    });
  });

  group('Validation & Security Isolation Tests', () {
    test('CategoryService throws CategoryException when name is empty', () {
      final service = CategoryService();

      expect(
        () => service.createCategory(name: '   ', businessId: 'biz-1'),
        throwsA(isA<CategoryException>().having(
          (e) => e.message,
          'message',
          contains('cannot be empty'),
        )),
      );
    });

    test('CategoryService throws CategoryException when updating without ID', () {
      final service = CategoryService();

      expect(
        () => service.updateCategory(const Category(
          id: '  ',
          businessId: 'biz-1',
          name: 'Valid Name',
        )),
        throwsA(isA<CategoryException>().having(
          (e) => e.message,
          'message',
          contains('Category ID is required'),
        )),
      );
    });

    test('ProductService throws ProductException for invalid product attributes', () {
      final service = ProductService();

      // Empty name
      expect(
        () => service.createProduct(const Product(
          id: '',
          businessId: 'biz-1',
          name: '',
          price: 10.0,
        )),
        throwsA(isA<ProductException>().having(
          (e) => e.message,
          'message',
          contains('cannot be empty'),
        )),
      );

      // Negative price
      expect(
        () => service.createProduct(const Product(
          id: '',
          businessId: 'biz-1',
          name: 'Invalid Price Item',
          price: -5.0,
        )),
        throwsA(isA<ProductException>().having(
          (e) => e.message,
          'message',
          contains('price cannot be negative'),
        )),
      );

      // Negative cost
      expect(
        () => service.createProduct(const Product(
          id: '',
          businessId: 'biz-1',
          name: 'Invalid Cost Item',
          price: 10.0,
          cost: -2.0,
        )),
        throwsA(isA<ProductException>().having(
          (e) => e.message,
          'message',
          contains('cost cannot be negative'),
        )),
      );

      // Update without product ID
      expect(
        () => service.updateProduct(const Product(
          id: '  ',
          businessId: 'biz-1',
          name: 'Item Name',
          price: 10.0,
        )),
        throwsA(isA<ProductException>().having(
          (e) => e.message,
          'message',
          contains('Product ID is required'),
        )),
      );
    });
  });
}
