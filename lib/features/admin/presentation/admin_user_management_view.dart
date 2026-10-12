import 'package:flutter/material.dart';

import '../../../models/admin_models.dart';
import '../../../services/admin_dashboard_service.dart';
import '../../../services/admin_user_service.dart';

/// User Management View integrating with AdminUserService for creating, editing, deleting, and role assignments.
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
  final AdminUserService _adminUserService = AdminUserService();
  List<AdminUserSummary> _allUsers = [];
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
      final list = await widget.adminService.getAdminUsers();
      if (mounted) {
        setState(() {
          _allUsers = list;
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

  List<AdminUserSummary> get _filteredUsers {
    return _allUsers.where((u) {
      // Exclude Admin details/users from staff management view
      if (u.role == 'admin') return false;

      // Role Filter
      if (_roleFilter != 'all') {
        if (_roleFilter == 'cashier') {
          if (u.role != 'cashier' && u.role != 'employee') return false;
        } else if (u.role != _roleFilter) {
          return false;
        }
      }

      // Search Query
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final nameMatch = u.fullName.toLowerCase().contains(q);
        final emailMatch = u.email.toLowerCase().contains(q);
        final bMatch = (u.businessName ?? '').toLowerCase().contains(q);
        if (!nameMatch && !emailMatch && !bMatch) return false;
      }

      return true;
    }).toList();
  }

  void _showCreateUserModal() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'cashier';
    bool obscurePassword = true;
    bool isSubmitting = false;
    String? modalError;

    String generatePassword() {
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
      final rnd = DateTime.now().microsecondsSinceEpoch;
      return List.generate(8, (i) => chars[(rnd + i * 17) % chars.length]).join();
    }

    passwordController.text = generatePassword();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.person_add_rounded, color: Color(0xFF003366)),
              SizedBox(width: 12),
              Text('Create New User', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (modalError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(modalError!, style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name *',
                      hintText: 'e.g. John Doe',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Username or Email *',
                      hintText: 'e.g. john or john@flexpos.com',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password *',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            suffixIcon: IconButton(
                              icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility, size: 18),
                              onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Generate Password',
                        icon: const Icon(Icons.autorenew_rounded, color: Color(0xFF003366)),
                        onPressed: () => setModalState(() => passwordController.text = generatePassword()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role Authorization',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cashier', child: Text('Cashier / Staff')),
                      DropdownMenuItem(value: 'manager', child: Text('Store Manager')),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedRole = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
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
                      final name = nameController.text.trim();
                      final email = emailController.text.trim();
                      final pass = passwordController.text.trim();

                      if (name.isEmpty) {
                        setModalState(() => modalError = 'Please enter user full name.');
                        return;
                      }
                      if (email.isEmpty) {
                        setModalState(() => modalError = 'Please enter user email or username.');
                        return;
                      }
                      if (pass.length < 6) {
                        setModalState(() => modalError = 'Password must be at least 6 characters.');
                        return;
                      }

                      final messenger = ScaffoldMessenger.of(context);
                      setModalState(() {
                        isSubmitting = true;
                        modalError = null;
                      });

                      try {
                        await _adminUserService.createUser(
                          fullName: name,
                          email: email,
                          password: pass,
                          role: selectedRole,
                        );

                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF003366),
                              duration: const Duration(seconds: 3),
                              content: Row(
                                children: [
                                  Expanded(child: Text('User "$name" created successfully! Password: $pass')),
                                  TextButton(
                                    onPressed: () => messenger.hideCurrentSnackBar(),
                                    child: const Text('DISMISS', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          );
                          _loadUsers();
                        }
                      } catch (e) {
                        setModalState(() {
                          isSubmitting = false;
                          modalError = e.toString().replaceAll('FlexPOSException: ', '');
                        });
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create User'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditUserModal(AdminUserSummary u) {
    final nameController = TextEditingController(text: u.fullName);
    final emailController = TextEditingController(text: u.email);
    final passwordController = TextEditingController();
    String selectedRole = u.role.isEmpty ? 'cashier' : u.role;
    if (selectedRole == 'employee') selectedRole = 'cashier';
    bool obscurePassword = true;
    bool isSubmitting = false;
    String? modalError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.edit_rounded, color: Color(0xFF003366)),
              const SizedBox(width: 12),
              Expanded(child: Text('Edit User: ${u.fullName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (modalError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(modalError!, style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: ['manager', 'cashier'].contains(selectedRole) ? selectedRole : 'cashier',
                    decoration: const InputDecoration(
                      labelText: 'Role Authorization',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cashier', child: Text('Cashier / Staff')),
                      DropdownMenuItem(value: 'manager', child: Text('Store Manager')),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedRole = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'New Password (Optional)',
                      hintText: 'Leave blank to keep current password',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility, size: 18),
                        onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
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
                      final name = nameController.text.trim();
                      final email = emailController.text.trim();
                      final pass = passwordController.text.trim();

                      if (name.isEmpty) {
                        setModalState(() => modalError = 'Please enter user full name.');
                        return;
                      }
                      if (email.isEmpty) {
                        setModalState(() => modalError = 'Please enter user email.');
                        return;
                      }
                      if (pass.isNotEmpty && pass.length < 6) {
                        setModalState(() => modalError = 'New password must be at least 6 characters.');
                        return;
                      }

                      final messenger = ScaffoldMessenger.of(context);
                      setModalState(() {
                        isSubmitting = true;
                        modalError = null;
                      });

                      try {
                        await _adminUserService.updateUser(
                          userId: u.id,
                          fullName: name,
                          email: email,
                          role: selectedRole,
                          newPassword: pass.isNotEmpty ? pass : null,
                        );

                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF003366),
                              duration: const Duration(seconds: 3),
                              content: Row(
                                children: [
                                  Expanded(child: Text('User details updated for "$name"!')),
                                  TextButton(
                                    onPressed: () => messenger.hideCurrentSnackBar(),
                                    child: const Text('DISMISS', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          );
                          _loadUsers();
                        }
                      } catch (e) {
                        setModalState(() {
                          isSubmitting = false;
                          modalError = e.toString().replaceAll('FlexPOSException: ', '');
                        });
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmModal(AdminUserSummary u) {
    bool isDeleting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 12),
              Text('Confirm Delete User', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to permanently delete user "${u.fullName}" (${u.email})?',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Text(
                'This will revoke their store access, delete their profile record, and remove all role permissions. This action cannot be undone.',
                style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever, size: 16),
              label: const Text('Delete User'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: isDeleting
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      setModalState(() => isDeleting = true);

                      try {
                        await _adminUserService.deleteUser(u.id);

                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red.shade900,
                              duration: const Duration(seconds: 3),
                              content: Row(
                                children: [
                                  Expanded(child: Text('User account "${u.fullName}" deleted.')),
                                  TextButton(
                                    onPressed: () => messenger.hideCurrentSnackBar(),
                                    child: const Text('DISMISS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          );
                          _loadUsers();
                        }
                      } catch (e) {
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red,
                              content: Text('Failed to delete user: ${e.toString().replaceAll("FlexPOSException: ", "")}'),
                            ),
                          );
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staffUsers = _allUsers.where((u) => u.role != 'admin').toList();
    final totalStaff = staffUsers.length;
    final managers = staffUsers.where((u) => u.role == 'manager').length;
    final cashiers = staffUsers.where((u) => u.role == 'cashier' || u.role == 'employee').length;

    final displayUsers = _filteredUsers;

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
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Create New User', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                    onPressed: _showCreateUserModal,
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.manage_accounts, size: 18),
                    label: const Text('Assign Manager / Role'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF003366),
                      side: const BorderSide(color: Color(0xFF003366)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: widget.onAssignRoleRequested,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // User Summary Cards
          Row(
            children: [
              _buildSummaryCard('Total Staff Members', '$totalStaff', Icons.people, Colors.blue),
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
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: (_roleFilter == 'admin') ? 'all' : _roleFilter,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Staff')),
                    DropdownMenuItem(value: 'manager', child: Text('Managers')),
                    DropdownMenuItem(value: 'cashier', child: Text('Cashiers')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _roleFilter = val);
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
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 32),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Retry'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _loadUsers,
                              ),
                            ],
                          ),
                        ),
                      )
                    : _allUsers.isEmpty
                        ? const Center(
                            child: Text('No registered users found in the system.', style: TextStyle(color: Colors.grey)),
                          )
                        : displayUsers.isEmpty
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
                                  itemCount: displayUsers.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                  itemBuilder: (context, index) {
                                    final u = displayUsers[index];
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Color(0xFF003366), size: 20),
            tooltip: 'Edit User Details',
            onPressed: () => _showEditUserModal(u),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
            tooltip: 'Delete User Account',
            onPressed: () => _showDeleteConfirmModal(u),
          ),
        ],
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
