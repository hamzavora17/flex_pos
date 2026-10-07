import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../main.dart';
import '../../../models/completed_sale_model.dart';
import '../../../models/product_model.dart';
import '../../../services/cashier_dashboard_service.dart';
import '../../../services/product_service.dart';
import '../../../services/sale_service.dart';
import 'manager_products_screen.dart';
import 'manager_profile_screen.dart';
import 'manager_sales_screen.dart';

/// Dashboard screen for authenticated Manager users featuring a modern POS admin layout,
/// dark navy sidebar navigation, live KPI metrics, quick action shortcuts, and real store analytics.
class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({super.key});

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> with WidgetsBindingObserver {
  final ProductService _productService = ProductService();
  final SaleService _saleService = SaleService();
  final CashierDashboardService _dashboardService = CashierDashboardService();

  RealtimeChannel? _realtimeChannel;

  int _selectedIndex = 0;
  String _displayName = 'Manager';
  String _userEmail = '';
  bool _isProfileLoading = true;

  // Overview Real Data State
  bool _isOverviewLoading = true;
  String? _overviewError;
  double _todaySales = 0.0;
  int _todayBills = 0;
  int _totalProductsCount = 0;
  int _lowStockCount = 0;
  List<CompletedSaleModel> _recentSales = [];
  List<Product> _lowStockProducts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadManagerProfile();
    _loadOverviewData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadOverviewData(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
      } catch (_) {}
    }
    super.dispose();
  }

  static String _formatWorkDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  void _setupRealtimeSubscription(String userId) {
    if (_realtimeChannel != null || userId.isEmpty) return;
    _realtimeChannel = _dashboardService.subscribeToDashboardChanges(
      userId: userId,
      onDataChanged: () {
        if (mounted) {
          _loadOverviewData(silent: true);
        }
      },
    );
  }

  Future<void> _loadManagerProfile() async {
    if (!SupabaseConfig.isConfigured) {
      if (mounted) {
        setState(() {
          _displayName = 'Manager';
          _userEmail = '';
          _isProfileLoading = false;
        });
      }
      return;
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        _userEmail = user.email ?? '';
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('full_name, email')
            .eq('id', user.id)
            .maybeSingle();

        if (profile != null) {
          final fullName = profile['full_name']?.toString() ?? '';
          if (fullName.isNotEmpty) {
            _displayName = fullName;
          } else if (_userEmail.isNotEmpty) {
            _displayName = _userEmail.split('@').first;
          }
        } else if (_userEmail.isNotEmpty) {
          _displayName = _userEmail.split('@').first;
        }
      }
    } catch (_) {
      // Retain fallback defaults
    } finally {
      if (mounted) {
        setState(() => _isProfileLoading = false);
      }
    }
  }

  Future<void> _loadOverviewData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _isOverviewLoading = true;
        _overviewError = null;
      });
    }

    try {
      final products = await _productService.getManagerProducts();
      final sales = await _saleService.getStoreSales();

      final todayStr = _formatWorkDate(DateTime.now());
      final todaySalesList = sales.where((s) {
        final isCompleted = s.status.toLowerCase() == 'completed';
        final isToday = _formatWorkDate(s.createdAt) == todayStr;
        return isCompleted && isToday;
      }).toList();

      final todaySalesSum = todaySalesList.fold(0.0, (sum, s) => sum + s.total);
      final lowStock = products.where((p) => p.stockQuantity <= p.minStockAlert).toList();
      final completedSalesList = sales.where((s) => s.status.toLowerCase() == 'completed').toList();

      if (mounted) {
        setState(() {
          _todaySales = todaySalesSum;
          _todayBills = todaySalesList.length;
          _totalProductsCount = products.length;
          _lowStockCount = lowStock.length;
          _recentSales = completedSalesList.take(5).toList();
          _lowStockProducts = lowStock.take(5).toList();
          _isOverviewLoading = false;
          _overviewError = null;
        });

        // Set up Realtime listener for live store updates
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          _setupRealtimeSubscription(user.id);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!silent) {
            _overviewError = e.toString();
          }
          _isOverviewLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
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

  Widget _buildOverviewTab() {
    if (_isOverviewLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF003366)),
      );
    }

    if (_overviewError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_overviewError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003366),
                foregroundColor: Colors.white,
              ),
              onPressed: _loadOverviewData,
              child: const Text('Retry Loading Data'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. KPI Summary Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final crossAxisCount = w > 1100 ? 4 : (w > 650 ? 2 : 1);

              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: w > 1100 ? 2.1 : (w > 650 ? 2.3 : 2.6),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildKpiCard(
                    title: "TODAY'S SALES",
                    value: CurrencyFormatter.format(_todaySales),
                    subtitle: "Today's store turnover",
                    icon: Icons.trending_up_rounded,
                    color: const Color(0xFF8DB600),
                    bgColor: const Color(0xFF8DB600).withValues(alpha: 0.12),
                  ),
                  _buildKpiCard(
                    title: "TODAY'S TRANSACTIONS",
                    value: '$_todayBills ${_todayBills == 1 ? 'Bill' : 'Bills'}',
                    subtitle: 'Completed cashier checkout bills',
                    icon: Icons.receipt_long_rounded,
                    color: const Color(0xFF0284C7),
                    bgColor: const Color(0xFF0284C7).withValues(alpha: 0.12),
                  ),
                  _buildKpiCard(
                    title: 'TOTAL PRODUCTS',
                    value: '$_totalProductsCount Items',
                    subtitle: 'Store product catalog items',
                    icon: Icons.inventory_2_rounded,
                    color: const Color(0xFF7C3AED),
                    bgColor: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                  ),
                  _buildKpiCard(
                    title: 'LOW STOCK ALERTS',
                    value: '$_lowStockCount ${_lowStockCount == 1 ? 'Alert' : 'Alerts'}',
                    subtitle: 'Items at or below min threshold',
                    icon: Icons.warning_amber_rounded,
                    color: _lowStockCount > 0 ? Colors.amber.shade900 : const Color(0xFF059669),
                    bgColor: _lowStockCount > 0
                        ? Colors.amber.shade100.withValues(alpha: 0.5)
                        : const Color(0xFF059669).withValues(alpha: 0.12),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),

          // 2. Quick Action Shortcuts Section
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF003366),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  title: 'Inspect Store Sales',
                  subtitle: 'View all cashier sales, items & receipts',
                  icon: Icons.receipt_long_rounded,
                  color: const Color(0xFF0284C7),
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildQuickActionCard(
                  title: 'Manage Products & Stock',
                  subtitle: 'Add products, update prices & adjust stock',
                  icon: Icons.inventory_2_rounded,
                  color: const Color(0xFF059669),
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildQuickActionCard(
                  title: 'My Profile & Credentials',
                  subtitle: 'View manager account details & settings',
                  icon: Icons.person_outline_rounded,
                  color: const Color(0xFF7C3AED),
                  onTap: () => setState(() => _selectedIndex = 3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // 3. Store Real Activity Tables (Recent Sales & Low Stock Alerts)
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              if (w > 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildRecentSalesPanel()),
                    const SizedBox(width: 20),
                    Expanded(child: _buildLowStockAlertsPanel()),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildRecentSalesPanel(),
                    const SizedBox(height: 20),
                    _buildLowStockAlertsPanel(),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSalesPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: Color(0xFF003366), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Recent Store Transactions',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => setState(() => _selectedIndex = 1),
                child: const Text('View All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
              ),
            ],
          ),
          const Divider(height: 20),
          if (_recentSales.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text('No completed store sales found.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
              ),
            )
          else
            Column(
              children: _recentSales.map((sale) {
                final formattedDate =
                    '${sale.createdAt.day.toString().padLeft(2, '0')}/${sale.createdAt.month.toString().padLeft(2, '0')} ${sale.createdAt.hour.toString().padLeft(2, '0')}:${sale.createdAt.minute.toString().padLeft(2, '0')}';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8DB600).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF003366), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('#${sale.invoiceNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                            Text('$formattedDate • ${sale.paymentMethod.toUpperCase()}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(sale.total),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF003366)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildLowStockAlertsPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Low Stock Inventory Alerts',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => setState(() => _selectedIndex = 2),
                child: const Text('Manage Stock', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
              ),
            ],
          ),
          const Divider(height: 20),
          if (_lowStockProducts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text('✅ All product inventory levels are healthy.', style: TextStyle(color: Color(0xFF059669), fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            )
          else
            Column(
              children: _lowStockProducts.map((p) {
                final isOut = p.stockQuantity <= 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isOut ? Colors.red.shade50 : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isOut ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                          color: isOut ? Colors.red.shade800 : Colors.amber.shade900,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                            Text('Threshold: ${p.minStockAlert} ${p.unit}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isOut ? Colors.red.shade50 : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isOut ? Colors.red.shade300 : Colors.amber.shade300),
                        ),
                        child: Text(
                          isOut ? '0 ${p.unit} (Out)' : '${p.stockQuantity} ${p.unit} (Low)',
                          style: TextStyle(
                            color: isOut ? Colors.red.shade800 : Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar(bool isDesktop) {
    return Container(
      width: 250,
      color: const Color(0xFF001F3F), // Dark Navy Sidebar
      child: Column(
        children: [
          // Branding Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            color: const Color(0xFF001833),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Image.asset(
                    'assets/FlexPOS_logo_upscaled.png',
                    height: 22,
                    errorBuilder: (_, _, _) => const Icon(Icons.store_rounded, size: 20, color: Color(0xFF003366)),
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FlexPOS',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5),
                    ),
                    Text(
                      'Manager Admin',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Navigation Destination Items
          _buildSidebarNavItem(index: 0, label: 'Dashboard', icon: Icons.dashboard_rounded),
          _buildSidebarNavItem(index: 1, label: 'Store Sales', icon: Icons.receipt_long_rounded),
          _buildSidebarNavItem(index: 2, label: 'Products & Stock', icon: Icons.inventory_2_rounded),
          _buildSidebarNavItem(index: 3, label: 'My Profile', icon: Icons.person_rounded),

          const Spacer(),
          const Divider(color: Color(0xFF1E293B), height: 1),

          // Logout Item at bottom
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: InkWell(
              onTap: _logout,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade800.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text(
                      'Log Out',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = index;
            if (_selectedIndex == 0) {
              _loadOverviewData();
            }
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF8DB600) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                size: 20,
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBar(bool isDesktop) {
    String pageTitle = 'Manager Dashboard';
    String pageSubtitle = 'Overview of your store performance & inventory';

    if (_selectedIndex == 1) {
      pageTitle = 'Store Sales';
      pageSubtitle = 'Inspect all completed cashier sales & receipts';
    } else if (_selectedIndex == 2) {
      pageTitle = 'Products & Stock';
      pageSubtitle = 'Manage catalog items, prices & stock levels';
    } else if (_selectedIndex == 3) {
      pageTitle = 'My Profile';
      pageSubtitle = 'View and update your manager account credentials';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: Color(0xFF003366)),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pageTitle,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                pageSubtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const Spacer(),

          // Manager Profile Badge on Top-Right
          if (!_isProfileLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF003366),
                    child: Text(
                      _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'M',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8DB600).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'MANAGER ROLE',
                          style: TextStyle(
                            color: Color(0xFF003366),
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildOverviewTab(),
      const ManagerSalesScreen(),
      const ManagerProductsScreen(),
      const ManagerProfileScreen(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          drawer: !isDesktop ? Drawer(child: _buildSidebar(false)) : null,
          body: Row(
            children: [
              // Desktop Persistent Dark Navy Sidebar
              if (isDesktop) _buildSidebar(true),

              // Main Content Area
              Expanded(
                child: Column(
                  children: [
                    // Top Header Bar
                    _buildHeaderBar(isDesktop),

                    // Main Content Body
                    Expanded(
                      child: screens[_selectedIndex],
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: !isDesktop
              ? BottomNavigationBar(
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    setState(() {
                      _selectedIndex = index;
                      if (_selectedIndex == 0) {
                        _loadOverviewData();
                      }
                    });
                  },
                  selectedItemColor: const Color(0xFF003366),
                  unselectedItemColor: Colors.grey[600],
                  type: BottomNavigationBarType.fixed,
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Overview'),
                    BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Store Sales'),
                    BottomNavigationBarItem(icon: Icon(Icons.inventory_2_rounded), label: 'Products & Stock'),
                    BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
                  ],
                )
              : null,
        );
      },
    );
  }
}
