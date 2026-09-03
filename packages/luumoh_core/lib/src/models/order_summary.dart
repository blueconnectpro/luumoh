class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.customerId,
    required this.storeId,
    required this.storeName,
    required this.storeAddress,
    required this.status,
    required this.paymentStatus,
    required this.totalAmount,
    required this.deliveryAddress,
    required this.createdAt,
    required this.updatedAt,
    this.fulfillmentType = 'delivery',
    this.itemsSubtotal = 0,
    this.discountAmount = 0,
    this.deliveryFee = 0,
    this.serviceFee = 0,
    this.storePayoutAmount = 0,
    this.riderPayoutAmount = 0,
    this.platformFeeAmount = 0,
    this.deliveryDistanceKm = 0,
    this.storeLatitude,
    this.storeLongitude,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.customerName,
    this.customerPhone,
    this.riderId,
    this.riderName,
    this.riderPhone,
    this.etaMinutes,
    this.etaUpdatedAt,
    this.preparationMinutes,
    this.cancellationReason,
  });

  factory OrderSummary.fromMap(Map<String, dynamic> map) {
    return OrderSummary(
      id: map['id'] as String,
      customerId: map['customer_id'] as String? ?? '',
      storeId: map['store_id'] as String,
      storeName: map['store_name'] as String? ?? 'Store',
      storeAddress: map['store_address'] as String? ?? '',
      status: map['status'] as String? ?? 'draft',
      paymentStatus: map['payment_status'] as String? ?? 'pending',
      fulfillmentType: map['fulfillment_type'] as String? ?? 'delivery',
      totalAmount: (map['total_amount'] as num? ?? 0).toDouble(),
      itemsSubtotal: (map['items_subtotal'] as num? ?? 0).toDouble(),
      discountAmount: (map['discount_amount'] as num? ?? 0).toDouble(),
      deliveryFee: (map['delivery_fee'] as num? ?? 0).toDouble(),
      serviceFee: (map['service_fee'] as num? ?? 0).toDouble(),
      storePayoutAmount: (map['store_payout_amount'] as num? ?? 0).toDouble(),
      riderPayoutAmount: (map['rider_payout_amount'] as num? ?? 0).toDouble(),
      platformFeeAmount: (map['platform_fee_amount'] as num? ?? 0).toDouble(),
      deliveryDistanceKm: (map['delivery_distance_km'] as num? ?? 0).toDouble(),
      storeLatitude: (map['store_latitude'] as num?)?.toDouble(),
      storeLongitude: (map['store_longitude'] as num?)?.toDouble(),
      deliveryLatitude: (map['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (map['delivery_longitude'] as num?)?.toDouble(),
      deliveryAddress: map['delivery_address'] as String? ?? '',
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      riderId: map['rider_id'] as String?,
      riderName: map['rider_name'] as String?,
      riderPhone: map['rider_phone'] as String?,
      etaMinutes: (map['eta_minutes'] as num?)?.toInt(),
      etaUpdatedAt: _parseDateTime(map['eta_updated_at']),
      preparationMinutes: (map['preparation_minutes'] as num?)?.toInt(),
      cancellationReason: map['cancellation_reason'] as String?,
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String customerId;
  final String storeId;
  final String storeName;
  final String storeAddress;
  final String status;
  final String paymentStatus;
  final String fulfillmentType;
  final double totalAmount;
  final double itemsSubtotal;
  final double discountAmount;
  final double deliveryFee;
  final double serviceFee;
  final double storePayoutAmount;
  final double riderPayoutAmount;
  final double platformFeeAmount;
  final double deliveryDistanceKm;
  final double? storeLatitude;
  final double? storeLongitude;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String deliveryAddress;
  final String? customerName;
  final String? customerPhone;
  final String? riderId;
  final String? riderName;
  final String? riderPhone;
  final int? etaMinutes;
  final DateTime? etaUpdatedAt;
  final int? preparationMinutes;
  final String? cancellationReason;
  final DateTime createdAt;
  final DateTime updatedAt;
}

DateTime? _parseDateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
