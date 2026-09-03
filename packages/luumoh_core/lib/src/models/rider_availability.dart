class RiderAvailability {
  const RiderAvailability({
    required this.riderId,
    required this.isOnline,
    required this.lastSeenAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RiderAvailability.fromMap(Map<String, dynamic> map) {
    return RiderAvailability(
      riderId: map['rider_id'] as String,
      isOnline: _boolValue(map['is_online']),
      lastSeenAt: DateTime.parse(map['last_seen_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final String riderId;
  final bool isOnline;
  final DateTime lastSeenAt;
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
