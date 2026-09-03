class DeliveryEvent {
  const DeliveryEvent({
    required this.id,
    required this.orderId,
    required this.status,
    required this.createdAt,
    this.riderId,
    this.etaMinutes,
    this.note,
  });

  factory DeliveryEvent.fromMap(Map<String, dynamic> map) {
    return DeliveryEvent(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      status: map['status'] as String? ?? 'updated',
      riderId: map['rider_id'] as String?,
      etaMinutes: (map['eta_minutes'] as num?)?.toInt(),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String orderId;
  final String status;
  final String? riderId;
  final int? etaMinutes;
  final String? note;
  final DateTime createdAt;
}
