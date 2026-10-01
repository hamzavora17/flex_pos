/// Model representing a single item snapshot inside a held sale.
class HeldSaleItemModel {
  final String id;
  final String heldSaleId;
  final String productId;
  final String productNameSnapshot;
  final String? skuSnapshot;
  final int quantity;
  final double unitPrice;

  HeldSaleItemModel({
    required this.id,
    required this.heldSaleId,
    required this.productId,
    required this.productNameSnapshot,
    this.skuSnapshot,
    required this.quantity,
    required this.unitPrice,
  });

  double get lineTotal => unitPrice * quantity;

  factory HeldSaleItemModel.fromMap(Map<String, dynamic> map) {
    return HeldSaleItemModel(
      id: map['id']?.toString() ?? '',
      heldSaleId: map['held_sale_id']?.toString() ?? '',
      productId: map['product_id']?.toString() ?? '',
      productNameSnapshot: map['product_name_snapshot']?.toString() ?? 'Product',
      skuSnapshot: map['sku_snapshot']?.toString(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'held_sale_id': heldSaleId,
      'product_id': productId,
      'product_name_snapshot': productNameSnapshot,
      'sku_snapshot': skuSnapshot,
      'quantity': quantity,
      'unit_price': unitPrice,
    };
  }
}

/// Model representing a paused/held sale transaction.
class HeldSaleModel {
  final String id;
  final String businessId;
  final String? branchId;
  final String employeeId;
  final String referenceNumber;
  final String status;
  final DateTime createdAt;
  final List<HeldSaleItemModel> items;

  HeldSaleModel({
    required this.id,
    required this.businessId,
    this.branchId,
    required this.employeeId,
    required this.referenceNumber,
    this.status = 'held',
    required this.createdAt,
    this.items = const [],
  });

  double get totalValue => items.fold(0.0, (sum, item) => sum + item.lineTotal);
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  factory HeldSaleModel.fromMap(Map<String, dynamic> map, {List<HeldSaleItemModel> items = const []}) {
    return HeldSaleModel(
      id: map['id']?.toString() ?? '',
      businessId: map['business_id']?.toString() ?? '',
      branchId: map['branch_id']?.toString(),
      employeeId: map['employee_id']?.toString() ?? '',
      referenceNumber: map['reference_number']?.toString() ?? 'HOLD-0000',
      status: map['status']?.toString() ?? 'held',
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      items: items,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'business_id': businessId,
      'branch_id': branchId,
      'employee_id': employeeId,
      'reference_number': referenceNumber,
      'status': status,
    };
  }
}
