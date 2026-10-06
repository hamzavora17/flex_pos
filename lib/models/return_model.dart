/// Representation of a return item and the resulting refund decision.
class ReturnItemSelection {
  final String productId;
  final String productName;
  final String? sku;
  final int selectedQuantity;
  final int maxQuantity; // Represents remaining returnable quantity
  final double unitPrice;

  ReturnItemSelection({
    required this.productId,
    required this.productName,
    this.sku,
    required this.selectedQuantity,
    required this.maxQuantity,
    required this.unitPrice,
  });

  double get lineRefund => unitPrice * selectedQuantity;

  ReturnItemSelection copyWith({int? selectedQuantity, int? maxQuantity}) {
    return ReturnItemSelection(
      productId: productId,
      productName: productName,
      sku: sku,
      selectedQuantity: selectedQuantity ?? this.selectedQuantity,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      unitPrice: unitPrice,
    );
  }
}

class ReturnResultModel {
  final String returnId;
  final double refundAmount;
  final bool isApproved;
  final String message;

  ReturnResultModel({
    required this.returnId,
    required this.refundAmount,
    required this.isApproved,
    required this.message,
  });
}

class ReturnReceiptModel {
  final String returnId;
  final String originalInvoiceNumber;
  final DateTime returnDate;
  final List<ReturnItemSelection> returnedItems;
  final double refundAmount;
  final String paymentMethod;
  final String status;

  ReturnReceiptModel({
    required this.returnId,
    required this.originalInvoiceNumber,
    required this.returnDate,
    required this.returnedItems,
    required this.refundAmount,
    required this.paymentMethod,
    required this.status,
  });
}
