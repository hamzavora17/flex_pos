import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_model.dart';
import 'business_service.dart';
import 'exceptions.dart';

/// Service providing CRUD and stock adjustment operations for inventory records.
class InventoryService {
  final SupabaseClient? customClient;
  final BusinessService? customBusinessService;

  InventoryService({
    SupabaseClient? client,
    BusinessService? businessService,
  })  : customClient = client,
        customBusinessService = businessService;

  SupabaseClient get client => customClient ?? Supabase.instance.client;
  BusinessService get businessService =>
      customBusinessService ?? BusinessService(client: customClient);

  /// Validates inventory record attributes before persistence operations.
  void _validateInventory(InventoryItem inventory, {bool isUpdate = false}) {
    if (isUpdate && inventory.id.trim().isEmpty) {
      throw const InventoryException('Inventory ID is required for update');
    }
    if (inventory.productId.trim().isEmpty) {
      throw const InventoryException('Product ID is required for inventory record');
    }
    if (inventory.quantity < 0) {
      throw const InventoryException('Inventory quantity cannot be negative');
    }
    if (inventory.lowStockThreshold < 0) {
      throw const InventoryException('Low stock threshold cannot be negative');
    }
  }

  /// Fetches all inventory records for the authenticated user's store business.
  Future<List<InventoryItem>> getInventory({String? businessId}) async {
    try {
      final bId = await businessService.getBusinessId();
      final response = await client
          .from('inventory')
          .select()
          .eq('business_id', bId);

      return (response as List<dynamic>)
          .map((json) => InventoryItem.fromMap(json as Map<String, dynamic>))
          .toList();
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw InventoryException('Unable to load inventory', e);
    }
  }

  /// Fetches the inventory record for a specific product under the authenticated user's store business.
  Future<InventoryItem?> getInventoryByProductId({
    required String productId,
    required String branchId,
  }) async {
    if (productId.trim().isEmpty) {
      throw const InventoryException('Product ID is required to fetch inventory');
    }
    if (branchId.trim().isEmpty) {
      throw const InventoryException('Branch ID is required to fetch inventory');
    }

    try {
      final bId = await businessService.getBusinessId();
      final response = await client
          .from('inventory')
          .select()
          .eq('product_id', productId.trim())
          .eq('branch_id', branchId.trim())
          .eq('business_id', bId)
          .maybeSingle();

      if (response == null) return null;
      return InventoryItem.fromMap(response);
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw InventoryException('Unable to fetch inventory for product', e);
    }
  }

  String _formatPostgrestError(String prefix, PostgrestException e) {
    final msg = e.message.toLowerCase();
    if (e.code == '42501' || msg.contains('row-level security') || msg.contains('permission denied')) {
      return '$prefix: Access denied by security policy.';
    }
    if (e.message.isNotEmpty) {
      return '$prefix: ${e.message}';
    }
    return '$prefix due to a database error.';
  }

  /// Creates a new inventory record for a product.
  Future<InventoryItem> createInventory(InventoryItem inventory) async {
    _validateInventory(inventory, isUpdate: false);

    try {
      final bId = await businessService.getBusinessId();
      final payload = inventory.copyWith(businessId: bId).toMap();
      final response = await client
          .from('inventory')
          .insert(payload)
          .select()
          .single();

      return InventoryItem.fromMap(response);
    } on FlexPOSException {
      rethrow;
    } on PostgrestException catch (e) {
      throw InventoryException(_formatPostgrestError('Unable to save inventory record', e), e);
    } catch (e) {
      throw InventoryException('Unable to save inventory record: ${e.toString()}', e);
    }
  }

  /// Updates an existing inventory record belonging to the authenticated user's business.
  Future<InventoryItem> updateInventory(InventoryItem inventory) async {
    _validateInventory(inventory, isUpdate: true);

    try {
      final bId = await businessService.getBusinessId();
      final payload = inventory.copyWith(businessId: bId).toMap();
      final response = await client
          .from('inventory')
          .update(payload)
          .eq('id', inventory.id)
          .eq('business_id', bId)
          .select()
          .single();

      return InventoryItem.fromMap(response);
    } on FlexPOSException {
      rethrow;
    } on PostgrestException catch (e) {
      throw InventoryException(_formatPostgrestError('Unable to update inventory record', e), e);
    } catch (e) {
      throw InventoryException('Unable to update inventory record: ${e.toString()}', e);
    }
  }

  /// Adjusts stock for a product safely, preventing negative inventory levels.
  Future<InventoryItem> adjustStock({
    required String productId,
    required String branchId,
    required int adjustmentQuantity,
  }) async {
    final trimmedProductId = productId.trim();
    final trimmedBranchId = branchId.trim();
    if (trimmedProductId.isEmpty) {
      throw const InventoryException('Product ID is required for stock adjustment');
    }
    if (trimmedBranchId.isEmpty) {
      throw const InventoryException('Branch ID is required for stock adjustment');
    }

    try {
      final bId = await businessService.getBusinessId();
      final existing = await getInventoryByProductId(
        productId: trimmedProductId,
        branchId: trimmedBranchId,
      );

      if (existing == null) {
        if (adjustmentQuantity < 0) {
          throw InventoryException(
            'Stock adjustment failed: Cannot deduct stock when no inventory record exists ($adjustmentQuantity)',
          );
        }
        return await createInventory(InventoryItem(
          id: '',
          productId: trimmedProductId,
          businessId: bId,
          branchId: trimmedBranchId,
          quantity: adjustmentQuantity,
        ));
      }

      final newQuantity = existing.quantity + adjustmentQuantity;
      if (newQuantity < 0) {
        throw InventoryException(
          'Stock adjustment would result in negative inventory level ($newQuantity)',
        );
      }

      return await updateInventory(existing.copyWith(quantity: newQuantity));
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw InventoryException('Unable to adjust stock level', e);
    }
  }

  /// Permanently deletes an inventory record by ID restricted to the authenticated user's business.
  Future<void> deleteInventory(String id) async {
    if (id.trim().isEmpty) {
      throw const InventoryException('Inventory ID is required for deletion');
    }

    try {
      final bId = await businessService.getBusinessId();
      await client
          .from('inventory')
          .delete()
          .eq('id', id)
          .eq('business_id', bId);
    } catch (e) {
      throw InventoryException('Unable to delete inventory record', e);
    }
  }
}
