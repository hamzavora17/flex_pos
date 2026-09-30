import 'package:supabase_flutter/supabase_flutter.dart';
import 'exceptions.dart';

/// Represents a simple item in the shopping cart for checkout requests.
class CartItem {
  final String productId;
  final int quantity;

  const CartItem({
    required this.productId,
    required this.quantity,
  });

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'quantity': quantity,
    };
  }
}

/// Service providing sales and checkout operations.
class SaleService {
  final SupabaseClient? customClient;

  SaleService({SupabaseClient? client}) : customClient = client;

  SupabaseClient get client => customClient ?? Supabase.instance.client;

  /// Submits a checkout transaction to the secure process_checkout Supabase RPC.
  /// 
  /// Calculates all line totals securely on the database side and performs
  /// atomic deduction of inventory, inserts to sale, sale_items and payments.
  Future<Map<String, dynamic>> checkout({
    required String branchId,
    required List<CartItem> items,
    required String paymentMethod,
    double discount = 0.0,
    String? customerId,
  }) async {
    // 1. Validation
    if (items.isEmpty) {
      throw const SaleException('Cart cannot be empty.');
    }
    for (var item in items) {
      if (item.quantity <= 0) {
        throw const SaleException('Quantity must be positive for all items.');
      }
    }
    if (discount < 0) {
      throw const SaleException('Discount cannot be negative.');
    }
    
    final validMethods = ['cash', 'card', 'upi', 'qr', 'other'];
    if (!validMethods.contains(paymentMethod.toLowerCase())) {
      throw SaleException('Unsupported payment method: $paymentMethod');
    }

    try {
      // 2. Prepare payload
      final payload = {
        'branch_id': branchId,
        if (customerId != null && customerId.trim().isNotEmpty) 'customer_id': customerId.trim(),
        'discount': discount,
        'payment_method': paymentMethod.toLowerCase(),
        'items': items.map((e) => e.toMap()).toList(),
      };

      // 3. Invoke RPC
      final response = await client.rpc(
        'process_checkout',
        params: {'payload': payload},
      );

      return Map<String, dynamic>.from(response as Map);
    } on PostgrestException catch (e) {
      // Catch specific database exceptions (e.g., insufficient stock, not found)
      throw SaleException(e.message);
    } catch (e) {
      throw SaleException('An unexpected error occurred during checkout.', e);
    }
  }
}
