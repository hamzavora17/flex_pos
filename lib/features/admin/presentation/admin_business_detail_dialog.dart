import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/admin_models.dart';
import '../../../services/admin_dashboard_service.dart';

/// Modal dialog showing comprehensive operational health and staff details for a selected business.
class AdminBusinessDetailDialog extends StatefulWidget {
  final String businessId;
  final AdminDashboardService adminService;

  const AdminBusinessDetailDialog({
    super.key,
    required this.businessId,
    required this.adminService,
  });

  @override
  State<AdminBusinessDetailDialog> createState() => _AdminBusinessDetailDialogState();
}

class _AdminBusinessDetailDialogState extends State<AdminBusinessDetailDialog> {
  Map<String, dynamic>? _details;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final res = await widget.adminService.getBusinessDetails(widget.businessId);
      if (mounted) {
        setState(() {
          _details = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final business = _details!['business'] as BusinessUnitModel;
    final employees = (_details!['employees'] as List<dynamic>? ?? []);
    final recentSales = (_details!['recent_sales'] as List<dynamic>? ?? []);

    final double todayRev = (_details!['today_revenue'] as num? ?? 0.0).toDouble();
    final int todayTx = (_details!['today_transactions'] as num? ?? 0).toInt();
    final double monthRev = (_details!['monthly_revenue'] as num? ?? 0.0).toDouble();
    final int monthTx = (_details!['monthly_transactions'] as num? ?? 0).toInt();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    business.businessName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 2),
                  Text('Business ID: ${business.id}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(height: 24),

          // Operational KPIs
          Row(
            children: [
              _buildMiniKpi("Today's Revenue", CurrencyFormatter.format(todayRev), '$todayTx sales', Colors.blue),
              const SizedBox(width: 12),
              _buildMiniKpi("Monthly Revenue", CurrencyFormatter.format(monthRev), '$monthTx sales', Colors.purple),
              const SizedBox(width: 12),
              _buildMiniKpi("Staff Count", '${employees.length} Users', 'Assigned staff', Colors.green),
            ],
          ),
          const SizedBox(height: 24),

          // Business Metadata
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Business Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Text('Owner Name / Email: ${business.ownerName ?? business.ownerEmail ?? business.ownerId}'),
                Text('Contact Email: ${business.email ?? 'N/A'}'),
                Text('Contact Phone: ${business.phone ?? 'N/A'}'),
                Text('Address: ${business.address ?? 'N/A'}'),
                Text('Status: ${business.status.toUpperCase()}'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Assigned Staff
          const Text('Assigned Store Staff', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (employees.isEmpty)
            const Text('No store staff assigned to this business.', style: TextStyle(color: Colors.grey))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: employees.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final emp = employees[index] as Map<String, dynamic>;
                final pData = emp['profiles'] as Map<String, dynamic>?;
                final name = pData?['full_name']?.toString() ?? 'Staff User';
                final email = pData?['email']?.toString() ?? 'No email';
                final position = emp['position']?.toString() ?? 'cashier';

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade50,
                    child: Icon(position == 'manager' ? Icons.supervisor_account : Icons.person, color: Colors.blue, size: 16),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$email • Role: ${position.toUpperCase()}'),
                );
              },
            ),
          const SizedBox(height: 24),

          // Recent Sales
          const Text('Recent Store Sales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (recentSales.isEmpty)
            const Text('No sales created for this business yet.', style: TextStyle(color: Colors.grey))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentSales.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final sale = recentSales[index] as Map<String, dynamic>;
                final inv = sale['invoice_number']?.toString() ?? 'INV';
                final total = (sale['total'] as num? ?? 0.0).toDouble();

                return ListTile(
                  dense: true,
                  title: Text('Invoice: $inv', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Total: ${CurrencyFormatter.format(total)}'),
                  trailing: const Icon(Icons.check_circle, color: Colors.green, size: 16),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMiniKpi(String label, String value, String sub, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
