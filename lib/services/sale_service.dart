import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../models/completed_sale_model.dart';
import '../models/sale_item_model.dart';
import 'business_service.dart';
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

  SupabaseClient? get client {
    if (customClient != null) return customClient;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

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

    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      throw const SaleException('Supabase is not configured.');
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
      final response = await c.rpc(
        'process_checkout',
        params: {'payload': payload},
      );

      return Map<String, dynamic>.from(response as Map);
    } on PostgrestException catch (e) {
      // Catch specific database exceptions (e.g., insufficient stock, not found)
      throw SaleException(e.message);
    } catch (e) {
      if (e is FlexPOSException) rethrow;
      throw SaleException('An unexpected error occurred during checkout.', e);
    }
  }

  /// Fetches completed sales history for the authenticated cashier in newest-first order.
  Future<List<CompletedSaleModel>> getCompletedSalesForCashier({
    String? searchQuery,
    String dateFilter = 'all',
  }) async {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      throw const SaleException('Supabase is not configured.');
    }

    try {
      final user = c.auth.currentUser;
      if (user == null) {
        throw const SaleException('No authenticated session found.');
      }

      final bId = await BusinessService(client: c).getBusinessId();

      final response = await c
          .from('sales')
          .select('*, sale_items(*), payments(*)')
          .eq('business_id', bId)
          .eq('employee_id', user.id)
          .order('created_at', ascending: false);

      final list = (response as List<dynamic>).map((json) {
        final itemsRaw = json['sale_items'] as List<dynamic>? ?? [];
        final items = itemsRaw.map((i) => SaleItem.fromMap(i as Map<String, dynamic>)).toList();
        final paymentsRaw = json['payments'] as List<dynamic>? ?? [];
        String pMethod = 'cash';
        if (paymentsRaw.isNotEmpty) {
          pMethod = paymentsRaw.first['payment_method']?.toString() ?? 'cash';
        }
        return CompletedSaleModel.fromMap(json as Map<String, dynamic>, items: items, paymentMethod: pMethod);
      }).toList();

      return _filterCompletedSales(list, searchQuery: searchQuery, dateFilter: dateFilter);
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw SaleException('Unable to load cashier completed sales', e);
    }
  }

  /// Fetches all store sales history for Managers / Admins across all cashiers.
  Future<List<CompletedSaleModel>> getStoreSales({
    String? searchQuery,
    String dateFilter = 'all',
  }) async {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      throw const SaleException('Supabase is not configured.');
    }

    try {
      final user = c.auth.currentUser;
      if (user == null) {
        throw const SaleException('No authenticated session found.');
      }

      final bId = await BusinessService(client: c).getBusinessId();

      final response = await c
          .from('sales')
          .select('*, sale_items(*), payments(*)')
          .eq('business_id', bId)
          .order('created_at', ascending: false);

      final list = (response as List<dynamic>).map((json) {
        final itemsRaw = json['sale_items'] as List<dynamic>? ?? [];
        final items = itemsRaw.map((i) => SaleItem.fromMap(i as Map<String, dynamic>)).toList();
        final paymentsRaw = json['payments'] as List<dynamic>? ?? [];
        String pMethod = 'cash';
        if (paymentsRaw.isNotEmpty) {
          pMethod = paymentsRaw.first['payment_method']?.toString() ?? 'cash';
        }
        return CompletedSaleModel.fromMap(json as Map<String, dynamic>, items: items, paymentMethod: pMethod);
      }).toList();

      return _filterCompletedSales(list, searchQuery: searchQuery, dateFilter: dateFilter);
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw SaleException('Unable to load store sales', e);
    }
  }

  List<CompletedSaleModel> _filterCompletedSales(
    List<CompletedSaleModel> sales, {
    String? searchQuery,
    String dateFilter = 'all',
  }) {
    final query = searchQuery?.trim().toLowerCase() ?? '';
    final now = DateTime.now();

    return sales.where((sale) {
      // Date Filter
      final dt = sale.createdAt;
      if (dateFilter == 'today') {
        final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
        if (!isToday) return false;
      } else if (dateFilter == 'yesterday') {
        final yesterday = now.subtract(const Duration(days: 1));
        final isYesterday = dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;
        if (!isYesterday) return false;
      } else if (dateFilter == 'last_7_days') {
        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        if (dt.isBefore(sevenDaysAgo)) return false;
      }

      // Search Query Filter across Invoice Number, Product Name, SKU
      if (query.isNotEmpty) {
        final invMatch = sale.invoiceNumber.toLowerCase().contains(query);
        final itemMatch = sale.items.any((item) {
          final nameMatch = (item.productNameSnapshot ?? item.productName ?? '').toLowerCase().contains(query);
          final skuMatch = (item.skuSnapshot ?? item.productSku ?? '').toLowerCase().contains(query);
          return nameMatch || skuMatch;
        });

        return invMatch || itemMatch;
      }

      return true;
    }).toList();
  }
}
