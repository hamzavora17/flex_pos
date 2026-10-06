import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/held_sale_model.dart';
import '../../../services/held_sale_service.dart';

import 'new_sale_screen.dart';

class HeldSalesScreen extends StatefulWidget {
  const HeldSalesScreen({super.key});

  @override
  State<HeldSalesScreen> createState() => _HeldSalesScreenState();
}

class _HeldSalesScreenState extends State<HeldSalesScreen> {
  final HeldSaleService _heldSaleService = HeldSaleService();

  bool _isLoading = true;
  String? _error;
  List<HeldSaleModel> _heldSales = [];

  @override
  void initState() {
    super.initState();
    _loadHeldSales();
  }

  Future<void> _loadHeldSales() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sales = await _heldSaleService.getHeldSales();
      setState(() {
        _heldSales = sales;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatHeldTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $period';

    if (isToday) {
      return 'Held today at $timeStr';
    }
    return 'Held on ${dt.day}/${dt.month}/${dt.year} at $timeStr';
  }

  Future<void> _resumeSale(HeldSaleModel heldSale) async {
    try {
      final restoredCart = await _heldSaleService.resumeHeldSale(heldSale, const {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Held Sale #${heldSale.referenceNumber} restored to cart.'),
            backgroundColor: const Color(0xFF003366),
          ),
        );

        // Push replacement to NewSaleScreen with restored cart items
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => NewSaleScreen(initialCart: restoredCart),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resume sale: ${e.toString()}'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  Future<void> _confirmAndDelete(HeldSaleModel heldSale) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Held Sale?'),
        content: Text('Are you sure you want to delete ${heldSale.referenceNumber}? This action cannot be undone.'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _heldSaleService.deleteHeldSale(heldSale.id);
        _loadHeldSales();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Held Sale ${heldSale.referenceNumber} deleted.'),
              backgroundColor: const Color(0xFF003366),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting held sale: ${e.toString()}'),
              backgroundColor: Colors.red[800],
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 52,
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to Dashboard',
        ),
        title: Row(
          children: [
            const Text(
              'Held Sales',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF8DB600).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8DB600), width: 0.8),
              ),
              child: const Text(
                'Paused Transactions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF003366)))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF003366),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _loadHeldSales,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _heldSales.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF003366).withValues(alpha: 0.06),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.pause_circle_outline_rounded,
                                size: 48,
                                color: Color(0xFF003366),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No Held Sales',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'You currently have no paused sales.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ACTIVE HELD SALES (${_heldSales.length})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 14),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final w = constraints.maxWidth;
                              final count = w > 900 ? 3 : (w > 600 ? 2 : 1);

                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _heldSales.length,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: count,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  mainAxisExtent: 180.0,
                                ),
                                itemBuilder: (context, index) {
                                  final sale = _heldSales[index];
                                  final previewText = sale.items
                                      .map((i) => '${i.quantity}x ${i.productNameSnapshot}')
                                      .join(', ');

                                  return Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x06000000),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header Row: Reference & Timestamp
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Held Sale #${sale.referenceNumber}',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.amber.shade300, width: 0.8),
                                              ),
                                              child: Text(
                                                'HELD',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.amber.shade900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatHeldTime(sale.createdAt),
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                        ),

                                        const SizedBox(height: 10),

                                        // Item Summary & Preview
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${sale.itemCount} ${sale.itemCount == 1 ? 'item' : 'items'}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF475569),
                                              ),
                                            ),
                                            Text(
                                              CurrencyFormatter.format(sale.totalValue),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF003366),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          previewText.isNotEmpty ? previewText : 'No items preview',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),

                                        const Spacer(),

                                        // Action Buttons
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF003366),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  elevation: 0,
                                                ),
                                                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                                label: const Text('Resume', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                                onPressed: () => _resumeSale(sale),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                              tooltip: 'Delete Held Sale',
                                              onPressed: () => _confirmAndDelete(sale),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
    );
  }
}
