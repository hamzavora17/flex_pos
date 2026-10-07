import 'package:flutter/material.dart';

import '../../../models/admin_models.dart';
import '../../../services/admin_dashboard_service.dart';

/// User Management View integrating with existing AdminUserService and Assign Manager / Role flow.
class AdminUserManagementView extends StatefulWidget {
  final AdminDashboardService adminService;
  final VoidCallback onAssignRoleRequested;

  const AdminUserManagementView({
    super.key,
    required this.adminService,
    required this.onAssignRoleRequested,
  });

  @override
  State<AdminUserManagementView> createState() => _AdminUserManagementViewState();
}

class _AdminUserManagementViewState extends State<AdminUserManagementView> {
  List<AdminUserSummary> _users = [];
  bool _isLoading = true;
  String? _errorMessage;

  String _searchQuery = '';
  String _roleFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await widget.adminService.getAdminUsers(
        searchQuery: _searchQuery,
        roleFilter: _roleFilter,
      );
      if (mounted) {
        setState(() {
          _users = list;
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
    final total = _users.length;
    final admins = _users.where((u) => u.role == 'admin').length;
    final managers = _users.where((u) => u.role == 'manager').length;
    final cashiers = _users.where((u) => u.role == 'cashier' || u.role == 'employee').length;

    return Padding(
      padding: const EdgeInsets.all(24.0),
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
                  const Text(
                    'User Management & Roles',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  Text('System users, store assignments, role authorizations, and staff discovery', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.manage_accounts, size: 18),
                label: const Text('Assign Manager / Role'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: widget.onAssignRoleRequested,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // User Summary Cards
          Row(
            children: [
              _buildSummaryCard('Total Registered Users', '$total', Icons.people, Colors.blue),
              const SizedBox(width: 16),
              _buildSummaryCard('Administrators', '$admins', Icons.security, Colors.purple),
              const SizedBox(width: 16),
              _buildSummaryCard('Store Managers', '$managers', Icons.supervisor_account, Colors.amber.shade800),
              const SizedBox(width: 16),
              _buildSummaryCard('Cashiers / Staff', '$cashiers', Icons.badge, Colors.green),
            ],
          ),
          const SizedBox(height: 20),

          // Search and Filters
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
                      hintText: 'Search user by name, email, or store...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (val) {
                      _searchQuery = val;
                      _loadUsers();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _roleFilter,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Roles')),
                    DropdownMenuItem(value: 'admin', child: Text('Admins')),
                    DropdownMenuItem(value: 'manager', child: Text('Managers')),
                    DropdownMenuItem(value: 'cashier', child: Text('Cashiers')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _roleFilter = val);
                      _loadUsers();
                    }
                  },
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadUsers,
                  tooltip: 'Reload Users',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // User Table Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      )
                    : _users.isEmpty
                        ? const Center(
                            child: Text('No users match your criteria.', style: TextStyle(color: Colors.grey)),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: ListView.separated(
                              itemCount: _users.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              itemBuilder: (context, index) {
                                final u = _users[index];
                                return _buildUserTile(u);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String countText, IconData icon, Color color) {
    return Expanded(
      child: Container(
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
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                Text(countText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTile(AdminUserSummary u) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: _getRoleColor(u.role).withValues(alpha: 0.1),
        child: Icon(_getRoleIcon(u.role), color: _getRoleColor(u.role), size: 18),
      ),
      title: Row(
        children: [
          Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 8),
          _buildRoleBadge(u.role),
        ],
      ),
      subtitle: Text('Email: ${u.email} • Store: ${u.businessName ?? 'Unassigned'}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: ElevatedButton.icon(
        icon: const Icon(Icons.manage_accounts, size: 14),
        label: const Text('Assign Role'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF003366),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontSize: 12),
        ),
        onPressed: widget.onAssignRoleRequested,
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    final color = _getRoleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.purple;
      case 'manager':
        return Colors.amber.shade800;
      case 'cashier':
      case 'employee':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Icons.security;
      case 'manager':
        return Icons.supervisor_account;
      case 'cashier':
      case 'employee':
        return Icons.badge;
      default:
        return Icons.person;
    }
  }
}
