/// Lightweight model representing a product item in FlexPOS.
class Product {
  final String id;
  final String businessId;
  final String? categoryId;
  final String name;
  final String? sku;
  final String? barcode;
  final double price;
  final double cost;
  final bool active;
  final String unit;
  final int minStockAlert;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Product({
    required this.id,
    required this.businessId,
    this.categoryId,
    required this.name,
    this.sku,
    this.barcode,
    required this.price,
    this.cost = 0.0,
    this.active = true,
    this.unit = 'pcs',
    this.minStockAlert = 5,
    this.createdAt,
    this.updatedAt,
  });

  /// Factory constructor to create a [Product] from a Supabase row map.
  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString() ?? '',
      businessId: map['business_id']?.toString() ?? '',
      categoryId: map['category_id']?.toString(),
      name: map['name']?.toString() ?? '',
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      price: (map['price'] is num)
          ? (map['price'] as num).toDouble()
          : double.tryParse(map['price']?.toString() ?? '0') ?? 0.0,
      cost: (map['cost'] is num)
          ? (map['cost'] as num).toDouble()
          : double.tryParse(map['cost']?.toString() ?? '0') ?? 0.0,
      active: map['active'] as bool? ?? true,
      unit: map['unit']?.toString() ?? 'pcs',
      minStockAlert: (map['min_stock_alert'] is int)
          ? map['min_stock_alert'] as int
          : int.tryParse(map['min_stock_alert']?.toString() ?? '5') ?? 5,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  /// Converts the [Product] instance into a map for Supabase insert/update.
  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'business_id': businessId,
      'category_id': categoryId,
      'name': name,
      'sku': (sku != null && sku!.trim().isNotEmpty) ? sku!.trim() : null,
      'barcode': (barcode != null && barcode!.trim().isNotEmpty) ? barcode!.trim() : null,
      'price': price,
      'cost': cost,
      'active': active,
      'unit': unit,
      'min_stock_alert': minStockAlert,
    };
  }

  Product copyWith({
    String? id,
    String? businessId,
    String? categoryId,
    String? name,
    String? sku,
    String? barcode,
    double? price,
    double? cost,
    bool? active,
    String? unit,
    int? minStockAlert,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      active: active ?? this.active,
      unit: unit ?? this.unit,
      minStockAlert: minStockAlert ?? this.minStockAlert,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
