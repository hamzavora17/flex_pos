/// Strongly-typed user roles supported in FlexPOS.
enum UserRole {
  admin,
  manager,
  cashier;

  /// Parses a raw database role string into a nullable [UserRole].
  ///
  /// Returns null if the role string is null, empty, or unresolvable.
  /// Preserves backwards compatibility by mapping legacy `'employee'` to [UserRole.cashier].
  static UserRole? tryFromString(String? role) {
    if (role == null || role.trim().isEmpty) {
      return null;
    }
    final normalized = role.trim().toLowerCase();
    switch (normalized) {
      case 'admin':
        return UserRole.admin;
      case 'manager':
        return UserRole.manager;
      case 'cashier':
      case 'employee':
        return UserRole.cashier;
      default:
        return null;
    }
  }

  /// Parses a raw database role string into a nullable [UserRole].
  ///
  /// Strictly avoids fallback to [UserRole.cashier] when role is unresolved.
  static UserRole? fromString(String? role) {
    return tryFromString(role);
  }

  /// Converts [UserRole] to database string format.
  String toDbString() {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.manager:
        return 'manager';
      case UserRole.cashier:
        return 'cashier';
    }
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.manager:
        return 'Manager';
      case UserRole.cashier:
        return 'Cashier';
    }
  }

  bool get isAdmin => this == UserRole.admin;
  bool get isManager => this == UserRole.manager;
  bool get isCashier => this == UserRole.cashier;

  /// Whether this role has authority to modify user roles.
  /// Strictly restricted to [UserRole.admin].
  bool get canManageRoles => this == UserRole.admin;

  /// Validates whether a user with current role can assign or promote a user to [targetRole].
  ///
  /// Neither cashiers nor managers can self-promote or promote other users.
  bool canPromoteTo(UserRole targetRole) {
    if (this != UserRole.admin) {
      return false;
    }
    return true;
  }
}
