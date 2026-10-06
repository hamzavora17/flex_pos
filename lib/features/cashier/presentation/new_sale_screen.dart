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
      _discount = double.tryParse(_discountController.text) ?? 0.0;
      if (_discount < 0) {
        _discount = 0.0;
      }
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
        _discount = 0.0;
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

    if (_subtotal - _discount < 0) {
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
        discount: _discount,
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
                    _discount = 0.0;
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
        const SnackBar(content: Text('Item is currently out of stock')),
      );
      return;
    }

    final existingIndex = _cart.indexWhere((c) => c.product.id == product.id);
    if (existingIndex >= 0) {
      setState(() {
        _cart[existingIndex].quantity++;
      });
    } else {
      setState(() {
        _cart.add(CartItemModel(product: product, maxStock: 999999));
      });
    }
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

  Widget _buildProductGrid() {
    return Column(
      children: [
        // Prominent Search Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
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
                hintText: 'Search products by name, SKU or barcode...',
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
        ),

        // Product Catalog Grid Container
        Expanded(
          child: Container(
            color: const Color(0xFFF8FAFC),
            child: _filteredProducts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF003366).withValues(alpha: 0.06),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              size: 42,
                              color: Color(0xFF003366),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _searchController.text.isEmpty
                                ? 'No products available'
                                : 'No products match "${_searchController.text}"',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _searchController.text.isEmpty
                                ? 'Add products to inventory to display them here.'
                                : 'Try searching with a different product name, SKU, or barcode.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
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
                      if (width >= 1100) {
                        crossAxisCount = 5;
                      } else if (width >= 850) {
                        crossAxisCount = 4;
                      } else if (width >= 600) {
                        crossAxisCount = 3;
                      } else {
                        crossAxisCount = 2;
                      }

                      const double spacing = 12.0;

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          mainAxisExtent: 195.0,
                        ),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          final hasStock = product.isInStock;
                          final cartIndex =
                              _cart.indexWhere((c) => c.product.id == product.id);
                          final inCartCount =
                              cartIndex >= 0 ? _cart[cartIndex].quantity : 0;

                          return _buildProductCard(
                            product: product,
                            hasStock: hasStock,
                            inCartCount: inCartCount,
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard({
    required Product product,
    required bool hasStock,
    required int inCartCount,
  }) {
    final bool isSelected = inCartCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasStock ? () => _addToCart(product) : null,
        mouseCursor: hasStock ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF003366)
                  : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Opacity(
            opacity: hasStock ? 1.0 : 0.5,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF003366).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            product.name.isNotEmpty
                                ? product.name.characters.first.toUpperCase()
                                : 'P',
                            style: const TextStyle(
                              color: Color(0xFF003366),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                              hasStock ? 'In Stock' : 'Out of stock',
                              style: TextStyle(
                                color: !hasStock
                                    ? Colors.red.shade700
                                    : const Color(0xFF003366),
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8DB600),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'In Cart: $inCartCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF0F172A),
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (product.sku != null && product.sku!.trim().isNotEmpty)
                        ? 'SKU: ${product.sku}'
                        : (product.barcode != null && product.barcode!.trim().isNotEmpty)
                            ? 'BC: ${product.barcode}'
                            : 'Unit: ${product.unit}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          CurrencyFormatter.format(product.price),
                          style: const TextStyle(
                            color: Color(0xFF003366),
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: hasStock ? const Color(0xFF003366) : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: hasStock ? Colors.white : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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

            // Checkout Summary Panel (Fixed at Bottom)
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Discount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
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
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            prefixText: CurrencyFormatter.symbol,
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Payment',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
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
                            DropdownMenuItem(value: 'qr', child: Text('QR Code')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _paymentMethod = val);
                            }
                          },
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
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
                  const Divider(height: 20, color: Color(0xFFE2E8F0)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(_total),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF003366),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Action Buttons: Hold Sale & Complete Sale
                  Row(
                    children: [
                      // Hold Sale Button
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
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
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.pause_circle_outline, size: 18),
                            label: const Text(
                              'Hold',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Complete Sale Button
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 50,
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
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'COMPLETE SALE',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                          ),
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
    );
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
                border: Border.all(color: const Color(0xFF8DB600), width: 0.8),
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
                  backgroundColor: const Color(0xFF8DB600),
                  child: const Icon(Icons.shopping_cart, color: Colors.white),
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF003366)),
            )
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
              : isDesktop
                  ? Row(
                      children: [
                        Expanded(child: _buildProductGrid()),
                        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                        SizedBox(width: 380, child: _buildCartPanel()),
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
