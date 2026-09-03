class RiderLocationUpdate {
  const RiderLocationUpdate({
    required this.id,
    required this.orderId,
    required this.riderId,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.riderName,
    this.accuracyMeters,
    this.heading,
    this.speedMps,
    this.note,
    this.storeId,
    this.storeName,
    this.storeLatitude,
    this.storeLongitude,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.deliveryDistanceKm = 0,
    this.orderStatus,
    this.paymentStatus,
  });

  factory RiderLocationUpdate.fromMap(Map<String, dynamic> map) {
    return RiderLocationUpdate(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      riderId: map['rider_id'] as String,
      riderName: map['rider_name'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracyMeters: (map['accuracy_meters'] as num?)?.toDouble(),
      heading: (map['heading'] as num?)?.toDouble(),
      speedMps: (map['speed_mps'] as num?)?.toDouble(),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      storeId: map['store_id'] as String?,
      storeName: map['store_name'] as String?,
      storeLatitude: (map['store_latitude'] as num?)?.toDouble(),
      storeLongitude: (map['store_longitude'] as num?)?.toDouble(),
      deliveryLatitude: (map['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (map['delivery_longitude'] as num?)?.toDouble(),
      deliveryDistanceKm: (map['delivery_distance_km'] as num? ?? 0).toDouble(),
      orderStatus: map['order_status'] as String?,
      paymentStatus: map['payment_status'] as String?,
    );
  }

  final String id;
  final String orderId;
  final String riderId;
  final String? riderName;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? heading;
  final double? speedMps;
  final String? note;
  final DateTime createdAt;
  final String? storeId;
  final String? storeName;
  final double? storeLatitude;
  final double? storeLongitude;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final double deliveryDistanceKm;
  final String? orderStatus;
  final String? paymentStatus;
}
