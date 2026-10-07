import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/product_model.dart';
import '../../../services/business_service.dart';
import '../../../services/held_sale_service.dart';
import '../../../services/product_service.dart';
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
  final List<CartItemModel>? initialCart;

  const NewSaleScreen({
    super.key,
    this.initialCart,
  });

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final ProductService _productService = ProductService();
  final BusinessService _businessService = BusinessService();
  final SaleService _saleService = SaleService();
  final HeldSaleService _heldSaleService = HeldSaleService();

  bool _isLoading = true;
  String? _error;

  String? _branchId;
  List<Product> _allProducts = [];

  List<Product> _filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();

  // Cart State
  final List<CartItemModel> _cart = [];
  double _discountPercent = 0.0;
  String _paymentMethod = 'cash'; // 'cash' or 'upi'
  final TextEditingController _discountController = TextEditingController();
  bool _isCheckingOut = false;

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.lineTotal);
  double get _discountAmount => _subtotal * (_discountPercent / 100.0);
  double get _total => (_subtotal - _discountAmount) > 0 ? (_subtotal - _discountAmount) : 0;
  int get _totalItems => _cart.fold(0, (sum, item) => sum + item.quantity);

  @override
  void initState() {
    super.initState();
    if (widget.initialCart != null && widget.initialCart!.isNotEmpty) {
      _cart.addAll(widget.initialCart!);
    }
    _loadData();
    _searchController.addListener(_onSearchChanged);
    _discountController.addListener(_onDiscountChanged);
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
      final bId = await _businessService.getBusinessId();

      // Get branch
      final branchResponse = await Supabase.instance.client
          .from('branches')
          .select('id')
          .eq('business_id', bId)
          .limit(1);

      if (branchResponse.isEmpty) {
        throw Exception('No branch found for this business.');
      }

      _branchId = branchResponse.first['id'].toString();

      // Load cashier products catalog from cashier_products view
      final products = await _productService.getCashierCatalog();

      setState(() {
        _allProducts = products;
        _filteredProducts = _sortProducts(products);
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
      final matches = _allProducts.where((p) {
        final nameMatch = p.name.toLowerCase().contains(query);
        final skuMatch = p.sku?.toLowerCase().contains(query) ?? false;
        final barcodeMatch = p.barcode?.toLowerCase().contains(query) ?? false;
        return nameMatch || skuMatch || barcodeMatch;
      }).toList();

      _filteredProducts = _sortProducts(matches);
    });
  }

  void _onDiscountChanged() {
    setState(() {
      final val = double.tryParse(_discountController.text) ?? 0.0;
      _discountPercent = val.clamp(0.0, 100.0);
    });
  }

  Future<void> _clearCart() async {
    if (_cart.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('Clear Cart?'),
          ],
        ),
        content: const Text('Are you sure you want to remove all items from the current cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Cart'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _cart.clear();
      _discountController.clear();
      _discountPercent = 0.0;
    });
  }

  Future<void> _holdCurrentSale() async {
    if (_cart.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Hold this sale?'),
        content: const Text('The current cart will be saved and cleared so you can start another sale.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hold Sale'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final heldSale = await _heldSaleService.holdSale(
        branchId: _branchId,
        cartItems: _cart,
      );

      setState(() {
        _cart.clear();
        _discountController.clear();
        _discountPercent = 0.0;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sale #${heldSale.referenceNumber} saved to Held Sales.'),
            backgroundColor: const Color(0xFF003366),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to hold sale: ${e.toString()}'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  Future<void> _completeSale() async {
    if (_cart.isEmpty || _isCheckingOut || _branchId == null) return;

    if (_subtotal - _discountAmount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Discount cannot exceed subtotal')),
      );
      return;
    }

    setState(() => _isCheckingOut = true);

    try {
      final items = _cart
          .map((c) => CartItem(
                productId: c.product.id,
                quantity: c.quantity,
              ))
          .toList();

      final response = await _saleService.checkout(
        branchId: _branchId!,
        items: items,
        paymentMethod: _paymentMethod,
        discount: _discountAmount,
      );

      final saleId = response['sale_id'] ?? 'Unknown';
      final totalPaid = response['total'] ?? _total;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF8DB600), size: 26),
                SizedBox(width: 10),
                Text('Sale Completed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Invoice #:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          Text('#$saleId', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Payment Method:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          Text(_paymentMethod.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Paid:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                          Text(
                            CurrencyFormatter.format(totalPaid as num),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF003366)),
                          ),
                        ],
                      ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  setState(() {
                    _cart.clear();
                    _discountController.clear();
                    _discountPercent = 0.0;
                    _paymentMethod = 'cash';
                    _isCheckingOut = false;
                  });
                  _loadData(); // reload stock from DB
                },
                child: const Text('Start Next Sale', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isCheckingOut = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red[800]),
        );
      }
    }
  }

  void _addToCart(Product product) {
    if (!product.isInStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} is out of stock.'),
          backgroundColor: Colors.red[800],
        ),
      );
      return;
    }

    setState(() {
      final existingIndex = _cart.indexWhere((c) => c.product.id == product.id);
      if (existingIndex >= 0) {
        _cart[existingIndex].quantity++;
      } else {
        _cart.add(CartItemModel(product: product, maxStock: 999999));
      }
    });
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      final item = _cart[index];
      final newQty = item.quantity + delta;

      if (newQty <= 0) {
        _cart.removeAt(index);
      } else {
        item.quantity = newQty;
      }
    });
  }

  void _removeItem(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

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
              'New Sale',
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
                border: Border.all(
                  color: const Color(0xFF8DB600),
                  width: 0.8,
                ),
              ),
              child: const Text(
                'POS Checkout Terminal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (!isDesktop)
            Builder(
              builder: (ctx) => IconButton(
                icon: Badge(
                  label: Text('$_totalItems'),
                  isLabelVisible: _totalItems > 0,
                  child: const Icon(Icons.shopping_cart_rounded, color: Colors.white, size: 22),
                ),
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                tooltip: 'Open Cart Panel',
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF003366)))
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
              : Row(
                  children: [
                    // Main Catalog Area
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          // Search & Filter Header
                          Container(
                            padding: const EdgeInsets.all(16),
                            color: Colors.white,
                            child: SizedBox(
                              height: 44,
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search products by name, SKU or barcode...',
                                  hintStyle: const TextStyle(
                                      color: Color(0xFF94A3B8), fontSize: 13),
                                  prefixIcon: const Icon(Icons.search_rounded,
                                      color: Color(0xFF003366), size: 20),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close_rounded,
                                              size: 18,
                                              color: Color(0xFF64748B)),
                                          onPressed: () =>
                                              _searchController.clear(),
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFF003366), width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Product Grid
                          Expanded(
                            child: _filteredProducts.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                            Icons.inventory_2_outlined,
                                            size: 48,
                                            color: Color(0xFF94A3B8)),
                                        const SizedBox(height: 12),
                                        const Text('No products found',
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0F172A))),
                                        const SizedBox(height: 4),
                                        Text(
                                            _searchController.text.isNotEmpty
                                                ? 'Try adjusting your search query'
                                                : 'No active products in catalog',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF64748B))),
                                      ],
                                    ),
                                  )
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      final width = constraints.maxWidth;
                                      int crossAxisCount = 3;
                                      if (width > 1200) {
                                        crossAxisCount = 5;
                                      } else if (width > 900) {
                                        crossAxisCount = 4;
                                      } else if (width > 600) {
                                        crossAxisCount = 3;
                                      } else {
                                        crossAxisCount = 2;
                                      }

                                      return GridView.builder(
                                        padding: const EdgeInsets.all(16),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                          childAspectRatio: 0.85,
                                        ),
                                        itemCount: _filteredProducts.length,
                                        itemBuilder: (context, index) {
                                          final product =
                                              _filteredProducts[index];
                                          final cartIndex = _cart.indexWhere(
                                              (c) =>
                                                  c.product.id == product.id);
                                          final inCartCount = cartIndex >= 0
                                              ? _cart[cartIndex].quantity
                                              : 0;

                                          return _buildProductCard(
                                            product: product,
                                            inCartCount: inCartCount,
                                          );
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),

                    // Side Cart Panel (Desktop)
                    if (isDesktop)
                      const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
                    if (isDesktop)
                      SizedBox(width: 380, child: _buildCartPanel()),
                  ],
                ),
    );
  }

  Widget _buildProductCard({
    required Product product,
    required int inCartCount,
  }) {
    final bool isSelected = inCartCount > 0;
    final bool hasStock = product.isInStock;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF003366)
              : (hasStock
                  ? const Color(0xFFE2E8F0)
                  : Colors.red.shade200),
          width: isSelected ? 2 : 1,
        ),
      ),
      color: hasStock ? Colors.white : const Color(0xFFFFF5F5),
      child: InkWell(
        onTap: hasStock ? () => _addToCart(product) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stock Badge / Selected Count Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: hasStock
                          ? const Color(0xFF8DB600).withValues(alpha: 0.15)
                          : Colors.red.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      hasStock ? 'In Stock' : 'Out of Stock',
                      style: TextStyle(
                        color: hasStock
                            ? const Color(0xFF003366)
                            : Colors.red.shade800,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF003366),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$inCartCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),

              // Product Info
              Text(
                product.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: hasStock
                      ? const Color(0xFF0F172A)
                      : Colors.grey.shade600,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (product.sku != null && product.sku!.isNotEmpty)
                Text(
                  'SKU: ${product.sku}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),

              // Price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    CurrencyFormatter.format(product.price),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: hasStock
                          ? const Color(0xFF003366)
                          : Colors.grey.shade500,
                    ),
                  ),
                  Icon(
                    Icons.add_circle_rounded,
                    color: hasStock
                        ? const Color(0xFF003366)
                        : Colors.grey.shade400,
                    size: 22,
                  ),
                ],
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
            // Current Sale Header (Clean, only item count badge)
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
                      fontSize: 16,
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
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cart Items List / Polished Empty State
            Expanded(
              child: _cart.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF003366).withValues(alpha: 0.05),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.remove_shopping_cart_outlined,
                                size: 40,
                                color: Color(0xFF003366),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Current Sale',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Your cart is empty',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Add products from the catalog\nto begin this sale.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                                height: 1.3,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _cart.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x04000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFF0F172A),
                                        height: 1.2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _removeItem(index),
                                    mouseCursor: SystemMouseCursors.click,
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2.0),
                                      child: Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.red.shade400,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${CurrencyFormatter.format(item.product.price)} / ${item.product.unit}',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: const Color(0xFFE2E8F0), width: 1),
                                    ),
                                    child: Row(
                                      children: [
                                        InkWell(
                                          onTap: () => _updateQuantity(index, -1),
                                          mouseCursor: SystemMouseCursors.click,
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(5),
                                            bottomLeft: Radius.circular(5),
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                                            child: Icon(
                                              Icons.remove_rounded,
                                              size: 15,
                                              color: Color(0xFF003366),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: Text(
                                            '${item.quantity}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => _updateQuantity(index, 1),
                                          mouseCursor: SystemMouseCursors.click,
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(5),
                                            bottomRight: Radius.circular(5),
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                                            child: Icon(
                                              Icons.add_rounded,
                                              size: 15,
                                              color: Color(0xFF003366),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    CurrencyFormatter.format(item.lineTotal),
                                    style: const TextStyle(
                                      color: Color(0xFF003366),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Checkout Summary Panel (Fixed at Bottom with Clear Hierarchy)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Subtotal Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Subtotal',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(_subtotal),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 2. Percentage Discount Section
                  Row(
                    children: [
                      const Text(
                        'Discount (%)',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _discountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            suffixText: '%',
                            suffixStyle: const TextStyle(
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
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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
                  if (_subtotal > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [5, 10, 15, 20].map((pct) {
                          final isSelected = (_discountPercent - pct).abs() < 0.1;
                          return Padding(
                            padding: const EdgeInsets.only(left: 4.0),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _discountController.text = pct.toString();
                                  _discountPercent = pct.toDouble();
                                });
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF003366) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF003366) : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Text(
                                  '$pct%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  if (_discountAmount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Discount (${_discountPercent.toStringAsFixed(0)}%)', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                          Text('-${CurrencyFormatter.format(_discountAmount)}', style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),

                  // 3. Payment Mode Section (Cash & UPI Only)
                  Row(
                    children: [
                      const Text(
                        'Payment Mode',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          ChoiceChip(
                            showCheckmark: false,
                            avatar: Icon(Icons.payments_rounded, size: 15, color: _paymentMethod == 'cash' ? Colors.white : const Color(0xFF003366)),
                            label: const Text('Cash'),
                            selected: _paymentMethod == 'cash',
                            selectedColor: const Color(0xFF003366),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _paymentMethod == 'cash' ? Colors.white : const Color(0xFF0F172A),
                            ),
                            visualDensity: VisualDensity.compact,
                            onSelected: (selected) {
                              if (selected) setState(() => _paymentMethod = 'cash');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            showCheckmark: false,
                            avatar: Icon(Icons.mobile_friendly_rounded, size: 15, color: _paymentMethod == 'upi' ? Colors.white : const Color(0xFF003366)),
                            label: const Text('UPI'),
                            selected: _paymentMethod == 'upi',
                            selectedColor: const Color(0xFF003366),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _paymentMethod == 'upi' ? Colors.white : const Color(0xFF0F172A),
                            ),
                            visualDensity: VisualDensity.compact,
                            onSelected: (selected) {
                              if (selected) setState(() => _paymentMethod = 'upi');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),

                  // 4. Strongly Separated TOTAL Box
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF003366).withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF003366).withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'TOTAL AMOUNT',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(_total),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF003366),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 5. Clean Actions (Secondary actions row + Primary PAY & COMPLETE button)
                  Row(
                    children: [
                      // Secondary Action: Hold
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: OutlinedButton.icon(
                            onPressed: (_cart.isEmpty || _isCheckingOut)
                                ? null
                                : _holdCurrentSale,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.amber.shade900,
                              side: BorderSide(
                                color: _cart.isEmpty
                                    ? Colors.grey.shade300
                                    : Colors.amber.shade800,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            icon: const Icon(Icons.pause_circle_outline, size: 16),
                            label: const Text(
                              'Hold',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Secondary Action: Clear Cart
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: OutlinedButton.icon(
                            onPressed: (_cart.isEmpty || _isCheckingOut)
                                ? null
                                : _clearCart,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(
                                color: _cart.isEmpty
                                    ? Colors.grey.shade300
                                    : Colors.red.shade300,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                            label: const Text(
                              'Clear Cart',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Primary Action: PAY & COMPLETE SALE
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_cart.isEmpty || _isCheckingOut)
                          ? null
                          : _completeSale,
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
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_rounded, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'PAY & COMPLETE SALE',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
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
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    super.dispose();
  }
}
