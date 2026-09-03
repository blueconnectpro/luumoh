class StoreMember {
  const StoreMember({
    required this.storeId,
    required this.userId,
    required this.canManageInventory,
    required this.canManageOrders,
    required this.createdAt,
  });

  factory StoreMember.fromMap(Map<String, dynamic> map) {
    return StoreMember(
      storeId: map['store_id'] as String,
      userId: map['user_id'] as String,
      canManageInventory: _boolValue(map['can_manage_inventory']),
      canManageOrders: _boolValue(map['can_manage_orders']),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String storeId;
  final String userId;
  final bool canManageInventory;
  final bool canManageOrders;
  final DateTime createdAt;
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
