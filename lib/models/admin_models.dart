/// Business metrics aggregated for the Admin Dashboard.
class AdminBusinessMetrics {
  final int total;
  final int active;
  final int inactive;
  final int createdToday;
  final int createdWeek;
  final int createdMonth;

  const AdminBusinessMetrics({
    required this.total,
    required this.active,
    required this.inactive,
    required this.createdToday,
    required this.createdWeek,
    required this.createdMonth,
  });

  factory AdminBusinessMetrics.fromMap(Map<String, dynamic> map) {
    return AdminBusinessMetrics(
      total: (map['total'] as num? ?? 0).toInt(),
      active: (map['active'] as num? ?? 0).toInt(),
      inactive: (map['inactive'] as num? ?? 0).toInt(),
      createdToday: (map['created_today'] as num? ?? 0).toInt(),
      createdWeek: (map['created_week'] as num? ?? 0).toInt(),
      createdMonth: (map['created_month'] as num? ?? 0).toInt(),
    );
  }
}

/// User metrics aggregated for the Admin Dashboard.
class AdminUserMetrics {
  final int total;
  final int active;
  final int inactive;
  final int admins;
  final int managers;
  final int cashiers;
  final int createdToday;
  final int createdMonth;

  const AdminUserMetrics({
    required this.total,
    required this.active,
    required this.inactive,
    required this.admins,
    required this.managers,
    required this.cashiers,
    required this.createdToday,
    required this.createdMonth,
  });

  factory AdminUserMetrics.fromMap(Map<String, dynamic> map) {
    return AdminUserMetrics(
      total: (map['total'] as num? ?? 0).toInt(),
      active: (map['active'] as num? ?? 0).toInt(),
      inactive: (map['inactive'] as num? ?? 0).toInt(),
      admins: (map['admins'] as num? ?? 0).toInt(),
      managers: (map['managers'] as num? ?? 0).toInt(),
      cashiers: (map['cashiers'] as num? ?? 0).toInt(),
      createdToday: (map['created_today'] as num? ?? 0).toInt(),
      createdMonth: (map['created_month'] as num? ?? 0).toInt(),
    );
  }
}

/// Revenue & Transaction metrics aggregated for the Admin Dashboard.
class AdminRevenueMetrics {
  final double todayRevenue;
  final int todayTransactions;
  final double todayAvgTxValue;
  final double weekRevenue;
  final double monthRevenue;
  final double prevMonthRevenue;
  final double revenueGrowthPct;

  const AdminRevenueMetrics({
    required this.todayRevenue,
    required this.todayTransactions,
    required this.todayAvgTxValue,
    required this.weekRevenue,
    required this.monthRevenue,
    required this.prevMonthRevenue,
    required this.revenueGrowthPct,
  });

  factory AdminRevenueMetrics.fromMap(Map<String, dynamic> map) {
    return AdminRevenueMetrics(
      todayRevenue: (map['today_revenue'] as num? ?? 0.0).toDouble(),
      todayTransactions: (map['today_transactions'] as num? ?? 0).toInt(),
      todayAvgTxValue: (map['today_avg_tx_value'] as num? ?? 0.0).toDouble(),
      weekRevenue: (map['week_revenue'] as num? ?? 0.0).toDouble(),
      monthRevenue: (map['month_revenue'] as num? ?? 0.0).toDouble(),
      prevMonthRevenue: (map['prev_month_revenue'] as num? ?? 0.0).toDouble(),
      revenueGrowthPct: (map['revenue_growth_pct'] as num? ?? 0.0).toDouble(),
    );
  }
}

/// Aggregated container for all real-time Admin Dashboard statistics.
class AdminDashboardStats {
  final AdminBusinessMetrics businessMetrics;
  final AdminUserMetrics userMetrics;
  final AdminRevenueMetrics revenueMetrics;

  const AdminDashboardStats({
    required this.businessMetrics,
    required this.userMetrics,
    required this.revenueMetrics,
  });

  factory AdminDashboardStats.fromMap(Map<String, dynamic> map) {
    return AdminDashboardStats(
      businessMetrics: AdminBusinessMetrics.fromMap(
        map['business_metrics'] as Map<String, dynamic>? ?? {},
      ),
      userMetrics: AdminUserMetrics.fromMap(
        map['user_metrics'] as Map<String, dynamic>? ?? {},
      ),
      revenueMetrics: AdminRevenueMetrics.fromMap(
        map['revenue_metrics'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

/// Single data point for time-series revenue and transaction charts.
class RevenueChartPoint {
  final DateTime timestamp;
  final double revenue;
  final double grossSales;
  final double refunds;
  final int transactions;

  const RevenueChartPoint({
    required this.timestamp,
    required this.revenue,
    required this.grossSales,
    required this.refunds,
    required this.transactions,
  });

  factory RevenueChartPoint.fromMap(Map<String, dynamic> map) {
    final rawTs = map['timestamp']?.toString();
    final dt = rawTs != null && rawTs.isNotEmpty
        ? DateTime.parse(rawTs).toLocal()
        : DateTime.now();

    return RevenueChartPoint(
      timestamp: dt,
      revenue: (map['revenue'] as num? ?? 0.0).toDouble(),
      grossSales: (map['gross_sales'] as num? ?? 0.0).toDouble(),
      refunds: (map['refunds'] as num? ?? 0.0).toDouble(),
      transactions: (map['transactions'] as num? ?? 0).toInt(),
    );
  }
}

/// Real activity log entry from the database `activity_logs` table.
class AdminActivityLog {
  final String id;
  final String? businessId;
  final String? businessName;
  final String? userId;
  final String? userName;
  final String type;
  final String title;
  final String details;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const AdminActivityLog({
    required this.id,
    this.businessId,
    this.businessName,
    this.userId,
    this.userName,
    required this.type,
    required this.title,
    required this.details,
    this.metadata,
    required this.createdAt,
  });

  factory AdminActivityLog.fromMap(Map<String, dynamic> map) {
    final rawTs = map['created_at']?.toString();
    final dt = rawTs != null && rawTs.isNotEmpty
        ? DateTime.parse(rawTs).toLocal()
        : DateTime.now();

    final bData = map['businesses'] as Map<String, dynamic>?;
    final pData = map['profiles'] as Map<String, dynamic>?;

    return AdminActivityLog(
      id: map['id']?.toString() ?? '',
      businessId: map['business_id']?.toString(),
      businessName: bData?['name']?.toString() ?? bData?['business_name']?.toString() ?? 'FlexPOS',
      userId: map['user_id']?.toString(),
      userName: pData?['full_name']?.toString() ?? pData?['email']?.toString(),
      type: map['type']?.toString() ?? 'system',
      title: map['title']?.toString() ?? 'Activity Event',
      details: map['details']?.toString() ?? '',
      metadata: map['metadata'] is Map ? Map<String, dynamic>.from(map['metadata'] as Map) : null,
      createdAt: dt,
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }
}

/// Business Unit data model backed by `public.businesses`.
class BusinessUnitModel {
  final String id;
  final String businessName;
  final String ownerId;
  final String? ownerName;
  final String? ownerEmail;
  final String? email;
  final String? phone;
  final String? address;
  final String status; // active, inactive, suspended, archived
  final DateTime createdAt;
  final int userCount;
  final double todaySales;
  final double monthlyRevenue;

  const BusinessUnitModel({
    required this.id,
    required this.businessName,
    required this.ownerId,
    this.ownerName,
    this.ownerEmail,
    this.email,
    this.phone,
    this.address,
    required this.status,
    required this.createdAt,
    this.userCount = 0,
    this.todaySales = 0.0,
    this.monthlyRevenue = 0.0,
  });

  factory BusinessUnitModel.fromMap(
    Map<String, dynamic> map, {
    int userCount = 0,
    double todaySales = 0.0,
    double monthlyRevenue = 0.0,
  }) {
    final rawTs = map['created_at']?.toString();
    final dt = rawTs != null && rawTs.isNotEmpty
        ? DateTime.parse(rawTs).toLocal()
        : DateTime.now();

    final ownerMap = map['profiles'] as Map<String, dynamic>?;
    final rawName = map['name']?.toString() ?? map['business_name']?.toString();
    final name = (rawName == null || rawName.trim().isEmpty || rawName == 'Unnamed Store' || rawName == 'Demo FlexPOS Store')
        ? 'FlexPOS'
        : rawName;

    return BusinessUnitModel(
      id: map['id']?.toString() ?? '',
      businessName: name,
      ownerId: map['owner_id']?.toString() ?? '',
      ownerName: ownerMap?['full_name']?.toString(),
      ownerEmail: ownerMap?['email']?.toString(),
      email: map['email']?.toString(),
      phone: map['phone']?.toString(),
      address: map['address']?.toString(),
      status: map['status']?.toString() ?? 'active',
      createdAt: dt,
      userCount: userCount,
      todaySales: todaySales,
      monthlyRevenue: monthlyRevenue,
    );
  }
}

/// System Setting model.
class SystemSettingModel {
  final String key;
  final String value;
  final String? description;
  final DateTime updatedAt;

  const SystemSettingModel({
    required this.key,
    required this.value,
    this.description,
    required this.updatedAt,
  });

  factory SystemSettingModel.fromMap(Map<String, dynamic> map) {
    final rawTs = map['updated_at']?.toString();
    final dt = rawTs != null && rawTs.isNotEmpty
        ? DateTime.parse(rawTs).toLocal()
        : DateTime.now();

    return SystemSettingModel(
      key: map['key']?.toString() ?? '',
      value: map['value']?.toString() ?? '',
      description: map['description']?.toString(),
      updatedAt: dt,
    );
  }
}

/// User Summary model for Admin User Management view.
class AdminUserSummary {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String status;
  final String? businessName;
  final DateTime createdAt;

  const AdminUserSummary({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.businessName,
    required this.createdAt,
  });

  factory AdminUserSummary.fromMap(Map<String, dynamic> map) {
    final rawTs = map['created_at']?.toString();
    final dt = rawTs != null && rawTs.isNotEmpty
        ? DateTime.parse(rawTs).toLocal()
        : DateTime.now();

    Map<String, dynamic>? empMap;
    final rawEmployees = map['employees'];
    if (rawEmployees is Map) {
      empMap = Map<String, dynamic>.from(rawEmployees);
    } else if (rawEmployees is List && rawEmployees.isNotEmpty) {
      final firstItem = rawEmployees.first;
      if (firstItem is Map) {
        empMap = Map<String, dynamic>.from(firstItem);
      }
    }

    String bName = 'FlexPOS';
    String empStatus = 'active';

    if (empMap != null) {
      empStatus = empMap['status']?.toString() ?? 'active';

      final rawBusinesses = empMap['businesses'];
      Map<String, dynamic>? bMap;
      if (rawBusinesses is Map) {
        bMap = Map<String, dynamic>.from(rawBusinesses);
      } else if (rawBusinesses is List && rawBusinesses.isNotEmpty) {
        final firstB = rawBusinesses.first;
        if (firstB is Map) {
          bMap = Map<String, dynamic>.from(firstB);
        }
      }

      if (bMap != null) {
        final fetchedName = bMap['business_name']?.toString() ?? bMap['name']?.toString();
        if (fetchedName != null && fetchedName.isNotEmpty) {
          bName = fetchedName;
        }
      }
    }

    final rawName = map['full_name']?.toString();
    final rawEmail = map['email']?.toString() ?? 'No Email';
    final String displayName;
    if (rawName != null && rawName.trim().isNotEmpty) {
      displayName = rawName.trim();
    } else if (rawEmail.contains('@')) {
      displayName = rawEmail.split('@').first;
    } else {
      displayName = 'User';
    }

    final rawRole = map['role']?.toString();
    final role = (rawRole != null && rawRole.trim().isNotEmpty)
        ? rawRole.trim().toLowerCase()
        : 'cashier';

    return AdminUserSummary(
      id: map['id']?.toString() ?? '',
      email: rawEmail,
      fullName: displayName,
      role: role,
      status: empStatus,
      businessName: bName,
      createdAt: dt,
    );
  }
}
