import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

import '../../../models/admin_models.dart';
import '../../../services/password_reset_service.dart';

/// Admin Notifications & Password Reset Requests View.
class AdminNotificationsView extends StatefulWidget {
  final VoidCallback onRequestResolved;

  const AdminNotificationsView({
    super.key,
    required this.onRequestResolved,
  });

  @override
  State<AdminNotificationsView> createState() => _AdminNotificationsViewState();
}

class _AdminNotificationsViewState extends State<AdminNotificationsView> {
  final PasswordResetService _resetService = PasswordResetService();

  List<PasswordResetRequestModel> _allRequests = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = 'all'; // 'all', 'pending', 'resolved'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final requests = await _resetService.getAllRequests();
      if (mounted) {
        setState(() {
          _allRequests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('FlexPOSException: ', '');
          _isLoading = false;
        });
      }
    }
  }

  List<PasswordResetRequestModel> get _filteredRequests {
    return _allRequests.where((req) {
      if (_statusFilter == 'pending' && req.status != 'pending') return false;
      if (_statusFilter == 'resolved' && req.status != 'resolved') return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return req.email.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  int get _pendingCount => _allRequests.where((r) => r.isPending).length;

  void _showResetPasswordModal(PasswordResetRequestModel req) {
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isSubmitting = false;
    String? modalError;

    // Default auto-generated password suggestion
    String generatePassword() {
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
      final rnd = Random();
      return String.fromCharCodes(Iterable.generate(10, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    }

    passwordController.text = generatePassword();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF003366).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF003366), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Reset User Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set a new password for user account: ${req.email}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13.5),
                ),
                const SizedBox(height: 16),
                if (modalError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(modalError!, style: TextStyle(color: Colors.red.shade800, fontSize: 12.5))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text('New Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Enter new password',
                    isDense: true,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                          onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20, color: Color(0xFF003366)),
                          tooltip: 'Generate New Password',
                          onPressed: () {
                            setModalState(() {
                              passwordController.text = generatePassword();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Password must be at least 6 characters.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text('Copy', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: passwordController.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password copied to clipboard!'), duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.of(dialogCtx).pop(),
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
                      final newPass = passwordController.text.trim();
                      if (newPass.length < 6) {
                        setModalState(() => modalError = 'Password must be at least 6 characters.');
                        return;
                      }

                      setModalState(() {
                        isSubmitting = true;
                        modalError = null;
                      });

                      try {
                        await _resetService.adminResetUserPassword(
                          requestId: req.id,
                          email: req.email,
                          newPassword: newPass,
                        );

                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF003366),
                              duration: const Duration(seconds: 3),
                              content: Row(
                                children: [
                                  Expanded(
                                    child: Text('Password updated successfully for ${req.email}! Password: $newPass'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: newPass));
                                    },
                                    child: const Text(
                                      'COPY',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                    },
                                    child: const Text(
                                      'DISMISS',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                          _loadRequests();
                          widget.onRequestResolved();
                        }
                      } catch (e) {
                        setModalState(() {
                          isSubmitting = false;
                          modalError = e.toString().replaceAll('FlexPOSException: ', '');
                        });
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Confirm & Reset Password'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRequests;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF003366).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF003366), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Notifications & Password Reset Requests',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                            if (_pendingCount > 0) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$_pendingCount Pending',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage user password reset requests submitted from the login terminal in real time.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF003366)),
                    tooltip: 'Refresh Notifications',
                    onPressed: _loadRequests,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Search & Filter Toolbar
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by user email or username...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'all', label: Text('All')),
                  ButtonSegment(
                    value: 'pending',
                    label: Text(_pendingCount > 0 ? 'Pending ($_pendingCount)' : 'Pending'),
                  ),
                  const ButtonSegment(value: 'resolved', label: Text('Resolved')),
                ],
                selected: {_statusFilter},
                onSelectionChanged: (set) {
                  setState(() => _statusFilter = set.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Content List
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Error loading requests: $_errorMessage', style: TextStyle(color: Colors.red.shade900))),
                  ],
                ),
              ),
            )
          else if (filtered.isEmpty)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.mark_email_read_rounded, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        _statusFilter == 'pending'
                            ? 'No pending password reset requests!'
                            : 'No notification records found.',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Password reset requests submitted by cashiers or managers will appear here live.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final req = filtered[index];
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: req.isPending ? Colors.amber.shade300 : Colors.grey.shade200,
                      width: req.isPending ? 1.5 : 1,
                    ),
                  ),
                  elevation: req.isPending ? 2 : 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: req.isPending ? Colors.amber.shade100 : Colors.green.shade100,
                          child: Icon(
                            req.isPending ? Icons.mark_email_unread_rounded : Icons.check_circle_rounded,
                            color: req.isPending ? Colors.amber.shade900 : Colors.green.shade800,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    req.email,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: req.isPending
                                          ? Colors.amber.shade100
                                          : req.isResolved
                                              ? Colors.green.shade100
                                              : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      req.status.toUpperCase(),
                                      style: TextStyle(
                                        color: req.isPending
                                            ? Colors.amber.shade900
                                            : req.isResolved
                                                ? Colors.green.shade800
                                                : Colors.grey.shade700,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Requested ${_formatDateTime(req.createdAt)}',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              ),
                              if (req.adminNotes != null && req.adminNotes!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  req.adminNotes!,
                                  style: TextStyle(color: Colors.grey[500], fontSize: 11.5, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (req.isPending) ...[
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF003366),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.key_rounded, size: 16),
                            label: const Text('Reset Password'),
                            onPressed: () => _showResetPasswordModal(req),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () async {
                              await _resetService.rejectRequest(req.id);
                              _loadRequests();
                              widget.onRequestResolved();
                            },
                            child: const Text('Dismiss', style: TextStyle(color: Colors.grey)),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
