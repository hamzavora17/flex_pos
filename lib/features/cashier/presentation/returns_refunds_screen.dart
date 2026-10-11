import 'package:flutter/material.dart';

import '../../../core/theme/theme_helper.dart';
import '../../../core/theme/theme_toggle_button.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/completed_sale_model.dart';
import '../../../models/return_model.dart';
import '../../../services/receipt_printer_service.dart';
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

  Future<void> _printReceipt(ReturnReceiptModel receipt) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Preparing return receipt for POS printing...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      await ReceiptPrinterService.printReturnReceipt(receipt);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to print receipt: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

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

        if (mounted) {
          setState(() {
            _sales = sales;
            _saleReturnedQtyMap = returnedQtyMap;
            _isLoading = false;
          });
        }
      } else {
        final history = await _returnService.getReturnHistory();
        if (mounted) {
          setState(() {
            _returnHistory = history;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() async {
    if (_selectedTab == 0) {
      final sales = await _saleService.getCompletedSalesForCashier(
        searchQuery: _searchController.text,
      );
      final returnedQtyMap = <String, Map<String, int>>{};
      for (var sale in sales) {
        final map = await _returnService.getReturnedQuantitiesForSale(sale.id);
        returnedQtyMap[sale.id] = map;
      }
      if (mounted) {
        setState(() {
          _sales = sales;
          _saleReturnedQtyMap = returnedQtyMap;
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

    // Initialize return selection state ONLY for products with remaining returnable quantity > 0
    final selections = <ReturnItemSelection>[];
    for (var item in sale.items) {
      final pid = (item.productId != null && item.productId!.isNotEmpty && item.productId != 'null')
          ? item.productId!
          : item.id;
      final name = item.productNameSnapshot ?? item.productName ?? 'Product';
      final byProdId = (item.productId != null && item.productId!.isNotEmpty) ? (returnedMap[item.productId] ?? 0) : 0;
      final byItemId = returnedMap[item.id] ?? 0;
      final alreadyReturned = byProdId > byItemId ? byProdId : byItemId;
      final remainingQty = item.quantity - alreadyReturned;

      if (remainingQty > 0) {
        selections.add(ReturnItemSelection(
          productId: pid,
          productName: name,
          sku: item.skuSnapshot ?? item.productSku,
          selectedQuantity: 1,
          maxQuantity: remainingQty,
          unitPrice: item.unitPrice,
        ));
      }
    }

    if (selections.isEmpty) {
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

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
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

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(sel.productName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                        Text(
                                          'UnitPrice: ${CurrencyFormatter.format(sel.unitPrice)} | Remaining Returnable: ${sel.maxQuantity}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                        ),
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
                  onPressed: isSubmitting ? null : () => Navigator.of(dialogCtx).pop(),
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
                          final messenger = ScaffoldMessenger.of(context);

                          try {
                            final result = await _returnService.processReturn(
                              saleId: sale.id,
                              items: validSelections,
                              isDamaged: isDamaged,
                              paymentMethod: refundPaymentMethod,
                            );

                            if (result.isApproved && result.returnId.isNotEmpty) {
                              // Fetch the newly created return record directly from the database
                              final receipt = await _returnService.getReturnById(result.returnId);

                              if (dialogCtx.mounted) {
                                Navigator.of(dialogCtx).pop(); // Close inspection dialog
                              }
                              if (mounted) {
                                _showReturnReceiptDialog(receipt);
                              }
                            } else {
                              if (dialogCtx.mounted) {
                                Navigator.of(dialogCtx).pop();
                              }
                              messenger.showSnackBar(
                                SnackBar(content: Text(result.message), backgroundColor: Colors.red[800]),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red[800]),
                            );
                            if (mounted) {
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
            color: ctx.surfaceCard,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Receipt POS Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF003366).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF003366), size: 36),
              ),
              const SizedBox(height: 12),
              Text(
                'FLEXPOS RETURN RECEIPT',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0, color: ctx.textPrimary),
              ),
              const SizedBox(height: 4),
              Text('Official Refund & Inventory Restoration Record', style: TextStyle(fontSize: 11, color: ctx.textSecondary)),
              Divider(height: 24, thickness: 1, color: ctx.border),

              // Metadata Table
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Return Receipt #:', style: TextStyle(fontSize: 12, color: ctx.textSecondary)),
                  Text('#$shortReturnId', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Original Invoice #:', style: TextStyle(fontSize: 12, color: ctx.textSecondary)),
                  Text('#${receipt.originalInvoiceNumber}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ctx.textPrimary)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Return Date & Time:', style: TextStyle(fontSize: 12, color: ctx.textSecondary)),
                  Text(formattedDate, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ctx.textPrimary)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Refund Method:', style: TextStyle(fontSize: 12, color: ctx.textSecondary)),
                  Text(receipt.paymentMethod.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ctx.textPrimary)),
                ],
              ),
              Divider(height: 20, thickness: 1, color: ctx.border),

              // Returned Items Table
              Align(
                alignment: Alignment.centerLeft,
                child: Text('RETURNED PRODUCTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ctx.textSecondary, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ctx.inputBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ctx.border),
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
                                Text(item.productName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ctx.textPrimary)),
                                Text('${item.selectedQuantity}x @ ${CurrencyFormatter.format(item.unitPrice)}', style: TextStyle(fontSize: 11, color: ctx.textSecondary)),
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
              Divider(height: 20, thickness: 1, color: ctx.border),

              // Total Refund Issued
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TOTAL REFUND ISSUED:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: ctx.textPrimary)),
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
            onPressed: () => _printReceipt(receipt),
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
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        toolbarHeight: 52,
        backgroundColor: context.headerBg,
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
        actions: const [
          ThemeToggleButton(),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Tab Selection Bar
          Container(
            color: context.surfaceCard,
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
              decoration: BoxDecoration(
                color: context.surfaceCard,
                border: Border(bottom: BorderSide(color: context.border, width: 1)),
              ),
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: context.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search sales by invoice number, product or SKU...',
                    hintStyle: TextStyle(color: context.textSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF003366), size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded, size: 18, color: context.textSecondary),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: context.inputBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.border),
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
    // Filter sales to find items with remainingReturnableQty > 0
    final eligibleSales = _sales.where((sale) {
      final returnedMap = _saleReturnedQtyMap[sale.id] ?? {};
      final hasReturnableQty = sale.items.any((item) {
        final byProdId = (item.productId != null && item.productId!.isNotEmpty) ? (returnedMap[item.productId] ?? 0) : 0;
        final byItemId = returnedMap[item.id] ?? 0;
        final returned = byProdId > byItemId ? byProdId : byItemId;
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

        // Only include items that have remainingReturnableQty > 0
        final returnableItems = sale.items.where((item) {
          final byProdId = (item.productId != null && item.productId!.isNotEmpty) ? (returnedMap[item.productId] ?? 0) : 0;
          final byItemId = returnedMap[item.id] ?? 0;
          final retQty = byProdId > byItemId ? byProdId : byItemId;
          return (item.quantity - retQty) > 0;
        }).toList();

        final itemSummaries = returnableItems.map((i) {
          final byProdId = (i.productId != null && i.productId!.isNotEmpty) ? (returnedMap[i.productId] ?? 0) : 0;
          final byItemId = returnedMap[i.id] ?? 0;
          final retQty = byProdId > byItemId ? byProdId : byItemId;
          final remQty = i.quantity - retQty;
          final pName = i.productNameSnapshot ?? i.productName ?? 'Product';

          return '$remQty of ${i.quantity}x $pName';
        }).join(', ');

        return Card(
          color: context.surfaceCard,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: context.border),
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
                          Text(sale.invoiceNumber, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: context.textPrimary)),
                          const SizedBox(width: 10),
                          Text('${sale.itemCount} items • ${CurrencyFormatter.format(sale.total)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF003366))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(itemSummaries, style: TextStyle(fontSize: 12, color: context.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
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
          color: context.surfaceCard,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: context.border),
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
                          Text('Return #$shortId', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: context.textPrimary)),
                          const SizedBox(width: 8),
                          Text('Original Invoice: #${receipt.originalInvoiceNumber}', style: TextStyle(fontSize: 12, color: context.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(itemSummary, style: TextStyle(fontSize: 12, color: context.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(CurrencyFormatter.format(receipt.refundAmount), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF8DB600))),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF003366),
                            side: const BorderSide(color: Color(0xFF003366)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          icon: const Icon(Icons.receipt_long_rounded, size: 14),
                          label: const Text('View Receipt'),
                          onPressed: () => _showReturnReceiptDialog(receipt),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF003366),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          icon: const Icon(Icons.print_outlined, size: 14),
                          label: const Text('Print Receipt'),
                          onPressed: () => _printReceipt(receipt),
                        ),
                      ],
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
