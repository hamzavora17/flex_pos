import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/product_model.dart';
import '../../../services/product_service.dart';

/// Screen enabling Managers to view store catalog products, exact stock levels, purchase costs, and stock status alerts.
class ManagerProductsScreen extends StatefulWidget {
  const ManagerProductsScreen({super.key});

  @override
  State<ManagerProductsScreen> createState() => _ManagerProductsScreenState();
}

class _ManagerProductsScreenState extends State<ManagerProductsScreen> {
  final ProductService _productService = ProductService();
  final TextEditingController _searchController = TextEditingController();

  List<Product> _products = [];
  bool _isLoading = true;
  String _selectedStockFilter = 'all'; // 'all', 'in_stock', 'low_stock', 'out_of_stock'
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _productService.getManagerProducts();
      if (mounted) {
        setState(() {
          _products = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load manager products: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();

    return _products.where((product) {
      // Search Query Filter
      if (query.isNotEmpty) {
        final nameMatch = product.name.toLowerCase().contains(query);
        final skuMatch = (product.sku ?? '').toLowerCase().contains(query);
        final barcodeMatch = (product.barcode ?? '').toLowerCase().contains(query);
        if (!nameMatch && !skuMatch && !barcodeMatch) return false;
      }

      // Stock Status Filter based on exact stock quantity vs minStockAlert threshold
      final qty = product.stockQuantity;
      final isOut = qty <= 0;
      final isLow = qty > 0 && qty <= product.minStockAlert;
      final isIn = qty > product.minStockAlert;

      if (_selectedStockFilter == 'in_stock' && !isIn) return false;
      if (_selectedStockFilter == 'low_stock' && !isLow) return false;
      if (_selectedStockFilter == 'out_of_stock' && !isOut) return false;

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;

    return Column(
      children: [
        // Filter & Search Header
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
                        hintText: 'Search products by Name, SKU, or Barcode...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF003366)),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Stock Status: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedStockFilter,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Stock Levels')),
                      DropdownMenuItem(value: 'in_stock', child: Text('In Stock Only')),
                      DropdownMenuItem(value: 'low_stock', child: Text('Low Stock Alerts')),
                      DropdownMenuItem(value: 'out_of_stock', child: Text('Out of Stock Only')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedStockFilter = val);
                      }
                    },
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length} products listed',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Products List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                'No store products match your filters.',
                                style: TextStyle(color: Colors.grey[600], fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadProducts,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final product = filtered[index];
                              final qty = product.stockQuantity;
                              final isOut = qty <= 0;
                              final isLow = qty > 0 && qty <= product.minStockAlert;

                              final statusLabel = isOut
                                  ? 'OUT OF STOCK'
                                  : isLow
                                      ? 'LOW STOCK'
                                      : 'IN STOCK';

                              final statusColor = isOut
                                  ? Colors.red.shade700
                                  : isLow
                                      ? Colors.orange.shade800
                                      : const Color(0xFF0369A1);

                              final statusBg = isOut
                                  ? Colors.red.shade50
                                  : isLow
                                      ? Colors.orange.shade50
                                      : const Color(0xFFE0F2FE);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  product.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color: Color(0xFF1E293B),
                                                  ),
                                                ),
                                                if (product.sku != null && product.sku!.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'SKU: ${product.sku}',
                                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusBg,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              statusLabel,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Divider(height: 1),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Stock Quantity',
                                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$qty ${product.unit}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Selling Price',
                                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  CurrencyFormatter.format(product.price),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                    color: Color(0xFF003366),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Min Stock Threshold',
                                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${product.minStockAlert} ${product.unit}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                    color: Color(0xFF475569),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
