class PromoCodeSummary {
  const PromoCodeSummary({
    required this.id,
    required this.code,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    required this.redemptionCount,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.storeId,
    this.storeName,
    this.startsAt,
    this.endsAt,
    this.maxRedemptions,
  });

  factory PromoCodeSummary.fromMap(Map<String, dynamic> map) {
    return PromoCodeSummary(
      id: map['id'] as String,
      storeId: map['store_id'] as String?,
      storeName: map['store_name'] as String?,
      code: map['code'] as String? ?? '',
      description: map['description'] as String? ?? '',
      discountType: map['discount_type'] as String? ?? 'fixed',
      discountValue: (map['discount_value'] as num? ?? 0).toDouble(),
      minOrderAmount: (map['min_order_amount'] as num? ?? 0).toDouble(),
      startsAt: map['starts_at'] == null
          ? null
          : DateTime.parse(map['starts_at'] as String),
      endsAt: map['ends_at'] == null
          ? null
          : DateTime.parse(map['ends_at'] as String),
      maxRedemptions: (map['max_redemptions'] as num?)?.toInt(),
      redemptionCount: (map['redemption_count'] as num? ?? 0).toInt(),
      isActive: _boolValue(map['is_active']),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final String id;
  final String? storeId;
  final String? storeName;
  final String code;
  final String description;
  final String discountType;
  final double discountValue;
  final double minOrderAmount;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? maxRedemptions;
  final int redemptionCount;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
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
