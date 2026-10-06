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
}
