import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/completed_sale_model.dart';
import '../../../models/return_model.dart';
import '../../../services/return_service.dart';
import '../../../services/sale_service.dart';

class ReturnsRefundsScreen extends StatefulWidget {
  final CompletedSaleModel? initialSale;

  const ReturnsRefundsScreen({
    super.key,
    this.initialSale,
  });

  @override
  State<ReturnsRefundsScreen> createState() => _ReturnsRefundsScreenState();
}

class _ReturnsRefundsScreenState extends State<ReturnsRefundsScreen> {
  final SaleService _saleService = SaleService();
  final ReturnService _returnService = ReturnService();

  bool _isLoading = true;
  String? _error;
  List<CompletedSaleModel> _sales = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSales();
    _searchController.addListener(_onSearchChanged);

    if (widget.initialSale != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openReturnInspectionDialog(widget.initialSale!);
      });
    }
  }

  Future<void> _loadSales() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sales = await _saleService.getCompletedSalesForCashier(
        searchQuery: _searchController.text,
      );
      setState(() {
        _sales = sales;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() async {
    final sales = await _saleService.getCompletedSalesForCashier(
      searchQuery: _searchController.text,
    );
    if (mounted) {
      setState(() {
        _sales = sales;
      });
    }
  }

  void _openReturnInspectionDialog(CompletedSaleModel sale) {
    if (sale.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items available in this sale to return.')),
      );
      return;
    }

    // Initialize return selection state
    final selections = sale.items.map((item) {
      final name = item.productNameSnapshot ?? item.productName ?? 'Product';
      return ReturnItemSelection(
        productId: item.productId ?? item.id,
        productName: name,
        sku: item.skuSnapshot ?? item.productSku,
        selectedQuantity: 1, // Default 1 for return selection
        maxQuantity: item.quantity,
        unitPrice: item.unitPrice,
      );
    }).toList();

    bool isDamaged = false; // Inspection decision
    String refundPaymentMethod = sale.paymentMethod;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final totalRefund = selections.fold(0.0, (sum, item) => sum + item.lineRefund);
            final totalQty = selections.fold(0, (sum, item) => sum + item.selectedQuantity);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF003366).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.assignment_return_rounded, color: Color(0xFF003366), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Return Inspection - #${sale.invoiceNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Select products, inspect condition, and process refund',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // STEP 1: Select Product + Quantity
                      const Text('STEP 1: SELECT PRODUCT & QUANTITY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: selections.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final sel = entry.value;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(sel.productName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                        Text('UnitPrice: ${CurrencyFormatter.format(sel.unitPrice)} | Max: ${sel.maxQuantity}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                      ],
                                    ),
                                  ),

                                  // Quantity Selector
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 20, color: Color(0xFF003366)),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        onPressed: sel.selectedQuantity > 0
                                            ? () {
                                                setDialogState(() {
                                                  selections[idx] = sel.copyWith(selectedQuantity: sel.selectedQuantity - 1);
                                                });
                                              }
                                            : null,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text(
                                          '${sel.selectedQuantity}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, size: 20, color: Color(0xFF003366)),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        onPressed: sel.selectedQuantity < sel.maxQuantity
                                            ? () {
                                                setDialogState(() {
                                                  selections[idx] = sel.copyWith(selectedQuantity: sel.selectedQuantity + 1);
                                                });
                                              }
                                            : null,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // STEP 2: Inspect Product
                      const Text('STEP 2: INSPECT PRODUCT CONDITION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDamaged ? Colors.red.shade50 : const Color(0xFF8DB600).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isDamaged ? Colors.red.shade300 : const Color(0xFF8DB600)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Is the product damaged or unsellable?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF003366)),
                                        SizedBox(width: 6),
                                        Text('NO (Intact / Good)'),
                                      ],
                                    ),
                                    selected: !isDamaged,
                                    selectedColor: const Color(0xFF8DB600).withValues(alpha: 0.3),
                                    onSelected: (val) {
                                      if (val) setDialogState(() => isDamaged = false);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                                        SizedBox(width: 6),
                                        Text('YES (Damaged)'),
                                      ],
                                    ),
                                    selected: isDamaged,
                                    selectedColor: Colors.red.shade100,
                                    onSelected: (val) {
                                      if (val) setDialogState(() => isDamaged = true);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isDamaged
                                  ? '⚠️ Inspection Result: DAMAGED GOODS REJECTED. Return cannot be approved.'
                                  : '✅ Inspection Result: INTACT GOODS APPROVED. Proceeding to refund calculation.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDamaged ? Colors.red.shade800 : const Color(0xFF003366),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // STEP 3: Refund Calculation Summary
                      const Text('STEP 3: REFUND SUMMARY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Items to Return:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                Text('$totalQty items', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Calculated Refund Amount:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                Text(
                                  CurrencyFormatter.format(isDamaged ? 0.0 : totalRefund),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: isDamaged ? Colors.red.shade800 : const Color(0xFF003366),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDamaged ? Colors.red[800] : const Color(0xFF003366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: (totalQty == 0 || isSubmitting)
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);

                          try {
                            final result = await _returnService.processReturn(
                              saleId: sale.id,
                              items: selections,
                              isDamaged: isDamaged,
                              paymentMethod: refundPaymentMethod,
                            );

                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              _showReturnResultOutcomeDialog(result);
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red[800]),
                              );
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(isDamaged ? 'Reject Return' : 'Approve & Process Refund'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showReturnResultOutcomeDialog(ReturnResultModel result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              result.isApproved ? Icons.check_circle : Icons.cancel,
              color: result.isApproved ? const Color(0xFF8DB600) : Colors.red[800],
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              result.isApproved ? 'Return Approved' : 'Return Rejected',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: result.isApproved ? const Color(0xFF8DB600).withValues(alpha: 0.1) : Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: result.isApproved ? const Color(0xFF8DB600) : Colors.red.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.message,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: result.isApproved ? const Color(0xFF003366) : Colors.red.shade900,
                    ),
                  ),
                  if (result.isApproved) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Refund Issued:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        Text(
                          CurrencyFormatter.format(result.refundAmount),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF003366)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Inventory Stock:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        Text('Restored (+Stock)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF8DB600))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _loadSales(); // Refresh sales
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
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
              'Returns & Refunds',
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
                'Product Return Management',
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
                        onPressed: _loadSales,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Search Bar Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                        ),
                      ),
                      child: SizedBox(
                        height: 48,
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            hintText: 'Search completed sales by invoice number, product or SKU...',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF003366), size: 22),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                                    onPressed: () => _searchController.clear(),
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF003366), width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Sales List
                    Expanded(
                      child: _sales.isEmpty
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
                                        Icons.assignment_return_outlined,
                                        size: 44,
                                        color: Color(0xFF003366),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No Sales Found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'No completed sales match your current search query.',
                                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(20),
                              itemCount: _sales.length,
                              itemBuilder: (context, index) {
                                final sale = _sales[index];
                                final itemSummary = sale.items
                                    .map((i) => '${i.quantity}x ${i.productNameSnapshot ?? i.productName ?? 'Product'}')
                                    .join(', ');

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    sale.invoiceNumber,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    '${sale.itemCount} items • ${CurrencyFormatter.format(sale.total)}',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF003366)),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                itemSummary,
                                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF003366),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          icon: const Icon(Icons.assignment_return_outlined, size: 16),
                                          label: const Text('Process Return'),
                                          onPressed: () => _openReturnInspectionDialog(sale),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
