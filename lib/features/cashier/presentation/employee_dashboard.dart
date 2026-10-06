import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../main.dart';
import '../../../services/cashier_dashboard_service.dart';
import '../../../services/held_sale_service.dart';
import 'held_sales_screen.dart';
import 'new_sale_screen.dart';
import 'previous_sales_screen.dart';
import 'returns_refunds_screen.dart';
import 'search_products_screen.dart';

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  final CashierDashboardService _dashboardService = CashierDashboardService();
  final HeldSaleService _heldSaleService = HeldSaleService();

  RealtimeChannel? _realtimeChannel;

  CashierDashboardData? _dashboardData;
  bool _isLoadingData = true;
  String? _errorMessage;
  bool _isEndingShift = false;
  int _heldSaleCount = 0;

  @override
  void initState() {
    super.initState();
    _startClock();
    _loadDashboardData();
  }

  void _startClock() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  Future<void> _loadDashboardData() async {
    try {
      final data = await _dashboardService.getDashboardData();
      int count = 0;
      try {
        count = await _heldSaleService.getHeldSaleCount();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _dashboardData = data;
          _heldSaleCount = count;
          _isLoadingData = false;
          _errorMessage = null;
        });

        _setupRealtimeSubscription(data.userId);
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        final detailMsg = e is DashboardException
            ? e.message
            : e.toString().replaceFirst('Exception: ', '').replaceFirst('DashboardException: ', '');
        setState(() {
          _isLoadingData = false;
          _errorMessage = detailMsg;
        });
      }
    }
  }

  void _setupRealtimeSubscription(String userId) {
    if (_realtimeChannel != null) return;
    _realtimeChannel = _dashboardService.subscribeToDashboardChanges(
      userId: userId,
      onDataChanged: () {
        if (mounted) {
          _loadDashboardData();
        }
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
      } catch (_) {}
    }
    super.dispose();
  }

  String _getGreeting() {
    final hour = _now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];
    return '$weekday, $month ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt, {bool includeSeconds = true}) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final periodStr = dt.hour >= 12 ? 'PM' : 'AM';
    if (includeSeconds) {
      final second = dt.second.toString().padLeft(2, '0');
      return '$hour:$minute:$second $periodStr';
    }
    return '$hour:$minute $periodStr';
  }

  String _formatShiftDuration() {
    final activeShift = _dashboardData?.activeShift;
    if (activeShift == null || !activeShift.isActive) return '00h 00m';

    final diff = _now.difference(activeShift.startTime);
    if (diff.isNegative) return '00h 00m';

    final hours = diff.inHours.toString().padLeft(2, '0');
    final minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${hours}h ${minutes}m';
  }

  String _getRelativeTime(DateTime timestamp) {
    final diff = _now.difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours} ${diff.inHours == 1 ? "hour" : "hours"} ago';
    return '${diff.inDays} ${diff.inDays == 1 ? "day" : "days"} ago';
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to end your current cashier session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003366),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (SupabaseConfig.isConfigured) {
        await Supabase.instance.client.auth.signOut();
      }
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }

  void _showProfileDialog() {
    final name = _dashboardData?.fullName ?? 'Cashier';
    final email = _dashboardData?.email ?? 'cashier@flexpos.com';
    final role = _dashboardData?.position ?? 'CASHIER';
    final terminal = _dashboardData?.terminalId ?? 'POS-TERM-01';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.person_pin, color: Color(0xFF003366), size: 26),
            SizedBox(width: 10),
            Text('Cashier Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF003366),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'C',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$role • $terminal',
                            style: const TextStyle(
                              color: Color(0xFF8DB600),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildProfileDetailRow(Icons.email_outlined, 'Email Address', email, isProtected: true),
              const SizedBox(height: 8),
              _buildProfileDetailRow(
                Icons.access_time_outlined,
                'Shift Status',
                _dashboardData?.activeShift != null
                    ? 'Shift active since ${_formatTime(_dashboardData!.activeShift!.startTime)}'
                    : 'No Active Shift',
              ),
              const SizedBox(height: 8),
              _buildProfileDetailRow(Icons.store_outlined, 'Assigned Terminal', '$terminal (Main Store)'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade800, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Email and session parameters are managed by System Administrator.',
                        style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetailRow(IconData icon, String label, String value, {bool isProtected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF003366)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (isProtected) ...[
            Tooltip(
              message: 'Admin Managed',
              child: Icon(Icons.lock_outline, size: 15, color: Colors.grey[400]),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleShiftToggle() async {
    final activeShift = _dashboardData?.activeShift;
    final isShiftActive = activeShift != null && activeShift.isActive;

    if (!isShiftActive) {
      // Start Shift
      setState(() => _isLoadingData = true);
      try {
        await _dashboardService.startShift(openingFloat: 150.0);
        await _loadDashboardData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Shift Started & Attendance Recorded'),
              backgroundColor: Color(0xFF003366),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoadingData = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error starting shift: ${e.toString()}'),
              backgroundColor: Colors.red[800],
            ),
          );
        }
      }
      return;
    }

    // Confirmation dialog before ending shift
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('End Current Shift?'),
        content: const Text('Are you sure you want to end your current shift and log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[800],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End Shift'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isEndingShift = true;
    });

    try {
      await _dashboardService.endShift(activeShift.id);

      if (SupabaseConfig.isConfigured) {
        await Supabase.instance.client.auth.signOut();
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEndingShift = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to end the shift. Please try again.'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // 1. NAVBAR / HEADER
            _buildNavbarHeader(),

            // MAIN DASHBOARD BODY
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadDashboardData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                  child: _isLoadingData
                      ? const SizedBox(
                          height: 300,
                          child: Center(
                            child: CircularProgressIndicator(color: Color(0xFF003366)),
                          ),
                        )
                      : (_errorMessage != null && _dashboardData == null
                          ? _buildErrorView()
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;
                                if (width > 950) {
                                  return _buildTwoColumnLayout();
                                } else {
                                  return _buildSingleColumnLayout();
                                }
                              },
                            )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 40),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: Colors.red[700]),
            const SizedBox(height: 16),
            const Text(
              'Database Connection Error',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unable to connect to Supabase. Please retry.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry Connection'),
              onPressed: () {
                setState(() => _isLoadingData = true);
                _loadDashboardData();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. NAVIGATION / HEADER
  // ===========================================================================
  Widget _buildNavbarHeader() {
    final cashierName = _dashboardData?.fullName ?? 'Cashier';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF003366),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.asset(
                  'assets/FlexPOS_logo_upscaled.png',
                  height: 28,
                  errorBuilder: (_, _, _) => const Icon(Icons.storefront, color: Color(0xFF003366), size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'FlexPOS Terminal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    '${_getGreeting()}, $cashierName',
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const Spacer(),

          Row(
            children: [
              // Current Time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(_now),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    _formatDate(_now),
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // Online Status Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8DB600).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF8DB600)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi, color: Color(0xFF8DB600), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'ONLINE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Profile Avatar
              Tooltip(
                message: 'My Profile',
                child: InkWell(
                  onTap: _showProfileDialog,
                  borderRadius: BorderRadius.circular(20),
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: const Color(0xFF8DB600),
                    child: Text(
                      cashierName.isNotEmpty ? cashierName[0].toUpperCase() : 'C',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Logout Button
              Tooltip(
                message: 'Logout',
                child: IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                  onPressed: _logout,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LAYOUT STRUCTURING
  // ===========================================================================
  Widget _buildTwoColumnLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPosOperationsSection(),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEFT COLUMN: Today's Overview + Current Shift & Attendance
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTodaysOverviewSection(),
                  const SizedBox(height: 20),
                  _buildCurrentShiftAndAttendanceSection(),
                ],
              ),
            ),
            const SizedBox(width: 20),
            // RIGHT COLUMN: Recent Activity + Logged-in User
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRecentActivitySection(),
                  const SizedBox(height: 20),
                  _buildLoggedInUserSection(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSingleColumnLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPosOperationsSection(),
        const SizedBox(height: 20),
        _buildTodaysOverviewSection(),
        const SizedBox(height: 20),
        _buildCurrentShiftAndAttendanceSection(),
        const SizedBox(height: 20),
        _buildRecentActivitySection(),
        const SizedBox(height: 20),
        _buildLoggedInUserSection(),
      ],
    );
  }

  // ===========================================================================
  // 2. MAIN POS OPERATIONS (5 Action Cards)
  // ===========================================================================
  Widget _buildPosOperationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'POS OPERATIONS',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Color(0xFF003366),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final count = w > 1050 ? 5 : (w > 650 ? 3 : 2);

            return GridView.count(
              crossAxisCount: count,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildPosOperationCard(
                  title: 'New Sale',
                  subtitle: 'Start checkout & billing',
                  icon: Icons.add_shopping_cart_rounded,
                  isPrimary: true,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NewSaleScreen()),
                    );
                    _loadDashboardData();
                  },
                ),
                _buildPosOperationCard(
                  title: 'Search Products',
                  subtitle: 'Find products by name, SKU or barcode',
                  icon: Icons.search_rounded,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SearchProductsScreen()),
                    );
                  },
                ),
                _buildPosOperationCard(
                  title: 'Held Sales',
                  subtitle: 'Resume paused transactions',
                  icon: Icons.pause_circle_outline_rounded,
                  badgeText: _heldSaleCount > 0 ? _heldSaleCount.toString() : null,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HeldSalesScreen()),
                    );
                    _loadDashboardData();
                  },
                ),
                _buildPosOperationCard(
                  title: 'Previous Sales',
                  subtitle: 'View completed sales',
                  icon: Icons.history_rounded,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PreviousSalesScreen()),
                    );
                    _loadDashboardData();
                  },
                ),
                _buildPosOperationCard(
                  title: 'Returns & Refunds',
                  subtitle: 'Manage eligible returns and refunds',
                  icon: Icons.assignment_return_outlined,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReturnsRefundsScreen()),
                    );
                    _loadDashboardData();
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPosOperationCard({
    required String title,
    required String subtitle,
    required IconData icon,
    bool isPrimary = false,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: isPrimary ? const Color(0xFF003366) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPrimary ? const Color(0xFF003366) : const Color(0xFFE2E8F0),
              width: isPrimary ? 1.5 : 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isPrimary
                            ? const Color(0xFF8DB600)
                            : const Color(0xFF003366).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        color: isPrimary ? Colors.white : const Color(0xFF003366),
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isPrimary ? Colors.white : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isPrimary ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (badgeText != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade800,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. TODAY'S OVERVIEW
  // ===========================================================================
  Widget _buildTodaysOverviewSection() {
    final salesStr = CurrencyFormatter.format(_dashboardData?.todaySales ?? 0.0);
    final earningsStr = CurrencyFormatter.format(_dashboardData?.todayEarnings ?? 0.0);
    final billsStr = '${_dashboardData?.todayBills ?? 0}';
    final isShiftActive = _dashboardData?.activeShift?.isActive ?? false;
    final shiftStr = isShiftActive ? 'Active' : 'No Active Shift';
    final workingTimeStr = _formatShiftDuration();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "TODAY'S OVERVIEW",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: Color(0xFF003366),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              if (w > 480) {
                return Row(
                  children: [
                    Expanded(child: _buildHorizontalStatTile("Sales", salesStr, Icons.payments_outlined)),
                    Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                    Expanded(child: _buildHorizontalStatTile("Earnings", earningsStr, Icons.account_balance_wallet_outlined)),
                    Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                    Expanded(child: _buildHorizontalStatTile("Bills", billsStr, Icons.receipt_long_outlined)),
                    Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                    Expanded(child: _buildHorizontalStatTile("Shift", shiftStr, Icons.access_time)),
                    Container(height: 36, width: 1, color: const Color(0xFFE2E8F0)),
                    Expanded(child: _buildHorizontalStatTile("Working Time", workingTimeStr, Icons.timer_outlined)),
                  ],
                );
              } else {
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildCompactGridStatTile("Sales", salesStr, Icons.payments_outlined),
                    _buildCompactGridStatTile("Earnings", earningsStr, Icons.account_balance_wallet_outlined),
                    _buildCompactGridStatTile("Bills", billsStr, Icons.receipt_long_outlined),
                    _buildCompactGridStatTile("Shift", shiftStr, Icons.access_time),
                    _buildCompactGridStatTile("Working Time", workingTimeStr, Icons.timer_outlined),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalStatTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: const Color(0xFF003366)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactGridStatTile(String label, String value, IconData icon) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: const Color(0xFF003366)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 4. RECENT ACTIVITY
  // ===========================================================================
  Widget _buildRecentActivitySection() {
    final activities = _dashboardData?.recentActivities ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'RECENT ACTIVITY',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Color(0xFF003366),
                ),
              ),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PreviousSalesScreen()),
                  );
                },
                child: const Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF003366),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (activities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No recent activity recorded today.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activities.length,
              separatorBuilder: (_, _) => const Divider(height: 10, color: Color(0xFFF1F5F9)),
              itemBuilder: (ctx, idx) {
                final item = activities[idx];
                return _buildActivityRow(
                  item.title,
                  item.details,
                  _getRelativeTime(item.timestamp),
                  item.icon,
                  item.iconColor,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildActivityRow(String title, String details, String time, IconData icon, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                ),
                Text(
                  details,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 5. CURRENT SHIFT & ATTENDANCE
  // ===========================================================================
  Widget _buildCurrentShiftAndAttendanceSection() {
    final activeShift = _dashboardData?.activeShift;
    final isShiftActive = activeShift != null && activeShift.isActive;
    final attendance = _dashboardData?.todayAttendance;
    final attStatus = attendance?.status.toUpperCase() ?? (isShiftActive ? 'PRESENT' : 'NOT RECORDED');

    final reportingTimeStr = attendance != null
        ? _formatTime(attendance.reportingTime, includeSeconds: false)
        : (activeShift != null
            ? _formatTime(activeShift.startTime.subtract(const Duration(minutes: 15)), includeSeconds: false)
            : 'Not recorded');

    final shiftStartedStr = activeShift != null
        ? _formatTime(activeShift.startTime, includeSeconds: false)
        : 'Not started';

    final openingFloatStr = activeShift != null
        ? CurrencyFormatter.format(activeShift.openingFloat)
        : 'Not recorded';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CURRENT SHIFT & ATTENDANCE',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Color(0xFF003366),
                ),
              ),

              // Attendance Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF8DB600).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF8DB600)),
                ),
                child: Row(
                  children: [
                    const Text('● ', style: TextStyle(color: Color(0xFF8DB600), fontSize: 10)),
                    Text(
                      attStatus,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF003366),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 20,
                  runSpacing: 10,
                  children: [
                    _buildShiftAttendanceDetailItem('Reporting Time', reportingTimeStr),
                    _buildShiftAttendanceDetailItem('Shift Started', shiftStartedStr),
                    _buildShiftAttendanceDetailItem('Working Time', _formatShiftDuration()),
                    _buildShiftAttendanceDetailItem('Opening Float', openingFloatStr),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                height: 38,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isShiftActive ? Colors.red[800] : const Color(0xFF8DB600),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.red[300],
                    disabledForegroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: _isEndingShift
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Icon(isShiftActive ? Icons.stop_circle_outlined : Icons.play_circle_fill, size: 16),
                  label: Text(
                    _isEndingShift
                        ? 'Ending Shift...'
                        : (isShiftActive ? 'End Current Shift' : 'Start Shift'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  onPressed: _isEndingShift ? null : _handleShiftToggle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShiftAttendanceDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ],
    );
  }

  // ===========================================================================
  // 6. LOGGED-IN USER INFORMATION
  // ===========================================================================
  Widget _buildLoggedInUserSection() {
    final cashierName = _dashboardData?.fullName ?? 'Cashier';
    final cashierRole = _dashboardData?.position ?? 'CASHIER';
    final terminalId = _dashboardData?.terminalId ?? 'POS-TERM-01';
    final cashierEmail = _dashboardData?.email ?? 'cashier@flexpos.com';
    final activeShift = _dashboardData?.activeShift;

    final sessionLoginStr = activeShift != null
        ? 'Shift active since ${_formatTime(activeShift.startTime)}'
        : 'Logged in today';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LOGGED-IN USER',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: Color(0xFF003366),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF003366),
                child: Text(
                  cashierName.isNotEmpty ? cashierName[0].toUpperCase() : 'C',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cashierName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '$cashierRole • $terminalId',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    Text(
                      cashierEmail,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      sessionLoginStr,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF003366), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF003366),
                    side: const BorderSide(color: Color(0xFF003366)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: _showProfileDialog,
                  child: const Text('My Profile', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
