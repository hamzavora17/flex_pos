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

  int _selectedTab = 0; // 0 = Eligible Sales, 1 = Return History
  bool _isLoading = true;
  String? _error;
  List<CompletedSaleModel> _sales = [];
  Map<String, Map<String, int>> _saleReturnedQtyMap = {}; // saleId -> (productId -> returnedQty)
  List<ReturnReceiptModel> _returnHistory = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);

    if (widget.initialSale != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openReturnInspectionDialog(widget.initialSale!);
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_selectedTab == 0) {
        final sales = await _saleService.getCompletedSalesForCashier(
          searchQuery: _searchController.text,
        );
        
        final returnedQtyMap = <String, Map<String, int>>{};
        for (var sale in sales) {
          final map = await _returnService.getReturnedQuantitiesForSale(sale.id);
          returnedQtyMap[sale.id] = map;
        }

        setState(() {
          _sales = sales;
          _saleReturnedQtyMap = returnedQtyMap;
          _isLoading = false;
        });
      } else {
        final history = await _returnService.getReturnHistory();
        setState(() {
          _returnHistory = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() async {
    if (_selectedTab == 0) {
      final sales = await _saleService.getCompletedSalesForCashier(
        searchQuery: _searchController.text,
      );
      if (mounted) {
        setState(() {
          _sales = sales;
        });
      }
    }
  }

  Future<void> _openReturnInspectionDialog(CompletedSaleModel sale) async {
    if (sale.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items available in this sale to return.')),
      );
      return;
    }

    // Loader dialog while resolving returnable quantities
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF003366)),
      ),
    );

    final returnedMap = await _returnService.getReturnedQuantitiesForSale(sale.id);
    if (mounted) Navigator.of(context).pop(); // Close loader

    // Initialize return selection state with accurate remaining returnable quantities
    final selections = sale.items.map((item) {
      final pid = item.productId ?? item.id;
      final name = item.productNameSnapshot ?? item.productName ?? 'Product';
      final alreadyReturned = returnedMap[pid] ?? 0;
      final remainingQty = (item.quantity - alreadyReturned) > 0 ? (item.quantity - alreadyReturned) : 0;

      return ReturnItemSelection(
        productId: pid,
        productName: name,
        sku: item.skuSnapshot ?? item.productSku,
        selectedQuantity: remainingQty > 0 ? 1 : 0,
        maxQuantity: remainingQty,
        unitPrice: item.unitPrice,
      );
    }).toList();

    final hasReturnableItems = selections.any((s) => s.maxQuantity > 0);
    if (!hasReturnableItems) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All items in this sale have already been fully returned.')),
        );
      }
      return;
    }

    bool isDamaged = false; // Inspection decision
    String refundPaymentMethod = sale.paymentMethod;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final validSelections = selections.where((s) => s.selectedQuantity > 0).toList();
            final totalRefund = validSelections.fold(0.0, (sum, item) => sum + item.lineRefund);
            final totalQty = validSelections.fold(0, (sum, item) => sum + item.selectedQuantity);

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
                            final isFullyReturned = sel.maxQuantity == 0;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(sel.productName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isFullyReturned ? Colors.grey : const Color(0xFF0F172A))),
                                        Text(
                                          isFullyReturned
                                              ? 'Fully Returned (Max: 0)'
                                              : 'UnitPrice: ${CurrencyFormatter.format(sel.unitPrice)} | Remaining Returnable: ${sel.maxQuantity}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: isFullyReturned ? FontWeight.bold : FontWeight.normal,
                                            color: isFullyReturned ? Colors.red.shade700 : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Quantity Selector
                                  if (!isFullyReturned)
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
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.red.shade200),
                                      ),
                                      child: const Text('Fully Returned', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // STEP 2: Inspect Product Condition
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
                              items: validSelections,
                              isDamaged: isDamaged,
                              paymentMethod: refundPaymentMethod,
                            );

                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();

                              if (result.isApproved) {
                                final receipt = ReturnReceiptModel(
                                  returnId: result.returnId,
                                  originalInvoiceNumber: sale.invoiceNumber,
                                  returnDate: DateTime.now(),
                                  returnedItems: validSelections,
                                  refundAmount: result.refundAmount, // Authentic server refund
                                  paymentMethod: refundPaymentMethod,
                                  status: 'Approved',
                                );
                                _showReturnReceiptDialog(receipt);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(result.message), backgroundColor: Colors.red[800]),
                                );
                              }
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red[800]),
                              );
                              _loadData(); // Refresh UI state on error
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

  void _showReturnReceiptDialog(ReturnReceiptModel receipt) {
    final formattedDate = '${receipt.returnDate.day.toString().padLeft(2, '0')}/${receipt.returnDate.month.toString().padLeft(2, '0')}/${receipt.returnDate.year} ${receipt.returnDate.hour.toString().padLeft(2, '0')}:${receipt.returnDate.minute.toString().padLeft(2, '0')}';
    final shortReturnId = receipt.returnId.length > 8 ? receipt.returnId.substring(0, 8).toUpperCase() : receipt.returnId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: 440,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Receipt POS Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF003366).withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF003366), size: 36),
              ),
              const SizedBox(height: 12),
              const Text(
                'FLEXPOS RETURN RECEIPT',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 4),
              const Text('Official Refund & Inventory Restoration Record', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              const Divider(height: 24, thickness: 1),

              // Metadata Table
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Return Receipt #:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  Text('#$shortReturnId', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Original Invoice #:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  Text('#${receipt.originalInvoiceNumber}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Return Date & Time:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  Text(formattedDate, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Refund Method:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  Text(receipt.paymentMethod.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(height: 20, thickness: 1),

              // Returned Items Table
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('RETURNED PRODUCTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5)),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: receipt.returnedItems.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                Text('${item.selectedQuantity}x @ ${CurrencyFormatter.format(item.unitPrice)}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              ],
                            ),
                          ),
                          Text(CurrencyFormatter.format(item.lineRefund), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 20, thickness: 1),

              // Total Refund Issued
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL REFUND ISSUED:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  Text(
                    CurrencyFormatter.format(receipt.refundAmount),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF8DB600)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8DB600).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF8DB600)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF003366)),
                    SizedBox(width: 6),
                    Text('APPROVED & STOCK RESTORED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Print Receipt'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sending return receipt to POS receipt printer...')),
              );
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _loadData(); // Refresh sales list and return history
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
      body: Column(
        children: [
          // Tab Selection Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('Eligible Sales for Return'),
                        icon: Icon(Icons.assignment_return_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('Return History & Receipts'),
                        icon: Icon(Icons.history_rounded, size: 18),
                      ),
                    ],
                    selected: {_selectedTab},
                    onSelectionChanged: (set) {
                      setState(() {
                        _selectedTab = set.first;
                        _loadData();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Search Bar Header (For Eligible Sales Tab)
          if (_selectedTab == 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
              ),
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'Search sales by invoice number, product or SKU...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF003366), size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ),
            ),

          // Content Area
          Expanded(
            child: _isLoading
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
                              onPressed: _loadData,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _selectedTab == 0
                        ? _buildEligibleSalesList()
                        : _buildReturnHistoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEligibleSalesList() {
    // Filter sales to find items with maxQuantity > 0
    final eligibleSales = _sales.where((sale) {
      final returnedMap = _saleReturnedQtyMap[sale.id] ?? {};
      final hasReturnableQty = sale.items.any((item) {
        final pid = item.productId ?? item.id;
        final returned = returnedMap[pid] ?? 0;
        return (item.quantity - returned) > 0;
      });
      return hasReturnableQty;
    }).toList();

    if (eligibleSales.isEmpty) {
      return Center(
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
                child: const Icon(Icons.assignment_return_outlined, size: 44, color: Color(0xFF003366)),
              ),
              const SizedBox(height: 16),
              const Text('No Returnable Sales Available', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 6),
              const Text('All products from recent completed sales have been fully returned or match no sales.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: eligibleSales.length,
      itemBuilder: (context, index) {
        final sale = eligibleSales[index];
        final returnedMap = _saleReturnedQtyMap[sale.id] ?? {};

        final itemSummaries = sale.items.map((i) {
          final pid = i.productId ?? i.id;
          final retQty = returnedMap[pid] ?? 0;
          final remQty = (i.quantity - retQty) > 0 ? (i.quantity - retQty) : 0;
          final pName = i.productNameSnapshot ?? i.productName ?? 'Product';

          if (remQty == 0) {
            return '$pName [Fully Returned]';
          }
          return '$remQty of ${i.quantity}x $pName';
        }).join(', ');

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
                          Text(sale.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                          const SizedBox(width: 10),
                          Text('${sale.itemCount} items • ${CurrencyFormatter.format(sale.total)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF003366))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(itemSummaries, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    );
  }

  Widget _buildReturnHistoryList() {
    if (_returnHistory.isEmpty) {
      return Center(
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
                child: const Icon(Icons.history_rounded, size: 44, color: Color(0xFF003366)),
              ),
              const SizedBox(height: 16),
              const Text('No Return History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 6),
              const Text('No approved product returns have been processed yet.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _returnHistory.length,
      itemBuilder: (context, index) {
        final receipt = _returnHistory[index];
        final shortId = receipt.returnId.length > 8 ? receipt.returnId.substring(0, 8).toUpperCase() : receipt.returnId;
        final itemSummary = receipt.returnedItems.map((i) => '${i.selectedQuantity}x ${i.productName}').join(', ');

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
                          Text('Return #$shortId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                          const SizedBox(width: 8),
                          Text('Original Invoice: #${receipt.originalInvoiceNumber}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(itemSummary, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(CurrencyFormatter.format(receipt.refundAmount), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF8DB600))),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF003366),
                        side: const BorderSide(color: Color(0xFF003366)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.receipt_long_rounded, size: 14),
                      label: const Text('View Receipt'),
                      onPressed: () => _showReturnReceiptDialog(receipt),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
