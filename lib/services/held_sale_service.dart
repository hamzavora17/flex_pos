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

  // In-memory fallback for local demo or offline environments
  static final List<HeldSaleModel> _inMemoryHeldSales = [];

  HeldSaleService({
    SupabaseClient? client,
    BusinessService? businessService,
    ProductService? productService,
    InventoryService? inventoryService,
  })  : customClient = client,
        customBusinessService = businessService,
        customProductService = productService,
        customInventoryService = inventoryService;

  SupabaseClient get client => customClient ?? Supabase.instance.client;
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

    final now = DateTime.now();
    final refNumber = 'HOLD-${now.millisecondsSinceEpoch.toString().substring(7)}';

    if (!SupabaseConfig.isConfigured) {
      final saleId = 'demo-held-${now.millisecondsSinceEpoch}';
      final items = cartItems
          .map((c) => HeldSaleItemModel(
                id: 'demo-item-${c.product.id}-${now.millisecondsSinceEpoch}',
                heldSaleId: saleId,
                productId: c.product.id,
                productNameSnapshot: c.product.name,
                skuSnapshot: c.product.sku,
                quantity: c.quantity,
                unitPrice: c.product.price,
              ))
          .toList();

      final heldSale = HeldSaleModel(
        id: saleId,
        businessId: 'demo-business',
        branchId: branchId,
        employeeId: 'demo-employee',
        referenceNumber: refNumber,
        createdAt: now,
        items: items,
      );

      _inMemoryHeldSales.add(heldSale);
      return heldSale;
    }

    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final bId = await businessService.getBusinessId();

      // Insert held_sales row
      final saleResponse = await client.from('held_sales').insert({
        'business_id': bId,
        'branch_id': branchId,
        'employee_id': user.id,
        'reference_number': refNumber,
        'status': 'held',
      }).select().single();

      final heldSaleId = saleResponse['id'].toString();

      // Insert held_sale_items rows
      final itemsPayload = cartItems
          .map((c) => {
                'held_sale_id': heldSaleId,
                'product_id': c.product.id,
                'product_name_snapshot': c.product.name,
                'sku_snapshot': c.product.sku,
                'quantity': c.quantity,
                'unit_price': c.product.price,
              })
          .toList();

      final itemsResponse =
          await client.from('held_sale_items').insert(itemsPayload).select();

      final items = (itemsResponse as List<dynamic>)
          .map((json) => HeldSaleItemModel.fromMap(json as Map<String, dynamic>))
          .toList();

      return HeldSaleModel.fromMap(saleResponse, items: items);
    } catch (_) {
      // Fallback to in-memory store if database tables are in setup
      final saleId = 'fallback-held-${now.millisecondsSinceEpoch}';
      final items = cartItems
          .map((c) => HeldSaleItemModel(
                id: 'item-${c.product.id}',
                heldSaleId: saleId,
                productId: c.product.id,
                productNameSnapshot: c.product.name,
                skuSnapshot: c.product.sku,
                quantity: c.quantity,
                unitPrice: c.product.price,
              ))
          .toList();

      final heldSale = HeldSaleModel(
        id: saleId,
        businessId: 'fallback-business',
        branchId: branchId,
        employeeId: 'fallback-employee',
        referenceNumber: refNumber,
        createdAt: now,
        items: items,
      );

      _inMemoryHeldSales.add(heldSale);
      return heldSale;
    }
  }

  /// Fetches active held sales for the current cashier.
  Future<List<HeldSaleModel>> getHeldSales() async {
    if (!SupabaseConfig.isConfigured) {
      return List<HeldSaleModel>.from(
          _inMemoryHeldSales.where((s) => s.status == 'held'));
    }

    try {
      final user = client.auth.currentUser;
      if (user == null) return [];

      final bId = await businessService.getBusinessId();

      final response = await client
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
    } catch (_) {
      return List<HeldSaleModel>.from(
          _inMemoryHeldSales.where((s) => s.status == 'held'));
    }
  }

  /// Gets total active held sale count for current cashier.
  Future<int> getHeldSaleCount() async {
    final sales = await getHeldSales();
    return sales.length;
  }

  /// Permanently deletes a held sale and its items without affecting inventory or creating sales/refunds.
  Future<void> deleteHeldSale(String heldSaleId) async {
    _inMemoryHeldSales.removeWhere((s) => s.id == heldSaleId);

    if (!SupabaseConfig.isConfigured) return;

    try {
      final user = client.auth.currentUser;
      if (user == null) return;

      await client
          .from('held_sales')
          .delete()
          .eq('id', heldSaleId)
          .eq('employee_id', user.id);
    } catch (_) {}
  }

  /// Resumes a held sale: verifies products exist and are active, loads items,
  /// deletes the held sale record from DB, and returns restored CartItemModel list.
  Future<List<CartItemModel>> resumeHeldSale(
      HeldSaleModel heldSale, Map<String, int> currentStockMap) async {
    final activeProducts = await productService.getActiveProducts();
    final activeProdMap = <String, Product>{};
    for (var p in activeProducts) {
      activeProdMap[p.id] = p;
    }

    final restoredCart = <CartItemModel>[];

    for (var item in heldSale.items) {
      final product = activeProdMap[item.productId];
      if (product != null && product.active) {
        final stock = currentStockMap[product.id] ?? product.minStockAlert + 10;
        final qty = item.quantity.clamp(1, stock > 0 ? stock : 1);

        // Preserve snapshot price
        final restoredProduct = product.copyWith(price: item.unitPrice);

        restoredCart.add(CartItemModel(
          product: restoredProduct,
          quantity: qty,
          maxStock: stock > 0 ? stock : 999,
        ));
      }
    }

    // Delete held sale record after successful restoration
    await deleteHeldSale(heldSale.id);

    return restoredCart;
  }
}
