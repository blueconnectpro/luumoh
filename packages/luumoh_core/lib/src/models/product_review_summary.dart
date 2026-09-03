class ProductReviewSummary {
  const ProductReviewSummary({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.storeId,
    required this.storeName,
    required this.productId,
    required this.productName,
    required this.rating,
    required this.createdAt,
    required this.updatedAt,
    this.customerName,
    this.customerPhone,
    this.comment,
  });

  factory ProductReviewSummary.fromMap(Map<String, dynamic> map) {
    return ProductReviewSummary(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      customerId: map['customer_id'] as String,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      storeId: map['store_id'] as String,
      storeName: map['store_name'] as String? ?? 'Store',
      productId: map['product_id'] as String,
      productName: map['product_name'] as String? ?? 'Item',
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
  final String productId;
  final String productName;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final DateTime updatedAt;
}
