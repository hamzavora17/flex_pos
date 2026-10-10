import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/admin_models.dart';
import '../../../services/admin_dashboard_service.dart';
import 'admin_business_detail_dialog.dart';

/// Single-business management view for FlexPOS in the Admin Control Center.
class AdminBusinessUnitsView extends StatefulWidget {
  final AdminDashboardService adminService;

  const AdminBusinessUnitsView({
    super.key,
    required this.adminService,
  });

  @override
  State<AdminBusinessUnitsView> createState() => _AdminBusinessUnitsViewState();
}

class _AdminBusinessUnitsViewState extends State<AdminBusinessUnitsView> {
  List<BusinessUnitModel> _businesses = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  Future<void> _loadBusinesses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await widget.adminService.getBusinessUnits();
      if (mounted) {
        setState(() {
          _businesses = list;
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

  void _showBusinessDetails(BusinessUnitModel business) {
    showDialog(
      context: context,
      builder: (_) => AdminBusinessDetailDialog(
        businessId: business.id,
        adminService: widget.adminService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Business Unit Management',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'FlexPOS store configuration, owner profile, operational status, and sales metrics',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh Data'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF003366),
                  side: const BorderSide(color: Color(0xFF003366)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _loadBusinesses,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Single Store Status Header Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'FlexPOS • Single-Business System Active',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    'OPERATIONAL',
                    style: TextStyle(color: Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Business Unit Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : _businesses.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.storefront_outlined, size: 64, color: Colors.grey),
                                const SizedBox(height: 16),
                                const Text(
                                  'FlexPOS business unit initialization pending.',
                                  style: TextStyle(color: Colors.grey, fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _loadBusinesses,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry Loading'),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _businesses.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final b = _businesses[index];
                              return _buildBusinessCard(b);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessCard(BusinessUnitModel b) {
    // Ensure display name is strictly FlexPOS
    final displayName = (b.businessName.isEmpty || b.businessName == 'Unnamed Store' || b.businessName == 'Demo FlexPOS Store')
        ? 'FlexPOS'
        : b.businessName;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF003366).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.store, color: Color(0xFF003366), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(width: 10),
                    _buildStatusBadge(b.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Owner: ${b.ownerName ?? b.ownerEmail ?? b.ownerId} • Email: ${b.email ?? 'Not set'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's Sales: ${CurrencyFormatter.format(b.todaySales)}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Monthly: ${CurrencyFormatter.format(b.monthlyRevenue)} • ${b.userCount} Staff',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text('View Details'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showBusinessDetails(b),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = Colors.green.shade50;
    Color fg = Colors.green.shade800;

    if (status == 'inactive') {
      bg = Colors.red.shade50;
      fg = Colors.red.shade800;
    } else if (status == 'suspended') {
      bg = Colors.amber.shade50;
      fg = Colors.amber.shade900;
    } else if (status == 'archived') {
      bg = Colors.grey.shade100;
      fg = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
