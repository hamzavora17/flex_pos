/// Model representing daily cashier attendance record.
class AttendanceModel {
  final String id;
  final String businessId;
  final String employeeId;
  final DateTime reportingTime;
  final String status; // 'present', 'absent', 'late', 'not_recorded'
  final String workDate; // YYYY-MM-DD
  final DateTime? createdAt;

  const AttendanceModel({
    required this.id,
    required this.businessId,
    required this.employeeId,
    required this.reportingTime,
    required this.status,
    required this.workDate,
    this.createdAt,
  });

  factory AttendanceModel.fromMap(Map<String, dynamic> map) {
    return AttendanceModel(
      id: map['id']?.toString() ?? '',
      businessId: map['business_id']?.toString() ?? '',
      employeeId: map['employee_id']?.toString() ?? '',
      reportingTime: map['reporting_time'] != null
          ? DateTime.parse(map['reporting_time'].toString()).toLocal()
          : DateTime.now(),
      status: map['status']?.toString() ?? 'not_recorded',
      workDate: map['work_date']?.toString() ?? '',
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
      'reporting_time': reportingTime.toIso8601String(),
      'status': status,
      'work_date': workDate,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }
}
