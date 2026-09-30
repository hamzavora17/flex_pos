class Payment {
  final String id;
  final String saleId;
  final String method;
  final String? reference;
  final double amount;
  final String paymentMethod;
  final DateTime? createdAt;

  const Payment({
    required this.id,
    required this.saleId,
    required this.method,
    this.reference,
    required this.amount,
    required this.paymentMethod,
    this.createdAt,
  });

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id']?.toString() ?? '',
      saleId: map['sale_id']?.toString() ?? '',
      method: map['method']?.toString() ?? 'cash',
      reference: map['reference']?.toString(),
      amount: (map['amount'] is num)
          ? (map['amount'] as num).toDouble()
          : double.tryParse(map['amount']?.toString() ?? '0') ?? 0.0,
      paymentMethod: map['payment_method']?.toString() ?? 'cash',
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'sale_id': saleId,
      'method': method,
      'reference': reference,
      'amount': amount,
      'payment_method': paymentMethod,
    };
  }
}
