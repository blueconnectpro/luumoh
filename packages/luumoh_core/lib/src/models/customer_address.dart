class CustomerAddress {
  const CustomerAddress({
    required this.id,
    required this.customerId,
    required this.label,
    required this.address,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
    this.latitude,
    this.longitude,
  });

  factory CustomerAddress.fromMap(Map<String, dynamic> map) {
    return CustomerAddress(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      label: map['label'] as String? ?? 'Home',
      address: map['address'] as String? ?? '',
      isDefault: _boolValue(map['is_default']),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final String id;
  final String customerId;
  final String label;
  final String address;
  final bool isDefault;
  final double? latitude;
  final double? longitude;
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
