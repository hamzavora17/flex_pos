class Sale {
  final String id;
  final String businessId;
  final String branchId;
  final String? shiftId;
  final String employeeId;
  final String? customerId;
  final String invoiceNumber;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Sale({
    required this.id,
    required this.businessId,
    required this.branchId,
    this.shiftId,
    required this.employeeId,
    this.customerId,
    required this.invoiceNumber,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id']?.toString() ?? '',
      businessId: map['business_id']?.toString() ?? '',
      branchId: map['branch_id']?.toString() ?? '',
      shiftId: map['shift_id']?.toString(),
      employeeId: map['employee_id']?.toString() ?? '',
      customerId: map['customer_id']?.toString(),
      invoiceNumber: map['invoice_number']?.toString() ?? '',
      subtotal: (map['subtotal'] is num)
          ? (map['subtotal'] as num).toDouble()
          : double.tryParse(map['subtotal']?.toString() ?? '0') ?? 0.0,
      discount: (map['discount'] is num)
          ? (map['discount'] as num).toDouble()
          : double.tryParse(map['discount']?.toString() ?? '0') ?? 0.0,
      tax: (map['tax'] is num)
          ? (map['tax'] as num).toDouble()
          : double.tryParse(map['tax']?.toString() ?? '0') ?? 0.0,
      total: (map['total'] is num)
          ? (map['total'] as num).toDouble()
          : double.tryParse(map['total']?.toString() ?? '0') ?? 0.0,
      status: map['status']?.toString() ?? 'completed',
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'business_id': businessId,
      'branch_id': branchId,
      'shift_id': shiftId,
      'employee_id': employeeId,
      'customer_id': customerId,
      'invoice_number': invoiceNumber,
      'subtotal': subtotal,
      'discount': discount,
      'tax': tax,
      'total': total,
      'status': status,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
