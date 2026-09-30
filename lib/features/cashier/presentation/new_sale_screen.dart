import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/product_model.dart';
import '../../../services/product_service.dart';
import '../../../services/inventory_service.dart';
import '../../../services/business_service.dart';
import '../../../services/sale_service.dart';

class CartItemModel {
  final Product product;
  int quantity;
  final int maxStock;

  CartItemModel({
    required this.product,
    this.quantity = 1,
    required this.maxStock,
  });

  double get lineTotal => product.price * quantity;
}

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final ProductService _productService = ProductService();
  final InventoryService _inventoryService = InventoryService();
  final BusinessService _businessService = BusinessService();
  final SaleService _saleService = SaleService();

  bool _isLoading = true;
  String? _error;

  String? _branchId;
  List<Product> _allProducts = [];
  Map<String, int> _productStocks = {};

  List<Product> _filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();

  // Cart State
  final List<CartItemModel> _cart = [];
  double _discount = 0.0;
  String _paymentMethod = 'cash';
  final TextEditingController _discountController = TextEditingController();
  bool _isCheckingOut = false;

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.lineTotal);
  double get _total => (_subtotal - _discount) > 0 ? (_subtotal - _discount) : 0;
  int get _totalItems => _cart.fold(0, (sum, item) => sum + item.quantity);

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
    _discountController.addListener(_onDiscountChanged);
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bId = await _businessService.getBusinessId();

      // Get branch (just take the first one for now)
      final branchResponse = await Supabase.instance.client
          .from('branches')
          .select('id')
          .eq('business_id', bId)
          .limit(1);

      if (branchResponse.isEmpty) {
        throw Exception('No branch found for this business.');
      }

      _branchId = branchResponse.first['id'].toString();

      // Load products
      final products = await _productService.getActiveProducts();

      // Load inventory for all products to get stock
      final inventoryItems = await _inventoryService.getInventory();
      final stockMap = <String, int>{};
      for (var item in inventoryItems) {
        if (item.branchId == _branchId || item.branchId == null) {
          stockMap[item.productId] = item.quantity;
        }
      }

      setState(() {
        _allProducts = products;
        _productStocks = stockMap;
        _filteredProducts = products;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final nameMatch = p.name.toLowerCase().contains(query);
        final skuMatch = p.sku?.toLowerCase().contains(query) ?? false;
        final barcodeMatch = p.barcode?.toLowerCase().contains(query) ?? false;
        return nameMatch || skuMatch || barcodeMatch;
      }).toList();
    });
  }

  void _onDiscountChanged() {
    setState(() {
      _discount = double.tryParse(_discountController.text) ?? 0.0;
      if (_discount < 0) {
        _discount = 0.0;
      }
    });
  }

  Future<void> _completeSale() async {
    if (_cart.isEmpty || _isCheckingOut || _branchId == null) return;
    
    // Validate discount not making total negative
    if (_subtotal - _discount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Discount cannot exceed subtotal')),
      );
      return;
    }

    setState(() => _isCheckingOut = true);

    try {
      final items = _cart.map((c) => CartItem(
            productId: c.product.id,
            quantity: c.quantity,
          )).toList();

      final response = await _saleService.checkout(
        branchId: _branchId!,
        items: items,
        paymentMethod: _paymentMethod,
        discount: _discount,
      );

      final saleId = response['sale_id'] ?? 'Unknown';
      final totalPaid = response['total'] ?? _total;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Sale Complete'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invoice: #$saleId'),
                Text('Payment: ${_paymentMethod.toUpperCase()}'),
                Text('Total Paid: \$${(totalPaid as num).toStringAsFixed(2)}', 
                     style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  setState(() {
                    _cart.clear();
                    _discountController.clear();
                    _discount = 0.0;
                    _paymentMethod = 'cash';
                    _isCheckingOut = false;
                  });
                  _loadData(); // reload stock from DB
                },
                child: const Text('New Sale'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isCheckingOut = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _addToCart(Product product) {
    final maxStock = _productStocks[product.id] ?? 0;

    if (maxStock <= 0) {
      return; // Handled by UI disabling, but just in case
    }

    final existingIndex = _cart.indexWhere((c) => c.product.id == product.id);
    if (existingIndex >= 0) {
      if (_cart[existingIndex].quantity < maxStock) {
        setState(() {
          _cart[existingIndex].quantity++;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot exceed available stock')),
        );
      }
    } else {
      setState(() {
        _cart.add(CartItemModel(product: product, maxStock: maxStock));
      });
    }
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      final item = _cart[index];
      final newQty = item.quantity + delta;

      if (newQty <= 0) {
        _cart.removeAt(index);
      } else if (newQty <= item.maxStock) {
        item.quantity = newQty;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot exceed available stock')),
        );
      }
    });
  }

  void _removeItem(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  Widget _buildProductGrid() {
    return Column(
      children: [
        // Search Header
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search products by name, SKU, or barcode...',
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF003366)),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF003366), width: 1.5),
              ),
            ),
          ),
        ),

        // Product Grid Content
        Expanded(
          child: _filteredProducts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF003366).withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: Color(0xFF003366),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty
                              ? 'No products available'
                              : 'No products match "${_searchController.text}"',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchController.text.isEmpty
                              ? 'Add products to inventory to see them here.'
                              : 'Try searching with a different term or SKU.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    int crossAxisCount;
                    if (width >= 1200) {
                      crossAxisCount = 6;
                    } else if (width >= 960) {
                      crossAxisCount = 5;
                    } else if (width >= 700) {
                      crossAxisCount = 4;
                    } else if (width >= 460) {
                      crossAxisCount = 3;
                    } else {
                      crossAxisCount = 2;
                    }

                    const double padding = 32.0; // 16 left + 16 right
                    const double spacing = 12.0;
                    final double cardWidth =
                        (width - padding - (crossAxisCount - 1) * spacing) /
                            crossAxisCount;

                    // Adapt card height based on width so name, price, and stock remain readable
                    final double cardHeight =
                        (cardWidth * 1.12).clamp(190.0, 225.0);

                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        mainAxisExtent: cardHeight,
                      ),
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        final stock = _productStocks[product.id] ?? 0;
                        final hasStock = stock > 0;
                        final cartIndex =
                            _cart.indexWhere((c) => c.product.id == product.id);
                        final inCartCount =
                            cartIndex >= 0 ? _cart[cartIndex].quantity : 0;

                        return _buildProductCard(
                          product: product,
                          stock: stock,
                          hasStock: hasStock,
                          inCartCount: inCartCount,
                          cardHeight: cardHeight,
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProductCard({
    required Product product,
    required int stock,
    required bool hasStock,
    required int inCartCount,
    required double cardHeight,
  }) {
    final bool isLowStock = hasStock && stock <= product.minStockAlert;
    final bool isSelected = inCartCount > 0;
    final double imageHeight = (cardHeight * 0.38).clamp(68.0, 88.0);

    return Card(
      elevation: isSelected ? 2 : 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF003366)
              : Colors.grey.shade200,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasStock ? () => _addToCart(product) : null,
        child: Opacity(
          opacity: hasStock ? 1.0 : 0.55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Branded Placeholder / Image Area
              Stack(
                children: [
                  Container(
                    height: imageHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF003366).withValues(alpha: 0.08),
                          const Color(0xFF003366).withValues(alpha: 0.02),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: (imageHeight * 0.52).clamp(34.0, 44.0),
                        height: (imageHeight * 0.52).clamp(34.0, 44.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF003366)
                                  .withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            product.name.isNotEmpty
                                ? product.name.characters.first.toUpperCase()
                                : 'P',
                            style: TextStyle(
                              color: const Color(0xFF003366),
                              fontWeight: FontWeight.bold,
                              fontSize:
                                  (imageHeight * 0.22).clamp(14.0, 18.0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Stock Badge (Top-Right)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      constraints: const BoxConstraints(maxWidth: 100),
                      decoration: BoxDecoration(
                        color: !hasStock
                            ? Colors.red.shade50
                            : isLowStock
                                ? Colors.orange.shade50
                                : const Color(0xFF8DB600)
                                    .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: !hasStock
                              ? Colors.red.shade200
                              : isLowStock
                                  ? Colors.orange.shade200
                                  : const Color(0xFF8DB600)
                                      .withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        hasStock ? '$stock ${product.unit}' : 'Out of stock',
                        style: TextStyle(
                          color: !hasStock
                              ? Colors.red.shade700
                              : isLowStock
                                  ? Colors.orange.shade800
                                  : const Color(0xFF003366),
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  // In Cart Quantity Badge (Top-Left)
                  if (isSelected)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8DB600),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.shopping_cart_rounded,
                              size: 10,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$inCartCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              // Product Info Area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (product.sku != null &&
                              product.sku!.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'SKU: ${product.sku}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ] else if (product.barcode != null &&
                              product.barcode!.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'BC: ${product.barcode}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              '\$${product.price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFF003366),
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: hasStock
                                  ? const Color(0xFF003366)
                                  : Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 16,
                              color: Colors.white,
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
        ),
      ),
    );
  }

  Widget _buildCartPanel() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Current Sale Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: const Color(0xFF003366),
              child: Row(
                children: [
                  const Icon(Icons.shopping_cart_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Current Sale',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '$_totalItems ${_totalItems == 1 ? 'item' : 'items'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cart Items List / Empty State
            Expanded(
              child: _cart.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF003366).withValues(alpha: 0.05),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.remove_shopping_cart_outlined,
                                size: 44,
                                color: Color(0xFF003366),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Cart is empty',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap products from the catalog to add them to this sale.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _cart.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.grey.shade100,
                      ),
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Product Info & Line Total
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: Color(0xFF1E293B),
                                        height: 1.2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '\$${item.product.price.toStringAsFixed(2)} / ${item.product.unit}',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Total: \$${item.lineTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Color(0xFF003366),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Quantity Controls & Remove Action
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.grey.shade300, width: 0.8),
                                    ),
                                    child: Row(
                                      children: [
                                        InkWell(
                                          onTap: () => _updateQuantity(index, -1),
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(7),
                                            bottomLeft: Radius.circular(7),
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(6.0),
                                            child: Icon(
                                              Icons.remove_rounded,
                                              size: 16,
                                              color: Color(0xFF003366),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8.0),
                                          child: Text(
                                            '${item.quantity}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => _updateQuantity(index, 1),
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(7),
                                            bottomRight: Radius.circular(7),
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(6.0),
                                            child: Icon(
                                              Icons.add_rounded,
                                              size: 16,
                                              color: Color(0xFF003366),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.red.shade400,
                                      size: 20,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    tooltip: 'Remove item',
                                    onPressed: () => _removeItem(index),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Summary Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Subtotal',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '\$${_subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Discount',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _discountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            prefixText: '\$',
                            prefixStyle: const TextStyle(
                              color: Color(0xFF003366),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0xFF003366), width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Payment',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 130,
                        child: DropdownButtonFormField<String>(
                          initialValue: _paymentMethod,
                          items: const [
                            DropdownMenuItem(value: 'cash', child: Text('Cash')),
                            DropdownMenuItem(value: 'card', child: Text('Card')),
                            DropdownMenuItem(value: 'upi', child: Text('UPI')),
                            DropdownMenuItem(value: 'qr', child: Text('QR')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _paymentMethod = val);
                            }
                          },
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0xFF003366), width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        '\$${_total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF003366),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed:
                          (_cart.isEmpty || _isCheckingOut) ? null : _completeSale,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8DB600),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        disabledForegroundColor: Colors.grey.shade400,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isCheckingOut
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Complete Sale',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Sale'),
        actions: [
          if (!isDesktop)
            Builder(
              builder: (ctx) => IconButton(
                icon: Badge(
                  label: Text('$_totalItems'),
                  isLabelVisible: _totalItems > 0,
                  child: const Icon(Icons.shopping_cart),
                ),
                onPressed: () {
                  Scaffold.of(ctx).openEndDrawer();
                },
              ),
            ),
        ],
      ),
      endDrawer: !isDesktop
          ? Drawer(
              width: 380,
              child: _buildCartPanel(),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _loadData, child: const Text('Retry')),
                    ],
                  ),
                )
              : isDesktop
                  ? Row(
                      children: [
                        Expanded(child: _buildProductGrid()),
                        const VerticalDivider(width: 1, thickness: 1),
                        SizedBox(width: 400, child: _buildCartPanel()),
                      ],
                    )
                  : _buildProductGrid(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    super.dispose();
  }
}
