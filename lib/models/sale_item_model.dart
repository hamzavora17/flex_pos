class SaleItem {
  final String id;
  final String saleId;
  final String? productId;
  final String? productName;
  final String? productSku;
  final String? productNameSnapshot;
  final String? skuSnapshot;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final DateTime? createdAt;

  const SaleItem({
    required this.id,
    required this.saleId,
    this.productId,
    this.productName,
    this.productSku,
    this.productNameSnapshot,
    this.skuSnapshot,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.createdAt,
  });

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      id: map['id']?.toString() ?? '',
      saleId: map['sale_id']?.toString() ?? '',
      productId: map['product_id']?.toString(),
      productName: map['product_name']?.toString(),
      productSku: map['product_sku']?.toString(),
      productNameSnapshot: map['product_name_snapshot']?.toString(),
      skuSnapshot: map['sku_snapshot']?.toString(),
      quantity: (map['quantity'] is int)
          ? map['quantity'] as int
          : int.tryParse(map['quantity']?.toString() ?? '0') ?? 0,
      unitPrice: (map['unit_price'] is num)
          ? (map['unit_price'] as num).toDouble()
          : double.tryParse(map['unit_price']?.toString() ?? '0') ?? 0.0,
      lineTotal: (map['line_total'] is num)
          ? (map['line_total'] as num).toDouble()
          : double.tryParse(map['line_total']?.toString() ?? '0') ?? 0.0,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'sale_id': saleId,
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'product_name_snapshot': productNameSnapshot,
      'sku_snapshot': skuSnapshot,
      'quantity': quantity,
      'unit_price': unitPrice,
      'line_total': lineTotal,
    };
  }
}
