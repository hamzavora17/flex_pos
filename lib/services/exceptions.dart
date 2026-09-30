/// Base exception class for FlexPOS application errors.
class FlexPOSException implements Exception {
  final String message;
  final dynamic originalError;

  const FlexPOSException(this.message, [this.originalError]);

  @override
  String toString() => message;
}

/// Thrown when a business ID cannot be resolved for the authenticated user.
class BusinessNotFoundException extends FlexPOSException {
  const BusinessNotFoundException([
    super.message = 'Unable to resolve store business for current user.',
    super.originalError,
  ]);
}

/// Thrown when category management operations fail.
class CategoryException extends FlexPOSException {
  const CategoryException(super.message, [super.originalError]);
}

/// Thrown when product management operations fail.
class ProductException extends FlexPOSException {
  const ProductException(super.message, [super.originalError]);
}

/// Thrown when inventory management operations fail.
class InventoryException extends FlexPOSException {
  const InventoryException(super.message, [super.originalError]);
}

/// Thrown when a sale or checkout operation fails.
class SaleException extends FlexPOSException {
  const SaleException(super.message, [super.originalError]);
}
