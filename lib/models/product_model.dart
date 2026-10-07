/// Model representing a product item in FlexPOS.
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
  final int stockQuantity;
  final bool isInStock;
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
    this.stockQuantity = 0,
    this.isInStock = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Factory constructor to create a [Product] from a Supabase row map.
  factory Product.fromMap(Map<String, dynamic> map) {
    final qty = (map['stock_quantity'] is int)
        ? map['stock_quantity'] as int
        : (map['quantity'] is int)
            ? map['quantity'] as int
            : int.tryParse(map['stock_quantity']?.toString() ?? map['quantity']?.toString() ?? '0') ?? 0;

    final inStockVal = map['is_in_stock'] != null
        ? (map['is_in_stock'] as bool? ?? false)
        : (qty > 0);

    return Product(
      id: map['id']?.toString() ?? '',
      businessId: map['business_id']?.toString() ?? '',
      categoryId: map['category_id']?.toString(),
      name: map['name']?.toString() ?? map['product_name']?.toString() ?? '',
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      price: (map['price'] is num)
          ? (map['price'] as num).toDouble()
          : (map['selling_price'] is num)
              ? (map['selling_price'] as num).toDouble()
              : double.tryParse(map['price']?.toString() ?? map['selling_price']?.toString() ?? '0') ?? 0.0,
      cost: (map['cost'] is num)
          ? (map['cost'] as num).toDouble()
          : (map['purchase_price'] is num)
              ? (map['purchase_price'] as num).toDouble()
              : double.tryParse(map['cost']?.toString() ?? map['purchase_price']?.toString() ?? '0') ?? 0.0,
      active: (map['active'] as bool?) ?? (map['is_active'] as bool?) ?? true,
      unit: map['unit']?.toString() ?? 'pcs',
      minStockAlert: (map['min_stock_alert'] is int)
          ? map['min_stock_alert'] as int
          : (map['minimum_stock_level'] is int)
              ? map['minimum_stock_level'] as int
              : int.tryParse(map['min_stock_alert']?.toString() ?? map['minimum_stock_level']?.toString() ?? '5') ?? 5,
      stockQuantity: qty,
      isInStock: inStockVal,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  /// Converts the [Product] instance into a map for Supabase insert/update.
  ///
  /// Only contains real columns present on `public.products` table.
  /// Stock quantities belong in `public.inventory` table.
  Map<String, dynamic> toMap({bool includeStockQuantity = false}) {
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
    int? stockQuantity,
    bool? isInStock,
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
      stockQuantity: stockQuantity ?? this.stockQuantity,
      isInStock: isInStock ?? this.isInStock,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
