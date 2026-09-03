class StoreSummary {
  const StoreSummary({
    required this.id,
    required this.name,
    required this.category,
    required this.isOpen,
    this.address = '',
    this.isActive = true,
    this.busyUntil,
    this.closedUntil,
    this.latitude,
    this.longitude,
  });

  factory StoreSummary.fromMap(Map<String, dynamic> map) {
    return StoreSummary(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Store',
      category: map['category'] as String? ?? 'general',
      isOpen: _boolValue(map['is_open']),
      address: map['address'] as String? ?? '',
      isActive: _boolValue(map['is_active'], fallback: true),
      busyUntil: _parseDateTime(map['busy_until']),
      closedUntil: _parseDateTime(map['closed_until']),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String name;
  final String category;
  final bool isOpen;
  final String address;
  final bool isActive;
  final DateTime? busyUntil;
  final DateTime? closedUntil;
  final double? latitude;
  final double? longitude;
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

DateTime? _parseDateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
