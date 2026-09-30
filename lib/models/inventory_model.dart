/// Lightweight model representing an inventory item record in FlexPOS.
class InventoryItem {
  final String id;
  final String productId;
  final String businessId;
  final String? branchId;
  final int quantity;
  final int lowStockThreshold;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InventoryItem({
    required this.id,
    required this.productId,
    required this.businessId,
    this.branchId,
    this.quantity = 0,
    this.lowStockThreshold = 5,
    this.createdAt,
    this.updatedAt,
  });

  /// Factory constructor to create an [InventoryItem] from a Supabase row map.
  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id']?.toString() ?? '',
      productId: map['product_id']?.toString() ?? '',
      businessId: map['business_id']?.toString() ?? '',
      branchId: map['branch_id']?.toString(),
      quantity: (map['quantity'] is int)
          ? map['quantity'] as int
          : int.tryParse(map['quantity']?.toString() ?? '0') ?? 0,
      lowStockThreshold: (map['low_stock_threshold'] is int)
          ? map['low_stock_threshold'] as int
          : int.tryParse(map['low_stock_threshold']?.toString() ?? '5') ?? 5,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  /// Converts the [InventoryItem] instance into a map for Supabase insert/update.
  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'product_id': productId,
      'business_id': businessId,
      if (branchId != null && branchId!.trim().isNotEmpty) 'branch_id': branchId,
      'quantity': quantity,
      'low_stock_threshold': lowStockThreshold,
    };
  }

  InventoryItem copyWith({
    String? id,
    String? productId,
    String? businessId,
    String? branchId,
    int? quantity,
    int? lowStockThreshold,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      businessId: businessId ?? this.businessId,
      branchId: branchId ?? this.branchId,
      quantity: quantity ?? this.quantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
