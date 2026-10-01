import 'sale_item_model.dart';

/// Representation of a completed sale with line items and payment metadata.
class CompletedSaleModel {
  final String id;
  final String businessId;
  final String branchId;
  final String employeeId;
  final String invoiceNumber;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String status;
  final String paymentMethod;
  final DateTime createdAt;
  final List<SaleItem> items;

  CompletedSaleModel({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.employeeId,
    required this.invoiceNumber,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    this.status = 'completed',
    this.paymentMethod = 'cash',
    required this.createdAt,
    this.items = const [],
  });

  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  factory CompletedSaleModel.fromMap(
    Map<String, dynamic> map, {
    List<SaleItem> items = const [],
    String paymentMethod = 'cash',
  }) {
    return CompletedSaleModel(
      id: map['id']?.toString() ?? '',
      businessId: map['business_id']?.toString() ?? '',
      branchId: map['branch_id']?.toString() ?? '',
      employeeId: map['employee_id']?.toString() ?? '',
      invoiceNumber: map['invoice_number']?.toString() ?? 'INV-0000',
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      tax: (map['tax'] as num?)?.toDouble() ?? 0.0,
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      status: map['status']?.toString() ?? 'completed',
      paymentMethod: paymentMethod,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      items: items,
    );
  }
}
