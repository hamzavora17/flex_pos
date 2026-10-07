import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/admin_models.dart';
import '../../../services/admin_dashboard_service.dart';
import 'admin_business_detail_dialog.dart';

/// Interactive Business Units management view for the Admin Panel.
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

  String _searchQuery = '';
  String _statusFilter = 'all';

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
      final list = await widget.adminService.getBusinessUnits(
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
      );
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

  Future<void> _showAddBusinessDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogErr;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.store, color: Color(0xFF003366)),
                  SizedBox(width: 8),
                  Text('Register New Business Store'),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (dialogErr != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(dialogErr!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Business Name *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.business),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty ? 'Business name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'Business Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Contact Phone',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(
                          labelText: 'Physical Address',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_on),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003366),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() {
                            isSubmitting = true;
                            dialogErr = null;
                          });

                          try {
                            await widget.adminService.createBusiness(
                              name: nameController.text,
                              email: emailController.text,
                              phone: phoneController.text,
                              address: addressController.text,
                            );

                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Business "${nameController.text}" successfully created!'),
                                  backgroundColor: Colors.green[800],
                                ),
                              );
                              _loadBusinesses();
                            }
                          } catch (e) {
                            setDialogState(() {
                              isSubmitting = false;
                              dialogErr = e.toString().replaceAll('Exception: ', '');
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Create Store'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    addressController.dispose();
  }

  Future<void> _updateStatus(BusinessUnitModel business, String newStatus) async {
    try {
      await widget.adminService.manageBusinessStatus(business.id, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Business "${business.businessName}" status updated to ${newStatus.toUpperCase()}'),
            backgroundColor: Colors.green[800],
          ),
        );
        _loadBusinesses();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
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
                    'Business Units Management',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  Text('Manage store locations, owner profiles, operational status, and metrics', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_business, size: 18),
                label: const Text('Add Business Store'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _showAddBusinessDialog,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Search and Filters Bar
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
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search business by name, owner, or email...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (val) {
                      _searchQuery = val;
                      _loadBusinesses();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _statusFilter,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                    DropdownMenuItem(value: 'active', child: Text('Active Only')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive Only')),
                    DropdownMenuItem(value: 'suspended', child: Text('Suspended Only')),
                    DropdownMenuItem(value: 'archived', child: Text('Archived Only')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _statusFilter = val);
                      _loadBusinesses();
                    }
                  },
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadBusinesses,
                  tooltip: 'Reload Businesses',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Business Units Content
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
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.storefront_outlined, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'No business units match your search or criteria.',
                                  style: TextStyle(color: Colors.grey, fontSize: 16),
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
                      b.businessName,
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
              OutlinedButton.icon(
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text('View Details'),
                onPressed: () => _showBusinessDetails(b),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Change Status',
                onSelected: (val) => _updateStatus(b, val),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'active', child: Text('Set Active')),
                  PopupMenuItem(value: 'inactive', child: Text('Set Inactive')),
                  PopupMenuItem(value: 'suspended', child: Text('Set Suspended')),
                  PopupMenuItem(value: 'archived', child: Text('Archive Store')),
                ],
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
