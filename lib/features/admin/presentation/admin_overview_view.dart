import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/admin_models.dart';
import 'admin_revenue_chart.dart';

/// Live Overview tab for the Admin Control Center.
class AdminOverviewView extends StatelessWidget {
  final AdminDashboardStats? stats;
  final List<RevenueChartPoint> chartPoints;
  final List<AdminActivityLog> recentActivities;
  final String chartPeriod;
  final ValueChanged<String> onChartPeriodChanged;
  final VoidCallback onRefresh;
  final VoidCallback onAssignRoleRequested;
  final bool isLoading;
  final String? errorMessage;

  const AdminOverviewView({
    super.key,
    required this.stats,
    required this.chartPoints,
    required this.recentActivities,
    required this.chartPeriod,
    required this.onChartPeriodChanged,
    required this.onRefresh,
    required this.onAssignRoleRequested,
    this.isLoading = false,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && stats == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to live database analytics...'),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null && stats == null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Failed to Load Admin Analytics',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003366),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final uMetrics = stats?.userMetrics;
    final rMetrics = stats?.revenueMetrics;

    final isDesktop = MediaQuery.of(context).size.width > 900;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'System-Wide Admin Control Center',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('Live Database Connected • Realtime Sync Active', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh Analytics',
                    onPressed: onRefresh,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.manage_accounts, size: 18),
                    label: const Text('Assign Manager / Role'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onAssignRoleRequested,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // KPI Cards Row
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width > 1100 ? 4 : (width > 600 ? 2 : 1);

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildKpiCard(
                    width: (width - (crossAxisCount - 1) * 16) / crossAxisCount,
                    title: 'FlexPOS Store',
                    value: 'FlexPOS',
                    subtitle: 'Main Business Unit • Active',
                    badgeText: 'ONLINE',
                    badgeColor: Colors.green,
                    icon: Icons.store,
                    color: Colors.blue.shade700,
                  ),
                  _buildKpiCard(
                    width: (width - (crossAxisCount - 1) * 16) / crossAxisCount,
                    title: 'Active Users',
                    value: '${uMetrics?.active ?? 0}',
                    subtitle: '${uMetrics?.managers ?? 0} Managers • ${uMetrics?.cashiers ?? 0} Cashiers',
                    badgeText: '${uMetrics?.admins ?? 0} Admins',
                    icon: Icons.people,
                    color: Colors.green.shade700,
                  ),
                  _buildKpiCard(
                    width: (width - (crossAxisCount - 1) * 16) / crossAxisCount,
                    title: "Today's Sales Revenue",
                    value: CurrencyFormatter.format(rMetrics?.todayRevenue ?? 0.0),
                    subtitle: '${rMetrics?.todayTransactions ?? 0} Transactions (Avg ${CurrencyFormatter.format(rMetrics?.todayAvgTxValue ?? 0.0)})',
                    badgeText: 'Today',
                    icon: Icons.payments,
                    color: Colors.amber.shade800,
                  ),
                  _buildKpiCard(
                    width: (width - (crossAxisCount - 1) * 16) / crossAxisCount,
                    title: 'Monthly Revenue',
                    value: CurrencyFormatter.format(rMetrics?.monthRevenue ?? 0.0),
                    subtitle: 'Prev Month: ${CurrencyFormatter.format(rMetrics?.prevMonthRevenue ?? 0.0)}',
                    badgeText: '${(rMetrics?.revenueGrowthPct ?? 0) >= 0 ? '+' : ''}${(rMetrics?.revenueGrowthPct ?? 0).toStringAsFixed(1)}%',
                    badgeColor: (rMetrics?.revenueGrowthPct ?? 0) >= 0 ? Colors.green : Colors.red,
                    icon: Icons.currency_rupee,
                    color: Colors.purple.shade700,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Interactive Time-Series Revenue Chart
          AdminRevenueChartCard(
            points: chartPoints,
            activePeriod: chartPeriod,
            onPeriodChanged: onChartPeriodChanged,
            isLoading: isLoading,
          ),
          const SizedBox(height: 24),

          // Recent Activity & Role Breakdown Row
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildRecentActivitySection(),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 2,
                  child: _buildRoleBreakdownSection(uMetrics),
                ),
              ],
            )
          else ...[
            _buildRecentActivitySection(),
            const SizedBox(height: 20),
            _buildRoleBreakdownSection(uMetrics),
          ],
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required double width,
    required String title,
    required String value,
    required String subtitle,
    required String badgeText,
    Color badgeColor = Colors.blue,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitySection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live System Activity Feed',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          Text('Real-time database audit log from cashiers, managers and system events', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 16),
          if (recentActivities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32.0),
              child: Center(
                child: Text(
                  'No recent activity records found.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentActivities.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final act = recentActivities[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: _getActivityIconColor(act.type).withValues(alpha: 0.1),
                    child: Icon(_getActivityIcon(act.type), color: _getActivityIconColor(act.type), size: 18),
                  ),
                  title: Text(
                    act.title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                  ),
                  subtitle: Text(
                    '${act.details}${act.userName != null ? ' • by ${act.userName}' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  trailing: Text(
                    act.timeAgo,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRoleBreakdownSection(AdminUserMetrics? uMetrics) {
    final total = (uMetrics?.total ?? 1) > 0 ? (uMetrics?.total ?? 1) : 1;
    final adminPct = (((uMetrics?.admins ?? 0) / total) * 100).toStringAsFixed(0);
    final managerPct = (((uMetrics?.managers ?? 0) / total) * 100).toStringAsFixed(0);
    final cashierPct = (((uMetrics?.cashiers ?? 0) / total) * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'User & Role Distribution',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          Text('System accounts grouped by assigned access role', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 20),
          _buildRoleRow('Administrators', '${uMetrics?.admins ?? 0}', '$adminPct%', Colors.purple),
          const SizedBox(height: 12),
          _buildRoleRow('Store Managers', '${uMetrics?.managers ?? 0}', '$managerPct%', Colors.blue),
          const SizedBox(height: 12),
          _buildRoleRow('Cashiers & Staff', '${uMetrics?.cashiers ?? 0}', '$cashierPct%', Colors.green),
          const SizedBox(height: 20),
          const Divider(color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Active System Users:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('${uMetrics?.active ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Inactive Accounts:', style: TextStyle(color: Colors.grey, fontSize: 13)),
              Text('${uMetrics?.inactive ?? 0}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleRow(String roleLabel, String countText, String pctText, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(roleLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            Text('$countText ($pctText)', style: TextStyle(color: Colors.grey[700], fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'sale':
        return Icons.shopping_cart;
      case 'return':
        return Icons.assignment_return;
      case 'business_created':
      case 'business_updated':
        return Icons.business;
      case 'user_created':
      case 'role_changed':
        return Icons.manage_accounts;
      default:
        return Icons.notifications;
    }
  }

  Color _getActivityIconColor(String type) {
    switch (type) {
      case 'sale':
        return Colors.green;
      case 'return':
        return Colors.orange;
      case 'business_created':
      case 'business_updated':
        return Colors.blue;
      case 'user_created':
      case 'role_changed':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
