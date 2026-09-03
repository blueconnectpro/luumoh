class StoreOpeningHour {
  const StoreOpeningHour({
    required this.id,
    required this.storeId,
    required this.dayOfWeek,
    required this.isClosed,
    required this.updatedAt,
    this.opensAt,
    this.closesAt,
  });

  factory StoreOpeningHour.fromMap(Map<String, dynamic> map) {
    return StoreOpeningHour(
      id: map['id'] as String,
      storeId: map['store_id'] as String,
      dayOfWeek: (map['day_of_week'] as num? ?? 0).toInt(),
      opensAt: map['opens_at'] as String?,
      closesAt: map['closes_at'] as String?,
      isClosed: _boolValue(map['is_closed']),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String storeId;
  final int dayOfWeek;
  final String? opensAt;
  final String? closesAt;
  final bool isClosed;
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
