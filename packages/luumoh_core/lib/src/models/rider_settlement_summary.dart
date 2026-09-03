class RiderSettlementSummary {
  const RiderSettlementSummary({
    required this.id,
    required this.riderId,
    required this.storeId,
    required this.storeName,
    required this.orderId,
    required this.orderStatus,
    required this.paymentStatus,
    required this.deliveryFeeAmount,
    required this.riderPayoutAmount,
    required this.platformDeliveryMargin,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.riderName,
    this.paidAt,
  });

  factory RiderSettlementSummary.fromMap(Map<String, dynamic> map) {
    return RiderSettlementSummary(
      id: map['id'] as String,
      riderId: map['rider_id'] as String,
      riderName: map['rider_name'] as String?,
      storeId: map['store_id'] as String,
      storeName: map['store_name'] as String? ?? 'Store',
      orderId: map['order_id'] as String,
      orderStatus: map['order_status'] as String? ?? 'delivered',
      paymentStatus: map['payment_status'] as String? ?? 'paid',
      deliveryFeeAmount: (map['delivery_fee_amount'] as num? ?? 0).toDouble(),
      riderPayoutAmount: (map['rider_payout_amount'] as num? ?? 0).toDouble(),
      platformDeliveryMargin:
          (map['platform_delivery_margin'] as num? ?? 0).toDouble(),
      status: map['status'] as String? ?? 'pending',
      paidAt: _parseDateTime(map['paid_at']),
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String riderId;
  final String? riderName;
  final String storeId;
  final String storeName;
  final String orderId;
  final String orderStatus;
  final String paymentStatus;
  final double deliveryFeeAmount;
  final double riderPayoutAmount;
  final double platformDeliveryMargin;
  final String status;
  final DateTime? paidAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

DateTime? _parseDateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
