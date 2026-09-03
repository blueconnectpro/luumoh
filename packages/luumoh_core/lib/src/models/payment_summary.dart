class PaymentSummary {
  const PaymentSummary({
    required this.id,
    required this.orderId,
    required this.storeId,
    required this.storeName,
    required this.customerId,
    required this.provider,
    required this.paymentReference,
    required this.amount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.itemsSubtotal = 0,
    this.discountAmount = 0,
    this.deliveryFee = 0,
    this.serviceFee = 0,
    this.storePayoutAmount = 0,
    this.riderPayoutAmount = 0,
    this.platformFeeAmount = 0,
    this.providerTransactionReference,
    this.checkoutUrl,
  });

  factory PaymentSummary.fromMap(Map<String, dynamic> map) {
    return PaymentSummary(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      storeId: map['store_id'] as String,
      storeName: map['store_name'] as String? ?? 'Store',
      customerId: map['customer_id'] as String,
      provider: map['provider'] as String? ?? 'monnify',
      paymentReference: map['payment_reference'] as String,
      providerTransactionReference:
          map['provider_transaction_reference'] as String?,
      amount: (map['amount'] as num? ?? 0).toDouble(),
      status: map['status'] as String? ?? 'pending',
      checkoutUrl: map['checkout_url'] as String?,
      itemsSubtotal: (map['items_subtotal'] as num? ?? 0).toDouble(),
      discountAmount: (map['discount_amount'] as num? ?? 0).toDouble(),
      deliveryFee: (map['delivery_fee'] as num? ?? 0).toDouble(),
      serviceFee: (map['service_fee'] as num? ?? 0).toDouble(),
      storePayoutAmount: (map['store_payout_amount'] as num? ?? 0).toDouble(),
      riderPayoutAmount: (map['rider_payout_amount'] as num? ?? 0).toDouble(),
      platformFeeAmount: (map['platform_fee_amount'] as num? ?? 0).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final String id;
  final String orderId;
  final String storeId;
  final String storeName;
  final String customerId;
  final String provider;
  final String paymentReference;
  final String? providerTransactionReference;
  final double amount;
  final String status;
  final String? checkoutUrl;
  final double itemsSubtotal;
  final double discountAmount;
  final double deliveryFee;
  final double serviceFee;
  final double storePayoutAmount;
  final double riderPayoutAmount;
  final double platformFeeAmount;
  final DateTime createdAt;
  final DateTime updatedAt;
}
