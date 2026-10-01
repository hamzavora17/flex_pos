/// Model representing a cashier work shift session.
class ShiftModel {
  final String id;
  final String businessId;
  final String employeeId;
  final DateTime startTime;
  final DateTime? endTime;
  final double openingFloat;
  final String status; // 'active', 'ended', 'not_started'
  final DateTime? createdAt;

  const ShiftModel({
    required this.id,
    required this.businessId,
    required this.employeeId,
    required this.startTime,
    this.endTime,
    this.openingFloat = 0.0,
    required this.status,
    this.createdAt,
  });

  bool get isActive => status == 'active';

  factory ShiftModel.fromMap(Map<String, dynamic> map) {
    return ShiftModel(
      id: map['id']?.toString() ?? '',
      businessId: map['business_id']?.toString() ?? '',
      employeeId: map['employee_id']?.toString() ?? '',
      startTime: map['start_time'] != null
          ? DateTime.parse(map['start_time'].toString()).toLocal()
          : DateTime.now(),
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'].toString()).toLocal()
          : null,
      openingFloat: (map['opening_float'] is num)
          ? (map['opening_float'] as num).toDouble()
          : double.tryParse(map['opening_float']?.toString() ?? '0.0') ?? 0.0,
      status: map['status']?.toString() ?? 'not_started',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'].toString()).toLocal()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'employee_id': employeeId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'opening_float': openingFloat,
      'status': status,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }
}
