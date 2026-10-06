import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/completed_sale_model.dart';
import '../../../services/sale_service.dart';

/// Screen enabling Managers to search, filter, and inspect store-wide cashier sales.
class ManagerSalesScreen extends StatefulWidget {
  const ManagerSalesScreen({super.key});

  @override
  State<ManagerSalesScreen> createState() => _ManagerSalesScreenState();
}

class _ManagerSalesScreenState extends State<ManagerSalesScreen> {
  final SaleService _saleService = SaleService();
  final TextEditingController _searchController = TextEditingController();

  List<CompletedSaleModel> _sales = [];
  bool _isLoading = true;
  String _selectedDateFilter = 'all'; // 'all', 'today', 'yesterday', 'last_7_days'
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStoreSales();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStoreSales() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _saleService.getStoreSales(
        searchQuery: _searchController.text,
        dateFilter: _selectedDateFilter,
      );
      if (mounted) {
        setState(() {
          _sales = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load store sales: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Filter Bar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search store sales (Invoice #, Product, SKU)...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF003366)),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _loadStoreSales();
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _loadStoreSales(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.filter_list, size: 18),
                    label: const Text('Search'),
                    onPressed: _loadStoreSales,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Date Filter: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedDateFilter,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Time')),
                      DropdownMenuItem(value: 'today', child: Text('Today')),
                      DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
                      DropdownMenuItem(value: 'last_7_days', child: Text('Last 7 Days')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedDateFilter = val);
                        _loadStoreSales();
                      }
                    },
                  ),
                  const Spacer(),
                  Text(
                    '${_sales.length} store sales found',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Sales List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : _sales.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                'No store sales match your filters.',
                                style: TextStyle(color: Colors.grey[600], fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadStoreSales,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _sales.length,
                            itemBuilder: (context, index) {
                              final sale = _sales[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 1,
                                child: ExpansionTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.point_of_sale, color: Color(0xFF0369A1)),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          sale.invoiceNumber,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                      ),
                                      Text(
                                        CurrencyFormatter.format(sale.total),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF003366),
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Payment: ${sale.paymentMethod.toUpperCase()}',
                                          style: TextStyle(color: Colors.grey[700], fontSize: 12),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Status: ${sale.status.toUpperCase()}',
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      color: const Color(0xFFF8FAFC),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Sale Items:',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          const SizedBox(height: 8),
                                          ...sale.items.map((item) {
                                            final name = item.productNameSnapshot ?? item.productName ?? 'Item';
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '• $name (x${item.quantity})',
                                                      style: const TextStyle(fontSize: 13),
                                                    ),
                                                  ),
                                                  Text(
                                                    CurrencyFormatter.format(item.lineTotal),
                                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
