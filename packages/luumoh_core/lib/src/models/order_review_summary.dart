class OrderReviewSummary {
  const OrderReviewSummary({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.storeId,
    required this.storeName,
    required this.orderStatus,
    required this.paymentStatus,
    required this.totalAmount,
    required this.rating,
    required this.createdAt,
    required this.updatedAt,
    this.customerName,
    this.customerPhone,
    this.comment,
  });

  factory OrderReviewSummary.fromMap(Map<String, dynamic> map) {
    return OrderReviewSummary(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      customerId: map['customer_id'] as String,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      storeId: map['store_id'] as String,
      storeName: map['store_name'] as String? ?? 'Store',
      orderStatus: map['order_status'] as String? ?? 'unknown',
      paymentStatus: map['payment_status'] as String? ?? 'unknown',
      totalAmount: (map['total_amount'] as num? ?? 0).toDouble(),
      rating: (map['rating'] as num? ?? 0).toInt(),
      comment: map['comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final String id;
  final String orderId;
  final String customerId;
  final String? customerName;
  final String? customerPhone;
  final String storeId;
  final String storeName;
  final String orderStatus;
  final String paymentStatus;
  final double totalAmount;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final DateTime updatedAt;
}
