import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/category_model.dart';
import '../../../models/product_model.dart';
import '../../../services/category_service.dart';
import '../../../services/product_service.dart';

class SearchProductsScreen extends StatefulWidget {
  const SearchProductsScreen({super.key});

  @override
  State<SearchProductsScreen> createState() => _SearchProductsScreenState();
}

class _SearchProductsScreenState extends State<SearchProductsScreen> {
  final ProductService _productService = ProductService();
  final CategoryService _categoryService = CategoryService();

  bool _isLoading = true;
  String? _error;

  List<Product> _allProducts = [];
  List<Category> _categories = [];
  Map<String, String> _categoryMap = {};

  List<Product> _filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();

  String _selectedCategoryId = 'all';
  String _selectedStockFilter = 'all'; // 'all', 'in_stock', 'low_stock', 'out_of_stock'

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterProducts);
  }

  /// Sorts products:
  /// 1. In-stock products first, sorted A -> Z by name
  /// 2. Out-of-stock products second, sorted A -> Z by name
  List<Product> _sortProducts(List<Product> products) {
    final sorted = List<Product>.from(products);
    sorted.sort((a, b) {
      if (a.isInStock && !b.isInStock) {
        return -1; // In-stock first
      } else if (!a.isInStock && b.isInStock) {
        return 1; // Out-of-stock second
      } else {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
    return sorted;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load products catalog and categories
      final products = await _productService.getCashierCatalog();
      final categories = await _categoryService.getCategories();

      final catMap = <String, String>{};
      for (var c in categories) {
        catMap[c.id] = c.name;
      }

      setState(() {
        _allProducts = products;
        _categories = categories;
        _categoryMap = catMap;
        _isLoading = false;
      });

      _filterProducts();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _filterProducts() {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _allProducts.where((p) {
      final hasStock = p.isInStock;
      final categoryName = _categoryMap[p.categoryId] ?? '';

      // Category Filter
      if (_selectedCategoryId != 'all' && p.categoryId != _selectedCategoryId) {
        return false;
      }

      // Stock Filter
      if (_selectedStockFilter == 'in_stock' && !hasStock) return false;
      if (_selectedStockFilter == 'out_of_stock' && hasStock) return false;

      // Search Query Filter across Name, SKU, Barcode, Price, Category, Unit
      if (query.isNotEmpty) {
        final nameMatch = p.name.toLowerCase().contains(query);
        final skuMatch = p.sku?.toLowerCase().contains(query) ?? false;
        final barcodeMatch = p.barcode?.toLowerCase().contains(query) ?? false;
        final priceMatch = p.price.toStringAsFixed(2).contains(query) || p.price.toString().contains(query);
        final categoryMatch = categoryName.toLowerCase().contains(query);
        final unitMatch = p.unit.toLowerCase().contains(query);

        return nameMatch || skuMatch || barcodeMatch || priceMatch || categoryMatch || unitMatch;
      }

      return true;
    }).toList();

    setState(() {
      _filteredProducts = _sortProducts(filtered);
    });
  }

  void _showProductDetailsDialog(Product product) {
    final hasStock = product.isInStock;
    final categoryName = _categoryMap[product.categoryId] ?? 'Uncategorized';

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
              child: const Icon(Icons.inventory_2, color: Color(0xFF003366), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Informational Product Details (Read-Only)',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildDetailRow('Selling Price', CurrencyFormatter.format(product.price), isHighlighted: true),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildDetailRow('SKU Code', product.sku?.isNotEmpty == true ? product.sku! : 'N/A'),
                    const SizedBox(height: 8),
                    _buildDetailRow('Barcode', product.barcode?.isNotEmpty == true ? product.barcode! : 'N/A'),
                    const SizedBox(height: 8),
                    _buildDetailRow('Category', categoryName),
                    const SizedBox(height: 8),
                    _buildDetailRow('Unit Type', product.unit),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Availability Status',
                      hasStock ? 'IN STOCK' : 'OUT OF STOCK',
                      badgeColor: hasStock ? const Color(0xFF8DB600) : Colors.red[800]!,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
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

  Widget _buildDetailRow(String label, String value, {bool isHighlighted = false, Color? badgeColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isHighlighted ? const Color(0xFF003366) : const Color(0xFF64748B),
            fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        if (badgeColor != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: badgeColor, width: 0.8),
            ),
            child: Text(
              value,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
            ),
          )
        else
          Text(
            value,
            style: TextStyle(
              fontSize: isHighlighted ? 16 : 13,
              fontWeight: isHighlighted ? FontWeight.w900 : FontWeight.bold,
              color: isHighlighted ? const Color(0xFF003366) : const Color(0xFF0F172A),
            ),
          ),
      ],
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
              'Search Products',
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
                'Informational Lookup',
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF003366)),
            )
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
              : Column(
                  children: [
                    // Search & Filter Header Panel
                    _buildSearchHeaderPanel(),

                    // Search Results List / Grid
                    Expanded(
                      child: _buildSearchResults(),
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
          // Search Input Bar
          SizedBox(
            height: 48,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Search by product name, SKU, barcode, price or category...',
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

          // Filters Row: Category & Stock Filter Dropdowns
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Category Filter Dropdown
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
                    value: _selectedCategoryId,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF003366)),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedCategoryId = val;
                        });
                        _filterProducts();
                      }
                    },
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Categories')),
                      ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                    ],
                  ),
                ),
              ),

              // Stock Status Filter Dropdown
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
                    value: _selectedStockFilter,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF003366)),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedStockFilter = val;
                        });
                        _filterProducts();
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Stock Statuses')),
                      DropdownMenuItem(value: 'in_stock', child: Text('In Stock Only')),
                      DropdownMenuItem(value: 'low_stock', child: Text('Low Stock Only')),
                      DropdownMenuItem(value: 'out_of_stock', child: Text('Out of Stock Only')),
                    ],
                  ),
                ),
              ),

              // Results Counter
              Text(
                'Showing ${_filteredProducts.length} ${_filteredProducts.length == 1 ? 'product' : 'products'}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_filteredProducts.isEmpty) {
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
                  Icons.search_off_rounded,
                  size: 44,
                  color: Color(0xFF003366),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No products found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Try searching with another product name, SKU, barcode,\nprice, or reset your active filters.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (_searchController.text.isNotEmpty || _selectedCategoryId != 'all' || _selectedStockFilter != 'all')
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF003366),
                    side: const BorderSide(color: Color(0xFF003366)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reset Search & Filters'),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _selectedCategoryId = 'all';
                      _selectedStockFilter = 'all';
                    });
                    _filterProducts();
                  },
                ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final count = w > 1100 ? 4 : (w > 800 ? 3 : (w > 550 ? 2 : 1));

        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 140.0,
          ),
          itemCount: _filteredProducts.length,
          itemBuilder: (context, index) {
            final product = _filteredProducts[index];
            final hasStock = product.isInStock;
            final categoryName = _categoryMap[product.categoryId] ?? 'General';

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showProductDetailsDialog(product),
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
                  child: Opacity(
                    opacity: hasStock ? 1.0 : 0.65,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Row: Category Badge & Stock Badge
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF003366).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  categoryName,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF003366),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: !hasStock
                                      ? Colors.red.shade50
                                      : const Color(0xFF8DB600).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: !hasStock
                                        ? Colors.red.shade200
                                        : const Color(0xFF8DB600).withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  hasStock ? 'IN STOCK' : 'OUT OF STOCK',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: !hasStock
                                        ? Colors.red.shade800
                                        : const Color(0xFF003366),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Product Name
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),

                          // SKU / Barcode Subtitle
                          Text(
                            (product.sku != null && product.sku!.trim().isNotEmpty)
                                ? 'SKU: ${product.sku}'
                                : (product.barcode != null && product.barcode!.trim().isNotEmpty)
                                    ? 'Barcode: ${product.barcode}'
                                    : 'Unit: ${product.unit}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const Spacer(),

                          // Price Footer
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${CurrencyFormatter.format(product.price)} / ${product.unit}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF003366),
                                ),
                              ),
                              const Icon(Icons.info_outline, size: 16, color: Color(0xFF003366)),
                            ],
                          ),
                        ],
                      ),
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
