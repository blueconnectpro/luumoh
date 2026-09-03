class StoreStaffPresence {
  const StoreStaffPresence({
    required this.storeId,
    required this.storeName,
    required this.userId,
    required this.staffName,
    required this.isActive,
    required this.canManageInventory,
    required this.canManageOrders,
    required this.lastSeenAt,
    required this.updatedAt,
    this.staffEmail,
    this.staffPhone,
    this.staffRole,
    this.lastLoginAt,
  });

  factory StoreStaffPresence.fromMap(Map<String, dynamic> map) {
    return StoreStaffPresence(
      storeId: map['store_id'] as String,
      storeName: map['store_name'] as String? ?? 'Store',
      userId: map['user_id'] as String,
      staffName: map['staff_name'] as String? ?? 'Store staff',
      staffEmail: map['staff_email'] as String?,
      staffPhone: map['staff_phone'] as String?,
      staffRole: map['staff_role'] as String?,
      canManageInventory: _boolValue(map['can_manage_inventory']),
      canManageOrders: _boolValue(map['can_manage_orders']),
      isActive: _boolValue(map['is_active']),
      lastLoginAt: _parseDateTime(map['last_login_at']),
      lastSeenAt: _parseDateTime(map['last_seen_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now(),
    );
  }

  final String storeId;
  final String storeName;
  final String userId;
  final String staffName;
  final String? staffEmail;
  final String? staffPhone;
  final String? staffRole;
  final bool canManageInventory;
  final bool canManageOrders;
  final bool isActive;
  final DateTime? lastLoginAt;
  final DateTime lastSeenAt;
  final DateTime updatedAt;
}

DateTime? _parseDateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

bool _boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return fallback;
}
