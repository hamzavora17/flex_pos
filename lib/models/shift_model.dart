/// Model representing a cashier work shift session.
class ShiftModel {
  final String id;
  final String employeeId;
  final String? branchId;
  final DateTime startTime; // Mapped from created_at
  final DateTime? endTime; // Mapped from updated_at if status == 'ended'
  final double openingFloat; // Mapped from expected_cash
  final String status; // 'active', 'ended', 'not_started'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ShiftModel({
    required this.id,
    required this.employeeId,
    this.branchId,
    required this.startTime,
    this.endTime,
    this.openingFloat = 0.0,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  bool get isActive => status == 'active';

  factory ShiftModel.fromMap(Map<String, dynamic> map) {
    final createdAtDt = map['created_at'] != null
        ? DateTime.parse(map['created_at'].toString()).toLocal()
        : DateTime.now();

    final statusStr = map['status']?.toString() ?? 'not_started';
    DateTime? endedAtDt;
    if (statusStr == 'ended' && map['updated_at'] != null) {
      endedAtDt = DateTime.parse(map['updated_at'].toString()).toLocal();
    }

    return ShiftModel(
      id: map['id']?.toString() ?? '',
      employeeId: map['employee_id']?.toString() ?? '',
      branchId: map['branch_id']?.toString(),
      startTime: createdAtDt,
      endTime: endedAtDt,
      openingFloat: (map['expected_cash'] is num)
          ? (map['expected_cash'] as num).toDouble()
          : double.tryParse(map['expected_cash']?.toString() ?? '0.0') ?? 0.0,
      status: statusStr,
      createdAt: createdAtDt,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'].toString()).toLocal()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'employee_id': employeeId,
      if (branchId != null) 'branch_id': branchId,
      'expected_cash': openingFloat,
      'status': status,
    };
  }
}
