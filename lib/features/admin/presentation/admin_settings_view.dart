import 'package:flutter/material.dart';

import '../../../models/admin_models.dart';
import '../../../services/admin_dashboard_service.dart';

/// Functional System Settings management view backed by `public.system_settings`.
class AdminSettingsView extends StatefulWidget {
  final AdminDashboardService adminService;

  const AdminSettingsView({
    super.key,
    required this.adminService,
  });

  @override
  State<AdminSettingsView> createState() => _AdminSettingsViewState();
}

class _AdminSettingsViewState extends State<AdminSettingsView> {
  final Map<String, TextEditingController> _controllers = {};
  bool _allowDiscounts = true;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await widget.adminService.getSystemSettings();
      for (var item in list) {
        if (item.key == 'allow_cashier_discounts') {
          _allowDiscounts = item.value.toLowerCase() == 'true';
        } else {
          _controllers[item.key] ??= TextEditingController();
          _controllers[item.key]!.text = item.value;
        }
      }

      // Ensure defaults if empty
      _controllers.putIfAbsent('currency_symbol', () => TextEditingController(text: '₹'));
      _controllers.putIfAbsent('default_tax_rate', () => TextEditingController(text: '0.00'));
      _controllers.putIfAbsent('min_stock_alert_threshold', () => TextEditingController(text: '5'));
      _controllers.putIfAbsent('receipt_header_text', () => TextEditingController(text: 'Thank you for shopping with FlexPOS!'));
      _controllers.putIfAbsent('auto_lock_shift_hours', () => TextEditingController(text: '12'));

      if (mounted) {
        setState(() => _isLoading = false);
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

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      await widget.adminService.updateSystemSetting('currency_symbol', _controllers['currency_symbol']?.text ?? '₹');
      await widget.adminService.updateSystemSetting('default_tax_rate', _controllers['default_tax_rate']?.text ?? '0.00');
      await widget.adminService.updateSystemSetting('allow_cashier_discounts', _allowDiscounts ? 'true' : 'false');
      await widget.adminService.updateSystemSetting('min_stock_alert_threshold', _controllers['min_stock_alert_threshold']?.text ?? '5');
      await widget.adminService.updateSystemSetting('receipt_header_text', _controllers['receipt_header_text']?.text ?? '');
      await widget.adminService.updateSystemSetting('auto_lock_shift_hours', _controllers['auto_lock_shift_hours']?.text ?? '12');

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('System settings successfully saved and updated in database!'),
            backgroundColor: Colors.green[800],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save system settings: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
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
                    'Global System Settings',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  Text('System-wide operational parameters, currency defaults, and security policies', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
              ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save, size: 18),
                label: const Text('Save Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isSaving ? null : _saveSettings,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Content Box
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
                    : Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: ListView(
                          children: [
                            const Text('Currency & Financial Defaults', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _controllers['currency_symbol'],
                                    decoration: const InputDecoration(
                                      labelText: 'Default Currency Symbol',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.currency_exchange),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _controllers['default_tax_rate'],
                                    decoration: const InputDecoration(
                                      labelText: 'Default Tax Rate (%)',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.percent),
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 40),

                            const Text('Cashier & Checkout Permissions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              title: const Text('Allow Cashier Manual Discounts', style: TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text('Permits cashiers to enter manual custom discounts during checkout'),
                              value: _allowDiscounts,
                              activeColor: const Color(0xFF003366),
                              onChanged: (val) => setState(() => _allowDiscounts = val),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _controllers['receipt_header_text'],
                              decoration: const InputDecoration(
                                labelText: 'Receipt Printed Header Message',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.receipt_long),
                              ),
                            ),
                            const Divider(height: 40),

                            const Text('Inventory & Shift Security', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _controllers['min_stock_alert_threshold'],
                                    decoration: const InputDecoration(
                                      labelText: 'Global Low Stock Alert Threshold',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.inventory_2),
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _controllers['auto_lock_shift_hours'],
                                    decoration: const InputDecoration(
                                      labelText: 'Auto-Lock Shift Timeout (Hours)',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.timer),
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
