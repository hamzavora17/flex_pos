import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/inventory_model.dart';
import '../../../models/product_model.dart';
import '../../../services/business_service.dart';
import '../../../services/inventory_service.dart';
import '../../../services/product_service.dart';

/// Historical reference check status for fail-closed product deletion safety.
enum HistoryCheckResult {
  noHistory,
  historyExists,
  checkFailed,
}

/// Screen enabling Managers to view, search, filter, create, edit, deactivate, and delete store catalog products and stock levels.
class ManagerProductsScreen extends StatefulWidget {
  const ManagerProductsScreen({super.key});

  @override
  State<ManagerProductsScreen> createState() => _ManagerProductsScreenState();
}

class _ManagerProductsScreenState extends State<ManagerProductsScreen> {
  final ProductService _productService = ProductService();
  final InventoryService _inventoryService = InventoryService();
  final BusinessService _businessService = BusinessService();
  final TextEditingController _searchController = TextEditingController();

  List<Product> _products = [];
  List<Map<String, dynamic>> _branches = [];
  bool _branchLoadFailed = false;
  bool _isLoading = true;
  String _selectedStockFilter = 'all'; // 'all', 'in_stock', 'low_stock', 'out_of_stock'
  String? _errorMessage;

  bool get _isSingleBranch => !_branchLoadFailed && _branches.length == 1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final bId = await _businessService.getBusinessId();

      List<Map<String, dynamic>> branches = [];
      bool branchFailed = false;

      // Fetch all store branches
      try {
        final branchRes = await Supabase.instance.client
            .from('branches')
            .select('id, name')
            .eq('business_id', bId);

        branches = List<Map<String, dynamic>>.from(branchRes as List? ?? []);
      } catch (_) {
        branchFailed = true;
      }

      // Load manager products with aggregated inventory
      final list = await _productService.getManagerProducts();

      if (mounted) {
        setState(() {
          _branches = branches;
          _branchLoadFailed = branchFailed;
          _products = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load manager products: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  /// Fail-closed pre-check to verify if a product has any historical references
  /// across sale_items, sale_return_items, held_sale_items, and inventory_logs.
  Future<HistoryCheckResult> _checkHasHistoricalReferences(String productId) async {
    try {
      final client = Supabase.instance.client;

      final salesCheck = await client
          .from('sale_items')
          .select('id')
          .eq('product_id', productId)
          .limit(1);
      if (salesCheck.isNotEmpty) return HistoryCheckResult.historyExists;

      final returnCheck = await client
          .from('sale_return_items')
          .select('id')
          .eq('product_id', productId)
          .limit(1);
      if (returnCheck.isNotEmpty) return HistoryCheckResult.historyExists;

      final heldCheck = await client
          .from('held_sale_items')
          .select('id')
          .eq('product_id', productId)
          .limit(1);
      if (heldCheck.isNotEmpty) return HistoryCheckResult.historyExists;

      final logCheck = await client
          .from('inventory_logs')
          .select('id')
          .eq('product_id', productId)
          .limit(1);
      if (logCheck.isNotEmpty) return HistoryCheckResult.historyExists;

      return HistoryCheckResult.noHistory;
    } catch (_) {
      // Query failed due to network, database, or RLS error -> Fail closed!
      return HistoryCheckResult.checkFailed;
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

      // Stock Status Filter based on stock quantity vs minStockAlert threshold
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

  void _openProductDialog([Product? existingProduct]) {
    final isEditing = existingProduct != null;
    final formKey = GlobalKey<FormState>();

    final nameController = TextEditingController(text: existingProduct?.name ?? '');
    final skuController = TextEditingController(text: existingProduct?.sku ?? '');
    final barcodeController = TextEditingController(text: existingProduct?.barcode ?? '');
    final priceController = TextEditingController(
        text: isEditing ? existingProduct.price.toStringAsFixed(2) : '');
    final costController = TextEditingController(
        text: isEditing ? existingProduct.cost.toStringAsFixed(2) : '0.00');
    final stockController = TextEditingController(
        text: isEditing ? existingProduct.stockQuantity.toString() : '0');
    final minStockController = TextEditingController(
        text: isEditing ? existingProduct.minStockAlert.toString() : '5');

    String selectedUnit = existingProduct?.unit ?? 'pcs';
    bool activeStatus = existingProduct?.active ?? true;
    bool isSaving = false;

    final unitOptions = ['pcs', 'kg', 'g', 'ltr', 'ml', 'box', 'pack'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                    child: Icon(
                      isEditing ? Icons.edit_note_rounded : Icons.add_box_rounded,
                      color: const Color(0xFF003366),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Edit Product' : 'Add New Product',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        Text(
                          isEditing
                              ? 'Update catalog details & inventory levels'
                              : 'Create a new product item in catalog',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product Name
                        TextFormField(
                          controller: nameController,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            labelText: 'Product Name *',
                            hintText: 'e.g. Colgate Strong Teeth 150g',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Product name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Unit & Active Status Row
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: selectedUnit,
                                items: unitOptions
                                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => selectedUnit = val);
                                  }
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Unit *',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Active in Catalog', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    Switch(
                                      value: activeStatus,
                                      activeThumbColor: const Color(0xFF8DB600),
                                      onChanged: (val) {
                                        setDialogState(() => activeStatus = val);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // SKU & Barcode
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: skuController,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  labelText: 'SKU (Optional)',
                                  hintText: 'e.g. Toothpaste-150',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: barcodeController,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  labelText: 'Barcode (Optional)',
                                  hintText: 'e.g. 890123456789',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Pricing: Selling Price & Cost Price
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: priceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  labelText: 'Selling Price (₹) *',
                                  hintText: '0.00',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Price required';
                                  final numVal = double.tryParse(val.trim());
                                  if (numVal == null || numVal < 0) return 'Invalid price';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: costController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  labelText: 'Cost Price (₹) *',
                                  hintText: '0.00',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Cost required';
                                  final numVal = double.tryParse(val.trim());
                                  if (numVal == null || numVal < 0) return 'Invalid cost';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Inventory: Stock Quantity & Min Threshold
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: stockController,
                                enabled: _isSingleBranch,
                                keyboardType: TextInputType.number,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _isSingleBranch ? Colors.black : Colors.grey[700],
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Stock Quantity *',
                                  hintText: '100',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  helperText: !_isSingleBranch
                                      ? (_branches.length > 1
                                          ? 'Stock editing is disabled for multi-branch stores as inventory is managed per branch.'
                                          : 'Stock editing is disabled as a valid store branch context could not be determined.')
                                      : null,
                                  helperMaxLines: 2,
                                ),
                                validator: (val) {
                                  if (!_isSingleBranch) return null;
                                  if (val == null || val.trim().isEmpty) return 'Stock required';
                                  final numVal = int.tryParse(val.trim());
                                  if (numVal == null || numVal < 0) return 'Invalid quantity';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: minStockController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  labelText: 'Low Stock Alert *',
                                  hintText: '5',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Threshold required';
                                  final numVal = int.tryParse(val.trim());
                                  if (numVal == null || numVal < 0) return 'Invalid threshold';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);

                          String targetProductId = '';
                          String name = '';

                          try {
                            name = nameController.text.trim();
                            final sku = skuController.text.trim();
                            final barcode = barcodeController.text.trim();
                            final price = double.parse(priceController.text.trim());
                            final cost = double.parse(costController.text.trim());
                            final stockQty = int.parse(stockController.text.trim());
                            final minStock = int.parse(minStockController.text.trim());

                            final bId = await _businessService.getBusinessId();

                            if (isEditing) {
                              targetProductId = existingProduct.id;
                              final updatedProduct = existingProduct.copyWith(
                                name: name,
                                sku: sku.isNotEmpty ? sku : null,
                                barcode: barcode.isNotEmpty ? barcode : null,
                                price: price,
                                cost: cost,
                                unit: selectedUnit,
                                minStockAlert: minStock,
                                stockQuantity: stockQty,
                                active: activeStatus,
                              );

                              await _productService.updateProduct(
                                updatedProduct,
                                includeStockQuantity: _isSingleBranch,
                              );
                            } else {
                              final newProduct = Product(
                                id: '',
                                businessId: bId,
                                name: name,
                                sku: sku.isNotEmpty ? sku : null,
                                barcode: barcode.isNotEmpty ? barcode : null,
                                price: price,
                                cost: cost,
                                unit: selectedUnit,
                                minStockAlert: minStock,
                                stockQuantity: _isSingleBranch ? stockQty : 0,
                                active: activeStatus,
                              );

                              final created = await _productService.createProduct(
                                newProduct,
                                includeStockQuantity: _isSingleBranch,
                              );
                              targetProductId = created.id;
                            }

                            // Update inventory record ONLY for single-branch stores where branch context is 100% unambiguous
                            if (_isSingleBranch) {
                              final singleBranchId = _branches.first['id']?.toString();
                              if (singleBranchId != null && targetProductId.isNotEmpty) {
                                try {
                                  final currentInv = await _inventoryService.getInventoryByProductId(
                                    productId: targetProductId,
                                    branchId: singleBranchId,
                                  );
                                  if (currentInv != null) {
                                    await _inventoryService.updateInventory(
                                      currentInv.copyWith(
                                        quantity: stockQty,
                                        lowStockThreshold: minStock,
                                      ),
                                    );
                                  } else {
                                    await _inventoryService.createInventory(
                                      InventoryItem(
                                        id: '',
                                        productId: targetProductId,
                                        businessId: bId,
                                        branchId: singleBranchId,
                                        quantity: stockQty,
                                        lowStockThreshold: minStock,
                                      ),
                                    );
                                  }
                                } catch (invErr) {
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Product details saved, but stock update failed: ${invErr.toString()}'),
                                        backgroundColor: Colors.amber[900],
                                      ),
                                    );
                                    _loadData();
                                    return;
                                  }
                                }
                              }
                            }

                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              final msg = _isSingleBranch
                                  ? (isEditing ? 'Product "$name" updated successfully.' : 'Product "$name" added successfully.')
                                  : 'Product "$name" saved. Stock levels must be managed per branch in multi-branch or unverified branch setups.';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(msg),
                                  backgroundColor: const Color(0xFF8DB600),
                                ),
                              );
                              _loadData();
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to save product: ${e.toString()}'),
                                  backgroundColor: Colors.red[800],
                                ),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(isEditing ? 'Save Changes' : 'Add Product'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleDeleteOrDeactivate(Product product) async {
    // Loader dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF003366)),
      ),
    );

    final checkResult = await _checkHasHistoricalReferences(product.id);
    if (mounted) Navigator.of(context).pop(); // Close loader

    if (!mounted) return;

    if (checkResult == HistoryCheckResult.checkFailed) {
      // FAIL CLOSED: Check failed -> Permanent deletion is BLOCKED!
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
              SizedBox(width: 8),
              Text('History Verification Failed'),
            ],
          ),
          content: Text(
            'Could not verify transaction history for product "${product.name}" due to a network or database error.\n\nPermanent deletion is disabled while history status is unverified. Please retry later or deactivate the product.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await _productService.deactivateProduct(product.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Product "${product.name}" deactivated.'),
                        backgroundColor: const Color(0xFF003366),
                      ),
                    );
                    _loadData();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to deactivate product: ${e.toString()}'),
                        backgroundColor: Colors.red[800],
                      ),
                    );
                  }
                }
              },
              child: const Text('Deactivate Product'),
            ),
          ],
        ),
      );
      return;
    }

    if (checkResult == HistoryCheckResult.historyExists) {
      // HISTORY EXISTS: Permanent deletion NOT offered!
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: Colors.amber, size: 24),
              SizedBox(width: 8),
              Text('Product Has Transaction History'),
            ],
          ),
          content: Text(
            'Product "${product.name}" has recorded sales, returns, or inventory audit logs.\n\nTo preserve historical store and financial audit records, permanent deletion is disabled. Deactivating hides it from cashier checkout while preserving sales history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await _productService.deactivateProduct(product.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Product "${product.name}" deactivated.'),
                        backgroundColor: const Color(0xFF003366),
                      ),
                    );
                    _loadData();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to deactivate product: ${e.toString()}'),
                        backgroundColor: Colors.red[800],
                      ),
                    );
                  }
                }
              },
              child: const Text('Deactivate Product'),
            ),
          ],
        ),
      );
    } else {
      // NO HISTORY: Permanent deletion permitted
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text('Permanently Delete Product?'),
            ],
          ),
          content: Text(
            'Product "${product.name}" has no historical transactions. Are you sure you want to permanently delete it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[800],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await _productService.deleteProduct(product.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Product "${product.name}" permanently deleted.'),
                        backgroundColor: Colors.red[800],
                      ),
                    );
                    _loadData();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to delete product: ${e.toString()}'),
                        backgroundColor: Colors.red[800],
                      ),
                    );
                  }
                }
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Filter & Search Header Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            hintText: 'Search products by Name, SKU, or Barcode...',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF003366), size: 20),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF003366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Product', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () => _openProductDialog(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Stock Status: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                    const SizedBox(width: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('All')),
                        ButtonSegment(value: 'in_stock', label: Text('In Stock')),
                        ButtonSegment(value: 'low_stock', label: Text('Low Stock')),
                        ButtonSegment(value: 'out_of_stock', label: Text('Out of Stock')),
                      ],
                      selected: {_selectedStockFilter},
                      onSelectionChanged: (set) {
                        setState(() => _selectedStockFilter = set.first);
                      },
                    ),
                    const Spacer(),
                    Text(
                      '${filtered.length} products listed',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Products List / Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF003366)))
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 44, color: Colors.red),
                            const SizedBox(height: 12),
                            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _loadData,
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF003366), foregroundColor: Colors.white),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF003366).withValues(alpha: 0.05),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.inventory_2_outlined, size: 44, color: Color(0xFF003366)),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'No Store Products Found',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'No products match your search query or filter.',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            color: const Color(0xFF003366),
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
                                    ? Colors.red.shade800
                                    : isLow
                                        ? Colors.amber.shade900
                                        : const Color(0xFF003366);

                                final statusBg = isOut
                                    ? Colors.red.shade50
                                    : isLow
                                        ? Colors.amber.shade50
                                        : const Color(0xFF8DB600).withValues(alpha: 0.15);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          // Product Details
                                          SizedBox(
                                            width: 260,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        product.name,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 15,
                                                          color: Color(0xFF0F172A),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (!product.active) ...[
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.grey.shade200,
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: const Text('Inactive', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    if (product.sku != null && product.sku!.isNotEmpty)
                                                      Text('SKU: ${product.sku}   ', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                                    if (product.barcode != null && product.barcode!.isNotEmpty)
                                                      Text('Barcode: ${product.barcode}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),

                                          // Status Badge
                                          SizedBox(
                                            width: 130,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: statusBg,
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                                ),
                                                child: Text(
                                                  statusLabel,
                                                  style: TextStyle(
                                                    color: statusColor,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),

                                          // Stock Quantity & Threshold
                                          SizedBox(
                                            width: 140,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Stock Level', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$qty ${product.unit}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: statusColor,
                                                  ),
                                                ),
                                                Text('Min: ${product.minStockAlert} ${product.unit}', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),

                                          // Pricing: Selling Price & Cost Price
                                          SizedBox(
                                            width: 140,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Selling Price', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  CurrencyFormatter.format(product.price),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: Color(0xFF003366),
                                                  ),
                                                ),
                                                Text('Cost: ${CurrencyFormatter.format(product.cost)}', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),

                                          // Action Buttons
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined, color: Color(0xFF003366), size: 20),
                                                tooltip: 'Edit Product',
                                                onPressed: () => _openProductDialog(product),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                                tooltip: 'Delete Product',
                                                onPressed: () => _handleDeleteOrDeactivate(product),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
