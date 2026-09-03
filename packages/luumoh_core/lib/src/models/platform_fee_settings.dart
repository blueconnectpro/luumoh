class PlatformFeeSettings {
  const PlatformFeeSettings({
    required this.deliveryFee,
    required this.serviceFeePercent,
    required this.serviceFeeFixed,
    required this.riderDeliveryPayout,
    required this.deliveryBaseKm,
    required this.deliveryFeePerKm,
    required this.minimumDeliveryFee,
    required this.isActive,
    required this.updatedAt,
  });

  factory PlatformFeeSettings.fromMap(Map<String, dynamic> map) {
    return PlatformFeeSettings(
      deliveryFee: (map['delivery_fee'] as num? ?? 0).toDouble(),
      serviceFeePercent: (map['service_fee_percent'] as num? ?? 0).toDouble(),
      serviceFeeFixed: (map['service_fee_fixed'] as num? ?? 0).toDouble(),
      riderDeliveryPayout:
          (map['rider_delivery_payout'] as num? ?? 0).toDouble(),
      deliveryBaseKm: (map['delivery_base_km'] as num? ?? 3).toDouble(),
      deliveryFeePerKm: (map['delivery_fee_per_km'] as num? ?? 0).toDouble(),
      minimumDeliveryFee: (map['minimum_delivery_fee'] as num? ?? 0).toDouble(),
      isActive: _boolValue(map['is_active'], fallback: true),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final double deliveryFee;
  final double serviceFeePercent;
  final double serviceFeeFixed;
  final double riderDeliveryPayout;
  final double deliveryBaseKm;
  final double deliveryFeePerKm;
  final double minimumDeliveryFee;
  final bool isActive;
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
