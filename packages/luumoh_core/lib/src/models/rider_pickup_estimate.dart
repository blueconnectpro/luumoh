class RiderPickupEstimate {
  const RiderPickupEstimate({
    required this.distanceKm,
    required this.etaMinutes,
    this.riderId,
  });

  factory RiderPickupEstimate.fromMap(Map<String, dynamic> map) {
    return RiderPickupEstimate(
      distanceKm: (map['distance_km'] as num? ?? 0).toDouble(),
      etaMinutes: (map['eta_minutes'] as num? ?? 0).toInt(),
      riderId: map['rider_id'] as String?,
    );
  }

  final double distanceKm;
  final int etaMinutes;
  final String? riderId;
}
