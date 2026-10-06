import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../features/cashier/presentation/new_sale_screen.dart';
import '../models/held_sale_model.dart';
import '../models/product_model.dart';
import 'business_service.dart';
import 'inventory_service.dart';
import 'product_service.dart';

/// Service managing persistent cashier held sales (paused carts).
class HeldSaleService {
  final SupabaseClient? customClient;
  final BusinessService? customBusinessService;
  final ProductService? customProductService;
  final InventoryService? customInventoryService;

  HeldSaleService({
    SupabaseClient? client,
    BusinessService? businessService,
    ProductService? productService,
    InventoryService? inventoryService,
  })  : customClient = client,
        customBusinessService = businessService,
        customProductService = productService,
        customInventoryService = inventoryService;

  SupabaseClient? get client {
    if (customClient != null) return customClient;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  BusinessService get businessService =>
      customBusinessService ?? BusinessService(client: customClient);
  ProductService get productService =>
      customProductService ?? ProductService(client: customClient);
  InventoryService get inventoryService =>
      customInventoryService ?? InventoryService(client: customClient);

  /// Saves an active cashier cart as a held sale transaction.
  /// Does NOT deduct stock, process payment, or create completed sales.
  Future<HeldSaleModel> holdSale({
    required String? branchId,
    required List<CartItemModel> cartItems,
  }) async {
    if (cartItems.isEmpty) {
      throw Exception('Cannot hold an empty cart');
    }

    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      throw Exception('Supabase is not configured.');
    }

    final user = c.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final now = DateTime.now();
    final refNumber = 'HOLD-${now.millisecondsSinceEpoch.toString().substring(7)}';

    final bId = await businessService.getBusinessId();

    try {
      // Insert held_sales row
      final saleResponse = await c.from('held_sales').insert({
        'business_id': bId,
        'branch_id': branchId,
        'employee_id': user.id,
        'reference_number': refNumber,
        'status': 'held',
      }).select().single();

      final heldSaleId = saleResponse['id'].toString();

      // Insert held_sale_items rows
      final itemsPayload = cartItems
          .map((item) => {
                'held_sale_id': heldSaleId,
                'product_id': item.product.id,
                'product_name_snapshot': item.product.name,
                'sku_snapshot': item.product.sku,
                'quantity': item.quantity,
                'unit_price': item.product.price,
              })
          .toList();

      final itemsResponse =
          await c.from('held_sale_items').insert(itemsPayload).select();

      final items = (itemsResponse as List<dynamic>)
          .map((json) => HeldSaleItemModel.fromMap(json as Map<String, dynamic>))
          .toList();

      return HeldSaleModel.fromMap(saleResponse, items: items);
    } catch (e) {
      throw Exception('Failed to hold sale: $e');
    }
  }

  /// Fetches active held sales for the current cashier.
  Future<List<HeldSaleModel>> getHeldSales() async {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      return [];
    }

    final user = c.auth.currentUser;
    if (user == null) return [];

    try {
      final bId = await businessService.getBusinessId();

      final response = await c
          .from('held_sales')
          .select('*, held_sale_items(*)')
          .eq('business_id', bId)
          .eq('employee_id', user.id)
          .eq('status', 'held')
          .order('created_at', ascending: false);

      final list = (response as List<dynamic>).map((json) {
        final rawItems = json['held_sale_items'] as List<dynamic>? ?? [];
        final items = rawItems
            .map((i) => HeldSaleItemModel.fromMap(i as Map<String, dynamic>))
            .toList();
        return HeldSaleModel.fromMap(json as Map<String, dynamic>, items: items);
      }).toList();

      return list;
    } catch (e) {
      // Return empty list if held_sales table is not present in the deployed database
      return [];
    }
  }

  /// Gets total active held sale count for current cashier.
  Future<int> getHeldSaleCount() async {
    try {
      final sales = await getHeldSales();
      return sales.length;
    } catch (_) {
      return 0;
    }
  }

  /// Permanently deletes a held sale and its items without affecting inventory or creating sales/refunds.
  Future<void> deleteHeldSale(String heldSaleId) async {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      throw Exception('Supabase is not configured.');
    }

    final user = c.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    try {
      await c
          .from('held_sales')
          .delete()
          .eq('id', heldSaleId)
          .eq('employee_id', user.id);
    } catch (e) {
      throw Exception('Failed to delete held sale: $e');
    }
  }

  /// Resumes a held sale: verifies products exist and are active, loads items,
  /// deletes the held sale record from DB, and returns restored CartItemModel list.
  Future<List<CartItemModel>> resumeHeldSale(
      HeldSaleModel heldSale, Map<String, int> currentStockMap) async {
    final activeProducts = await productService.getCashierCatalog();
    final activeProdMap = <String, Product>{};
    for (var p in activeProducts) {
      activeProdMap[p.id] = p;
    }

    final restoredCart = <CartItemModel>[];

    for (var item in heldSale.items) {
      final product = activeProdMap[item.productId];
      if (product != null && product.active && product.isInStock) {
        // Preserve snapshot price
        final restoredProduct = product.copyWith(price: item.unitPrice);

        restoredCart.add(CartItemModel(
          product: restoredProduct,
          quantity: item.quantity,
          maxStock: 999999,
        ));
      }
    }

    // Delete held sale record after successful restoration
    await deleteHeldSale(heldSale.id);

    return restoredCart;
  }
}
