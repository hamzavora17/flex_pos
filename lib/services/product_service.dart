import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import 'business_service.dart';
import 'exceptions.dart';

/// Service providing CRUD operations for catalog products.
class ProductService {
  final SupabaseClient? customClient;
  final BusinessService? customBusinessService;

  ProductService({
    SupabaseClient? client,
    BusinessService? businessService,
  })  : customClient = client,
        customBusinessService = businessService;

  SupabaseClient get client => customClient ?? Supabase.instance.client;
  BusinessService get businessService =>
      customBusinessService ?? BusinessService(client: customClient);

  /// Validates product attributes before persistence operations.
  void _validateProduct(Product product, {bool isUpdate = false}) {
    if (isUpdate && product.id.trim().isEmpty) {
      throw const ProductException('Product ID is required for update');
    }
    if (product.name.trim().isEmpty) {
      throw const ProductException('Product name cannot be empty');
    }
    if (product.price < 0) {
      throw const ProductException('Product price cannot be negative');
    }
    if (product.cost < 0) {
      throw const ProductException('Product cost cannot be negative');
    }
  }

  /// Fetches all products for the current user's business store.
  Future<List<Product>> getProducts({String? businessId}) async {
    try {
      final bId = await businessService.getBusinessId();
      final response = await client
          .from('products')
          .select()
          .eq('business_id', bId)
          .order('name', ascending: true);

      return (response as List<dynamic>)
          .map((json) => Product.fromMap(json as Map<String, dynamic>))
          .toList();
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw ProductException('Unable to load products', e);
    }
  }

  /// Fetches only active products for the current user's business store.
  Future<List<Product>> getActiveProducts({String? businessId}) async {
    try {
      final bId = await businessService.getBusinessId();
      final response = await client
          .from('products')
          .select()
          .eq('business_id', bId)
          .eq('active', true)
          .order('name', ascending: true);

      return (response as List<dynamic>)
          .map((json) => Product.fromMap(json as Map<String, dynamic>))
          .toList();
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw ProductException('Unable to load active products', e);
    }
  }

  /// Fetches a single product by its unique ID, restricted to the authenticated user's business.
  Future<Product?> getProductById(String id) async {
    if (id.trim().isEmpty) return null;

    try {
      final bId = await businessService.getBusinessId();
      final response = await client
          .from('products')
          .select()
          .eq('id', id)
          .eq('business_id', bId)
          .maybeSingle();

      if (response == null) return null;
      return Product.fromMap(response);
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw ProductException('Unable to find product', e);
    }
  }

  /// Creates a new product in the authenticated user's store catalog.
  Future<Product> createProduct(Product product) async {
    _validateProduct(product, isUpdate: false);

    try {
      final bId = await businessService.getBusinessId();
      final payload = product.copyWith(businessId: bId).toMap();
      final response = await client
          .from('products')
          .insert(payload)
          .select()
          .single();

      return Product.fromMap(response);
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw ProductException('Unable to save product', e);
    }
  }

  /// Updates an existing product in the authenticated user's store catalog.
  Future<Product> updateProduct(Product product) async {
    _validateProduct(product, isUpdate: true);

    try {
      final bId = await businessService.getBusinessId();
      final payload = product.copyWith(businessId: bId).toMap();
      final response = await client
          .from('products')
          .update(payload)
          .eq('id', product.id)
          .eq('business_id', bId)
          .select()
          .single();

      return Product.fromMap(response);
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw ProductException('Unable to update product', e);
    }
  }

  /// Deactivates a product (sets `active = false`) restricted to the user's business.
  Future<void> deactivateProduct(String id) async {
    if (id.trim().isEmpty) {
      throw const ProductException('Product ID is required to deactivate');
    }

    try {
      final bId = await businessService.getBusinessId();
      await client
          .from('products')
          .update({'active': false})
          .eq('id', id)
          .eq('business_id', bId);
    } catch (e) {
      throw ProductException('Unable to deactivate product', e);
    }
  }

  /// Permanently deletes a product by its ID restricted to the user's business.
  Future<void> deleteProduct(String id) async {
    if (id.trim().isEmpty) {
      throw const ProductException('Product ID is required for deletion');
    }

    try {
      final bId = await businessService.getBusinessId();
      await client
          .from('products')
          .delete()
          .eq('id', id)
          .eq('business_id', bId);
    } catch (e) {
      throw ProductException('Unable to delete product', e);
    }
  }
}
