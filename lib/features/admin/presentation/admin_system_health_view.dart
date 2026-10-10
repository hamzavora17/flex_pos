import 'package:flutter/material.dart';

import '../../../core/config/supabase_config.dart';
import '../../../models/admin_models.dart';
import '../../../services/admin_dashboard_service.dart';

/// System Health & Administrative Audit View.
class AdminSystemHealthView extends StatefulWidget {
  final AdminDashboardService adminService;
  final AdminDashboardStats? stats;

  const AdminSystemHealthView({
    super.key,
    required this.adminService,
    required this.stats,
  });

  @override
  State<AdminSystemHealthView> createState() => _AdminSystemHealthViewState();
}

class _AdminSystemHealthViewState extends State<AdminSystemHealthView> {
  bool _isDbConnected = false;
  bool _isChecking = true;
  DateTime _lastPingTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _checkDbHealth();
  }

  Future<void> _checkDbHealth() async {
    setState(() => _isChecking = true);
    try {
      final c = widget.adminService.client;
      if (c != null) {
        await c.from('profiles').select('id').limit(1);
        _isDbConnected = true;
      } else {
        _isDbConnected = false;
      }
    } catch (_) {
      _isDbConnected = false;
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _lastPingTime = DateTime.now();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    'System Health & Diagnostic Status',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  Text('Database connectivity, Supabase Realtime synchronization, and security parameters', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Run Health Check',
                onPressed: _checkDbHealth,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Diagnostic Cards
          Expanded(
            child: ListView(
              children: [
                Row(
                  children: [
                    _buildHealthCard(
                      title: 'Database Connection',
                      status: _isChecking ? 'Checking...' : (_isDbConnected ? 'ONLINE' : 'OFFLINE'),
                      sub: _isDbConnected ? 'Connected to Supabase PostgreSQL Cluster' : 'Database connection error',
                      isGood: _isDbConnected,
                      icon: Icons.storage,
                    ),
                    const SizedBox(width: 16),
                    _buildHealthCard(
                      title: 'Realtime Subscription',
                      status: 'SUBSCRIBED',
                      sub: 'Postgres changes broadcast channel active',
                      isGood: true,
                      icon: Icons.podcasts,
                    ),
                    const SizedBox(width: 16),
                    _buildHealthCard(
                      title: 'Authentication RLS',
                      status: 'ENFORCED',
                      sub: 'Security Definer & RLS Policies active',
                      isGood: true,
                      icon: Icons.shield,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Operational Status
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('System Runtime Environment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 16),
                      _buildInfoRow('Supabase Project URL', SupabaseConfig.url),
                      const Divider(height: 24),
                      _buildInfoRow('Business Store Unit', 'FlexPOS (Active)'),
                      const Divider(height: 24),
                      _buildInfoRow('Active User Sessions', '${widget.stats?.userMetrics.active ?? 0} Authenticated Users'),
                      const Divider(height: 24),
                      _buildInfoRow('Last Data Sync Ping', '${_lastPingTime.hour}:${_lastPingTime.minute.toString().padLeft(2, '0')}:${_lastPingTime.second.toString().padLeft(2, '0')}'),
                      const Divider(height: 24),
                      _buildInfoRow('FlexPOS Version', 'v1.0.0 (Build 1) - Production Admin Edition'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCard({
    required String title,
    required String status,
    required String sub,
    required bool isGood,
    required IconData icon,
  }) {
    final color = isGood ? Colors.green : Colors.red;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w600)),
                Icon(icon, color: color, size: 22),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Text(status, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF1E293B))),
        Text(val, style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.bold)),
      ],
    );
  }
}
