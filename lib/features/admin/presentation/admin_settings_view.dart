import 'package:flutter/material.dart';

import '../../../core/theme/app_logo_controller.dart';
import '../../../core/theme/app_logo_widget.dart';
import '../../../core/theme/app_name_controller.dart';
import '../../../core/utils/image_picker_helper.dart';
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
  bool _isPickingImage = false;
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
      _controllers.putIfAbsent('app_logo_url', () => TextEditingController(text: AppLogoController.instance.value));
      _controllers.putIfAbsent('app_name', () => TextEditingController(text: AppNameController.instance.value));
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

  Future<void> _pickImageFromGallery() async {
    setState(() => _isPickingImage = true);

    try {
      final base64String = await ImagePickerHelper.pickImageAsBase64();

      if (base64String != null && base64String.isNotEmpty) {
        setState(() {
          _controllers['app_logo_url']?.text = base64String;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo loaded from gallery! Click "Save Settings" to apply globally across the app.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select photo: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final logoVal = _controllers['app_logo_url']?.text.trim() ?? '';
      await widget.adminService.updateSystemSetting('app_logo_url', logoVal);
      await AppLogoController.instance.updateLogo(logoVal);

      final rawAppName = _controllers['app_name']?.text.trim() ?? '';
      final appNameVal = rawAppName.isEmpty ? 'FlexPOS' : rawAppName;
      await widget.adminService.updateSystemSetting('app_name', appNameVal);
      await AppNameController.instance.updateName(appNameVal);

      await widget.adminService.updateSystemSetting('allow_cashier_discounts', _allowDiscounts ? 'true' : 'false');
      await widget.adminService.updateSystemSetting('min_stock_alert_threshold', _controllers['min_stock_alert_threshold']?.text ?? '5');
      await widget.adminService.updateSystemSetting('receipt_header_text', _controllers['receipt_header_text']?.text ?? '');
      await widget.adminService.updateSystemSetting('auto_lock_shift_hours', _controllers['auto_lock_shift_hours']?.text ?? '12');

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('System settings, store name, and logo successfully saved!'),
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
                  Text('System-wide operational parameters, store name, logo branding, and security policies', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
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
                            // Application Branding & Logo
                            const Text(
                              'Application Logo & Branding',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  // Clickable Logo Preview Box
                                  Tooltip(
                                    message: 'Click to select image from gallery',
                                    child: InkWell(
                                      onTap: _isPickingImage ? null : _pickImageFromGallery,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            width: 110,
                                            height: 110,
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                                            ),
                                            child: Center(
                                              child: _isPickingImage
                                                  ? const CircularProgressIndicator()
                                                  : AppLogoWidget(
                                                      key: ValueKey(_controllers['app_logo_url']?.text),
                                                      height: 85,
                                                    ),
                                            ),
                                          ),
                                          Positioned(
                                            right: 4,
                                            bottom: 4,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF003366),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.add_a_photo, size: 14, color: Colors.white),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        TextFormField(
                                          controller: _controllers['app_logo_url'],
                                          decoration: InputDecoration(
                                            labelText: 'Application Logo Source (URL / Asset Path / Base64)',
                                            hintText: 'e.g. assets/FlexPOS_logo_upscaled.png or https://example.com/logo.png',
                                            border: const OutlineInputBorder(),
                                            prefixIcon: const Icon(Icons.image_outlined),
                                            suffixIcon: IconButton(
                                              icon: const Icon(Icons.clear, size: 18),
                                              onPressed: () {
                                                setState(() {
                                                  _controllers['app_logo_url']?.clear();
                                                });
                                              },
                                            ),
                                          ),
                                          onChanged: (_) {
                                            setState(() {}); // refresh live preview
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            ElevatedButton.icon(
                                              icon: _isPickingImage
                                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                                  : const Icon(Icons.photo_library, size: 18),
                                              label: const Text('Choose Photo from Gallery'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF003366),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              onPressed: _isPickingImage ? null : _pickImageFromGallery,
                                            ),
                                            OutlinedButton.icon(
                                              icon: const Icon(Icons.restore, size: 16),
                                              label: const Text('Default Logo'),
                                              onPressed: () {
                                                setState(() {
                                                  _controllers['app_logo_url']?.text = 'assets/FlexPOS_logo_upscaled.png';
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Store Display Name Field (Under Logo Change Box)
                            TextFormField(
                              controller: _controllers['app_name'],
                              decoration: InputDecoration(
                                labelText: 'Application / Store Display Name',
                                hintText: 'FlexPOS',
                                helperText: 'Defaults to "FlexPOS" if left blank.',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.edit_note),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _controllers['app_name']?.clear();
                                    });
                                  },
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const Divider(height: 40),

                            const Text('Cashier & Checkout Permissions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              title: const Text('Allow Cashier Manual Discounts', style: TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text('Permits cashiers to enter manual custom discounts during checkout'),
                              value: _allowDiscounts,
                              activeThumbColor: const Color(0xFF003366),
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
