import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/completed_sale_model.dart';
import '../../../services/sale_service.dart';
import 'returns_refunds_screen.dart';

class PreviousSalesScreen extends StatefulWidget {
  const PreviousSalesScreen({super.key});

  @override
  State<PreviousSalesScreen> createState() => _PreviousSalesScreenState();
}

class _PreviousSalesScreenState extends State<PreviousSalesScreen> {
  final SaleService _saleService = SaleService();

  bool _isLoading = true;
  String? _error;
  List<CompletedSaleModel> _sales = [];

  final TextEditingController _searchController = TextEditingController();
  String _selectedDateFilter = 'all'; // 'today', 'yesterday', 'last_7_days', 'all'

  @override
  void initState() {
    super.initState();
    _loadSales();
    _searchController.addListener(_onSearchOrFilterChanged);
  }

  Future<void> _loadSales() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final salesList = await _saleService.getCompletedSalesForCashier(
        searchQuery: _searchController.text,
        dateFilter: _selectedDateFilter,
      );

      setState(() {
        _sales = salesList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchOrFilterChanged() async {
    final salesList = await _saleService.getCompletedSalesForCashier(
      searchQuery: _searchController.text,
      dateFilter: _selectedDateFilter,
    );
    if (mounted) {
      setState(() {
        _sales = salesList;
      });
    }
  }

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    final year = dt.year;

    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';

    return '$day $month $year • $hour:$minute $period';
  }

  void _showSaleDetailsDialog(CompletedSaleModel sale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF003366).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF003366), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.invoiceNumber,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    _formatDateTime(sale.createdAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Items Table Container
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    // Table Header
                    const Row(
                      children: [
                        Expanded(flex: 3, child: Text('ITEM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                        SizedBox(width: 60, child: Text('QTY', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                        SizedBox(width: 70, child: Text('PRICE', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                      ],
                    ),
                    const Divider(height: 12, color: Color(0xFFE2E8F0)),

                    // Items Rows
                    ...sale.items.map((item) {
                      final name = item.productNameSnapshot ?? item.productName ?? 'Product';
                      final sku = item.skuSnapshot ?? item.productSku ?? '';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                  if (sku.isNotEmpty)
                                    Text('SKU: $sku', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 60,
                              child: Text(
                                '${item.quantity}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(
                              width: 70,
                              child: Text(
                                CurrencyFormatter.format(item.lineTotal),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF003366)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Summary Details
              _buildSummaryRow('Subtotal', CurrencyFormatter.format(sale.subtotal)),
              if (sale.discount > 0)
                _buildSummaryRow('Discount', '-${CurrencyFormatter.format(sale.discount)}', isDiscount: true),
              if (sale.tax > 0)
                _buildSummaryRow('Tax', CurrencyFormatter.format(sale.tax)),
              _buildSummaryRow('Payment Method', sale.paymentMethod.toUpperCase(), isText: true),
              const Divider(height: 16, color: Color(0xFFE2E8F0)),
              _buildSummaryRow('Grand Total', CurrencyFormatter.format(sale.total), isTotal: true),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF003366),
              side: const BorderSide(color: Color(0xFF003366)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.assignment_return_outlined, size: 16),
            label: const Text('Return Items'),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReturnsRefundsScreen(initialSale: sale)),
              );
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isDiscount = false, bool isText = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 12,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? const Color(0xFF0F172A) : const Color(0xFF64748B),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 12,
              fontWeight: isTotal ? FontWeight.w900 : FontWeight.bold,
              color: isTotal
                  ? const Color(0xFF003366)
                  : (isDiscount ? Colors.green[700] : const Color(0xFF0F172A)),
            ),
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
              'Previous Sales',
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
                'Sales History',
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
                    // Search & Date Filter Panel
                    _buildSearchHeaderPanel(),

                    // Sales History List
                    Expanded(
                      child: _buildSalesList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSearchHeaderPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Field
          SizedBox(
            height: 48,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Search by invoice number, product name, or SKU...',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF003366), size: 22),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                        onPressed: () {
                          _searchController.clear();
                        },
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
          const SizedBox(height: 14),

          // Date Filter Dropdown & Results Counter
          Row(
            children: [
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedDateFilter,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF003366)),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedDateFilter = val;
                        });
                        _onSearchOrFilterChanged();
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Time')),
                      DropdownMenuItem(value: 'today', child: Text('Today')),
                      DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
                      DropdownMenuItem(value: 'last_7_days', child: Text('Last 7 Days')),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Showing ${_sales.length} ${_sales.length == 1 ? 'sale' : 'sales'}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSalesList() {
    if (_sales.isEmpty) {
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
                child: const Icon(
                  Icons.receipt_long_outlined,
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
                'No completed sales match your current search query or date filter.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final count = w > 900 ? 3 : (w > 600 ? 2 : 1);

        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 165.0,
          ),
          itemCount: _sales.length,
          itemBuilder: (context, index) {
            final sale = _sales[index];
            final previewText = sale.items
                .map((i) => '${i.quantity}x ${i.productNameSnapshot ?? i.productName ?? 'Product'}')
                .join(', ');

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showSaleDetailsDialog(sale),
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(12),
                child: Ink(
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
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Row: Invoice # & COMPLETED status
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              sale.invoiceNumber,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8DB600).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF8DB600), width: 0.8),
                              ),
                              child: const Text(
                                'COMPLETED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF003366),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDateTime(sale.createdAt),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),

                        const SizedBox(height: 10),

                        // Item Count, Payment Method & Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${sale.itemCount} ${sale.itemCount == 1 ? 'item' : 'items'} • ${sale.paymentMethod.toUpperCase()}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(sale.total),
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

                        const Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'View Receipt & Details',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF003366)),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF003366)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
