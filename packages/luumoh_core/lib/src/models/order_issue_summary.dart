class OrderIssueSummary {
  const OrderIssueSummary({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.storeId,
    required this.storeName,
    required this.orderStatus,
    required this.paymentStatus,
    required this.totalAmount,
    required this.category,
    required this.message,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.customerName,
    this.customerPhone,
    this.adminNote,
  });

  factory OrderIssueSummary.fromMap(Map<String, dynamic> map) {
    return OrderIssueSummary(
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
      category: map['category'] as String? ?? 'other',
      message: map['message'] as String? ?? '',
      status: map['status'] as String? ?? 'open',
      adminNote: map['admin_note'] as String?,
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
  final String category;
  final String message;
  final String status;
  final String? adminNote;
  final DateTime createdAt;
  final DateTime updatedAt;
}
