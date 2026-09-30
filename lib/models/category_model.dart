/// Lightweight model representing a product category in FlexPOS.
class Category {
  final String id;
  final String businessId;
  final String name;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Category({
    required this.id,
    required this.businessId,
    required this.name,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  /// Factory constructor to create a [Category] from a Supabase row map.
  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id']?.toString() ?? '',
      businessId: map['business_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  /// Converts the [Category] instance into a map for Supabase insert/update.
  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'business_id': businessId,
      'name': name,
      'description': description,
    };
  }

  Category copyWith({
    String? id,
    String? businessId,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Category(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
