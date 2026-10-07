import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../models/return_model.dart';

/// Service managing product returns, damage inspection, refund calculations, and inventory restorations.
class ReturnService {
  final SupabaseClient? customClient;

  ReturnService({SupabaseClient? client}) : customClient = client;

  SupabaseClient? get client {
    if (customClient != null) return customClient;
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Processes product return following the inspection decision tree:
  /// - Is product damaged = YES -> Reject return with clear message ("Damaged goods rejected").
  /// - Is product damaged = NO -> Approve return, calculate refund, restore stock, and record refund.
  Future<ReturnResultModel> processReturn({
    required String saleId,
    required List<ReturnItemSelection> items,
    required bool isDamaged,
    String paymentMethod = 'cash',
  }) async {
    final validItems = items.where((i) => i.selectedQuantity > 0).toList();
    if (validItems.isEmpty) {
      throw Exception('Please select at least one item to return.');
    }

    // Inspection Decision Tree
    if (isDamaged) {
      // REJECT RETURN
      return ReturnResultModel(
        returnId: '',
        refundAmount: 0.0,
        isApproved: false,
        message: 'Return Rejected: Damaged or broken items are not eligible for return or inventory restoration.',
      );
    }

    // Step 3: Calculate Refund
    final totalRefund = validItems.fold(0.0, (sum, item) => sum + item.lineRefund);

    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      throw Exception('Supabase is not configured.');
    }

    try {
      final payload = {
        'sale_id': saleId,
        'is_damaged': false,
        'payment_method': paymentMethod.toLowerCase(),
        'items': validItems
            .map((i) => {
                  'product_id': i.productId,
                  'quantity': i.selectedQuantity,
                  'unit_price': i.unitPrice,
                })
            .toList(),
      };

      final response = await c.rpc('process_return', params: {'payload': payload});
      final resMap = Map<String, dynamic>.from(response as Map);

      return ReturnResultModel(
        returnId: resMap['return_id']?.toString() ?? '',
        refundAmount: (resMap['refund_amount'] as num?)?.toDouble() ?? totalRefund,
        isApproved: true,
        message: 'Return Approved! Inventory stock restored.',
      );
    } catch (e) {
      throw Exception('Failed to process return on database: $e');
    }
  }

  /// Fetches a map of product_id -> total_returned_quantity for approved returns on a sale.
  Future<Map<String, int>> getReturnedQuantitiesForSale(String saleId) async {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) return {};

    try {
      final response = await c
          .from('sale_returns')
          .select('id, sale_return_items(product_id, quantity)')
          .eq('sale_id', saleId)
          .eq('status', 'approved');

      final returnedMap = <String, int>{};
      for (var ret in (response as List<dynamic>)) {
        final items = ret['sale_return_items'] as List<dynamic>? ?? [];
        for (var item in items) {
          final pid = item['product_id']?.toString() ?? '';
          final qty = (item['quantity'] as num? ?? 0).toInt();
          if (pid.isNotEmpty) {
            returnedMap[pid] = (returnedMap[pid] ?? 0) + qty;
          }
        }
      }
      return returnedMap;
    } catch (_) {
      return {};
    }
  }

  /// Fetches a persisted return record by return ID directly from the database
  /// and constructs the ReturnReceiptModel from authentic DB data.
  Future<ReturnReceiptModel> getReturnById(String returnId) async {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) {
      throw Exception('Supabase is not configured.');
    }

    try {
      final response = await c
          .from('sale_returns')
          .select('*, sales(invoice_number), sale_return_items(*, products(name, sku))')
          .eq('id', returnId)
          .single();

      final json = response;
      final rId = json['id']?.toString() ?? returnId;
      final salesData = json['sales'] as Map<String, dynamic>?;
      final invNo = salesData?['invoice_number']?.toString() ?? 'INV';
      final dtRaw = json['created_at']?.toString();
      if (dtRaw == null || dtRaw.isEmpty) {
        throw Exception('Missing created_at timestamp in database return record $returnId');
      }
      final dt = DateTime.parse(dtRaw).toLocal();
      final refAmount = (json['refund_amount'] as num?)?.toDouble() ?? 0.0;
      final pMethod = json['payment_method']?.toString() ?? 'cash';
      final status = json['status']?.toString() ?? 'approved';

      final rawItems = json['sale_return_items'] as List<dynamic>? ?? [];
      final items = <ReturnItemSelection>[];
      for (var i in rawItems) {
        final pData = i['products'] as Map<String, dynamic>?;
        final pName = pData?['name']?.toString() ?? 'Returned Product';
        final sku = pData?['sku']?.toString();
        final qty = (i['quantity'] as num? ?? 1).toInt();
        final price = (i['unit_price'] as num? ?? 0.0).toDouble();

        items.add(ReturnItemSelection(
          productId: i['product_id']?.toString() ?? '',
          productName: pName,
          sku: sku,
          selectedQuantity: qty,
          maxQuantity: qty,
          unitPrice: price,
        ));
      }

      return ReturnReceiptModel(
        returnId: rId,
        originalInvoiceNumber: invNo,
        returnDate: dt,
        returnedItems: items,
        refundAmount: refAmount,
        paymentMethod: pMethod,
        status: status,
      );
    } catch (e) {
      throw Exception('Failed to fetch persisted return record $returnId from database: $e');
    }
  }

  /// Fetches historical return receipts for store returns.
  Future<List<ReturnReceiptModel>> getReturnHistory() async {
    final c = client;
    if (!SupabaseConfig.isConfigured || c == null) return [];

    try {
      final response = await c
          .from('sale_returns')
          .select('*, sales(invoice_number), sale_return_items(*, products(name, sku))')
          .order('created_at', ascending: false);

      final receipts = <ReturnReceiptModel>[];
      for (var ret in (response as List<dynamic>)) {
        final rId = ret['id']?.toString() ?? '';
        final salesData = ret['sales'] as Map<String, dynamic>?;
        final invNo = salesData?['invoice_number']?.toString() ?? 'INV-HIST';
        final dtRaw = ret['created_at']?.toString();
        if (dtRaw == null || dtRaw.isEmpty) {
          throw Exception('Missing created_at timestamp in database return record $rId');
        }
        final dt = DateTime.parse(dtRaw).toLocal();
        final refAmount = (ret['refund_amount'] as num?)?.toDouble() ?? 0.0;
        final pMethod = ret['payment_method']?.toString() ?? 'cash';
        final status = ret['status']?.toString() ?? 'approved';

        final rawItems = ret['sale_return_items'] as List<dynamic>? ?? [];
        final items = <ReturnItemSelection>[];
        for (var i in rawItems) {
          final pData = i['products'] as Map<String, dynamic>?;
          final pName = pData?['name']?.toString() ?? 'Returned Product';
          final sku = pData?['sku']?.toString();
          items.add(ReturnItemSelection(
            productId: i['product_id']?.toString() ?? '',
            productName: pName,
            sku: sku,
            selectedQuantity: (i['quantity'] as num? ?? 1).toInt(),
            maxQuantity: (i['quantity'] as num? ?? 1).toInt(),
            unitPrice: (i['unit_price'] as num? ?? 0.0).toDouble(),
          ));
        }

        receipts.add(ReturnReceiptModel(
          returnId: rId,
          originalInvoiceNumber: invNo,
          returnDate: dt,
          returnedItems: items,
          refundAmount: refAmount,
          paymentMethod: pMethod,
          status: status,
        ));
      }
      return receipts;
    } catch (_) {
      return [];
    }
  }
}
