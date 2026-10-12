import 'package:flutter/material.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../core/theme/theme_toggle_button.dart';
import '../../../models/admin_models.dart';
import '../../../models/user_role.dart';
import '../../../services/admin_dashboard_service.dart';
import '../../../services/admin_user_service.dart';
import '../../../services/password_reset_service.dart';
import '../../../services/exceptions.dart';
import '../../../main.dart';
import '../../../core/theme/app_logo_widget.dart';
import '../../../core/theme/app_name_controller.dart';
import 'admin_notifications_view.dart';
import 'admin_overview_view.dart';
import 'admin_settings_view.dart';
import 'admin_support_view.dart';
import 'admin_system_health_view.dart';
import 'admin_user_management_view.dart';

/// Main container screen for the FlexPOS Admin Control Center.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminDashboardService _adminService = AdminDashboardService();
  final AdminUserService _adminUserService = AdminUserService();
  final PasswordResetService _passwordResetService = PasswordResetService();

  int _selectedTabIndex = 0;

  AdminDashboardStats? _stats;
  List<RevenueChartPoint> _chartPoints = [];
  List<AdminActivityLog> _recentActivities = [];
  int _pendingResetCount = 0;

  String _chartPeriod = 'last_7_days';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAllDashboardData();
    _adminService.subscribeToRealtimeChanges(_handleRealtimeEvent);
  }

  @override
  void dispose() {
    _adminService.unsubscribeRealtime();
    super.dispose();
  }

  void _handleRealtimeEvent() {
    debugPrint('[AdminDashboardScreen] Realtime change detected. Auto-refreshing dashboard...');
    if (mounted) {
      _loadAllDashboardData(silent: true);
    }
  }

  Future<void> _loadAllDashboardData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final statsFuture = _adminService.getDashboardStats();
      final chartFuture = _adminService.getRevenueChartData(period: _chartPeriod);
      final activityFuture = _adminService.getActivityLogs(limit: 10);
      final resetCountFuture = _passwordResetService.getPendingRequestsCount();

      final results = await Future.wait([statsFuture, chartFuture, activityFuture, resetCountFuture]);

      if (mounted) {
        setState(() {
          _stats = results[0] as AdminDashboardStats;
          _chartPoints = results[1] as List<RevenueChartPoint>;
          _recentActivities = results[2] as List<AdminActivityLog>;
          _pendingResetCount = results[3] as int;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AdminDashboardScreen] Error loading dashboard data: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onChartPeriodChanged(String newPeriod) async {
    setState(() => _chartPeriod = newPeriod);
    try {
      final points = await _adminService.getRevenueChartData(period: newPeriod);
      if (mounted) {
        setState(() => _chartPoints = points);
      }
    } catch (e) {
      debugPrint('[AdminDashboardScreen] Error updating chart period: $e');
    }
  }

  String _getNotificationButtonLabel(int count) {
    if (count <= 0) return 'Notifications';
    const circled = ['❶', '❷', '❸', '❹', '❺', '❻', '❼', '❽', '❾', '❿'];
    if (count <= 10) {
      return 'Notifications ${circled[count - 1]}';
    }
    return 'Notifications ($count)';
  }

  void _showAssignRoleDialog(BuildContext context) {
    UserRole selectedRole = UserRole.manager;
    Map<String, String>? selectedUser;
    bool isSubmitting = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<List<Map<String, String>>>(
          future: _adminUserService.getAssignableUsers(),
          builder: (context, snapshot) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AlertDialog(
                    content: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(width: 16),
                          Text('Loading eligible user profiles...'),
                        ],
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  final rawError = snapshot.error;
                  final displayErr = rawError is FlexPOSException
                      ? rawError.message
                      : (rawError?.toString().replaceAll('Exception: ', '') ?? 'An unknown error occurred.');

                  return AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Error Loading Users'),
                      ],
                    ),
                    content: SingleChildScrollView(
                      child: Text(displayErr),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  );
                }

                final users = snapshot.data ?? [];
                if (users.isEmpty) {
                  return AlertDialog(
                    title: const Text('Assign Manager or Cashier Role'),
                    content: const Text(
                      'No unassigned system accounts were found in auth.users or profiles.\n\nAll existing users already have active roles.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  );
                }

                selectedUser ??= users.first;

                return AlertDialog(
                  title: const Text('Assign Manager or Cashier Role'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    errorMessage!,
                                    style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        const Text('Select Unassigned User Account:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<Map<String, String>>(
                          initialValue: selectedUser,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: users.map((u) {
                            return DropdownMenuItem<Map<String, String>>(
                              value: u,
                              child: Text('${u['email']} (${u['fullName'] ?? 'User'})'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedUser = val);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        const Text('Assign Store Role:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<UserRole>(
                          initialValue: selectedRole,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: const [
                            DropdownMenuItem(value: UserRole.manager, child: Text('Manager')),
                            DropdownMenuItem(value: UserRole.cashier, child: Text('Cashier / Employee')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedRole = val);
                            }
                          },
                        ),
                      ],
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
                      onPressed: (isSubmitting || selectedUser == null)
                          ? null
                          : () async {
                              final targetUuid = selectedUser!['id'];
                              if (targetUuid == null || targetUuid.isEmpty) {
                                setDialogState(() {
                                  errorMessage = 'Selected user has no valid Profile UUID.';
                                });
                                return;
                              }

                              setDialogState(() {
                                isSubmitting = true;
                                errorMessage = null;
                              });

                              try {
                                await _adminUserService.assignUserRole(
                                  targetUserId: targetUuid,
                                  role: selectedRole,
                                );

                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Successfully assigned ${selectedUser!['email']} as ${selectedRole.label}!'),
                                      backgroundColor: Colors.green[800],
                                    ),
                                  );
                                  _loadAllDashboardData(silent: true);
                                }
                              } catch (e) {
                                setDialogState(() {
                                  isSubmitting = false;
                                  errorMessage = e.toString().replaceAll('Exception: ', '');
                                });
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Assign Role'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        title: Row(
          children: [
            if (!isDesktop) ...[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const AppLogoWidget(height: 24),
              ),
              const SizedBox(width: 12),
            ],
            const AppNameText(suffix: ' Admin Control Center', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Live Notifications Button linked to Forgot Password requests
          TextButton.icon(
            style: TextButton.styleFrom(
              backgroundColor: _pendingResetCount > 0 ? Colors.amber.shade700 : Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: Icon(
              _pendingResetCount > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
              size: 18,
            ),
            label: Text(
              _getNotificationButtonLabel(_pendingResetCount),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            onPressed: () {
              setState(() => _selectedTabIndex = 4);
            },
          ),
          const SizedBox(width: 8),
          const ThemeToggleButton(),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              if (SupabaseConfig.isConfigured) {
                await _adminService.client?.auth.signOut();
              }
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: !isDesktop
          ? Drawer(
              child: Container(
                color: const Color(0xFF1E293B),
                child: _buildSidebarContent(),
              ),
            )
          : null,
      body: Row(
        children: [
          if (isDesktop)
            Container(
              width: 250,
              color: const Color(0xFF1E293B),
              child: _buildSidebarContent(),
            ),
          Expanded(
            child: _buildActiveTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarContent() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const AppLogoWidget(height: 28),
              ),
              const SizedBox(width: 12),
              const AppNameText(
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 16),
        _buildSidebarItem(0, Icons.dashboard, 'Overview'),
        _buildSidebarItem(1, Icons.people, 'User Management'),
        _buildSidebarItem(2, Icons.settings, 'System Settings'),
        _buildSidebarItem(3, Icons.health_and_safety, 'System Health'),
        _buildSidebarItem(4, Icons.notifications_active_rounded, 'Notifications', badgeCount: _pendingResetCount),
        const Spacer(),
        _buildSidebarItem(5, Icons.help_outline, 'Support'),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSidebarItem(int index, IconData icon, String label, {int badgeCount = 0}) {
    final isSelected = _selectedTabIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? Colors.white : Colors.white60, size: 20),
        title: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        onTap: () {
          setState(() => _selectedTabIndex = index);
          if (MediaQuery.of(context).size.width <= 900) {
            Navigator.of(context).maybePop();
          }
        },
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return AdminOverviewView(
          stats: _stats,
          chartPoints: _chartPoints,
          recentActivities: _recentActivities,
          chartPeriod: _chartPeriod,
          onChartPeriodChanged: _onChartPeriodChanged,
          onRefresh: () => _loadAllDashboardData(),
          isLoading: _isLoading,
          errorMessage: _errorMessage,
        );
      case 1:
        return AdminUserManagementView(
          adminService: _adminService,
          onAssignRoleRequested: () => _showAssignRoleDialog(context),
        );
      case 2:
        return AdminSettingsView(adminService: _adminService);
      case 3:
        return AdminSystemHealthView(adminService: _adminService, stats: _stats);
      case 4:
        return AdminNotificationsView(
          onRequestResolved: () => _loadAllDashboardData(silent: true),
        );
      case 5:
        return AdminSupportView(adminService: _adminService);
      default:
        return AdminOverviewView(
          stats: _stats,
          chartPoints: _chartPoints,
          recentActivities: _recentActivities,
          chartPeriod: _chartPeriod,
          onChartPeriodChanged: _onChartPeriodChanged,
          onRefresh: () => _loadAllDashboardData(),
          isLoading: _isLoading,
          errorMessage: _errorMessage,
        );
    }
  }
}
