class OrderMessageSummary {
  const OrderMessageSummary({
    required this.id,
    required this.orderId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.message,
    required this.createdAt,
    required this.customerId,
    required this.storeId,
    required this.storeName,
    this.riderId,
  });

  factory OrderMessageSummary.fromMap(Map<String, dynamic> map) {
    return OrderMessageSummary(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String? ?? 'Luumoh user',
      senderRole: map['sender_role'] as String? ?? 'customer',
      message: map['message'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      customerId: map['customer_id'] as String,
      storeId: map['store_id'] as String,
      storeName: map['store_name'] as String? ?? 'Store',
      riderId: map['rider_id'] as String?,
    );
  }

  final String id;
  final String orderId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String message;
  final DateTime createdAt;
  final String customerId;
  final String storeId;
  final String storeName;
  final String? riderId;
}
