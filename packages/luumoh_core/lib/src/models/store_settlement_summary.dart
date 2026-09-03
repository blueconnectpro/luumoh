class StoreSettlementSummary {
  const StoreSettlementSummary({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.orderId,
    required this.customerId,
    required this.orderStatus,
    required this.paymentStatus,
    required this.grossItemsAmount,
    required this.discountAmount,
    required this.netItemsAmount,
    required this.serviceFeeAmount,
    required this.payoutAmount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.paidAt,
  });

  factory StoreSettlementSummary.fromMap(Map<String, dynamic> map) {
    return StoreSettlementSummary(
      id: map['id'] as String,
      storeId: map['store_id'] as String,
      storeName: map['store_name'] as String? ?? 'Store',
      orderId: map['order_id'] as String,
      customerId: map['customer_id'] as String,
      orderStatus: map['order_status'] as String? ?? 'paid',
      paymentStatus: map['payment_status'] as String? ?? 'paid',
      grossItemsAmount: (map['gross_items_amount'] as num? ?? 0).toDouble(),
      discountAmount: (map['discount_amount'] as num? ?? 0).toDouble(),
      netItemsAmount: (map['net_items_amount'] as num? ?? 0).toDouble(),
      serviceFeeAmount: (map['service_fee_amount'] as num? ?? 0).toDouble(),
      payoutAmount: (map['payout_amount'] as num? ?? 0).toDouble(),
      status: map['status'] as String? ?? 'pending',
      paidAt: _parseDateTime(map['paid_at']),
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String storeId;
  final String storeName;
  final String orderId;
  final String customerId;
  final String orderStatus;
  final String paymentStatus;
  final double grossItemsAmount;
  final double discountAmount;
  final double netItemsAmount;
  final double serviceFeeAmount;
  final double payoutAmount;
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
