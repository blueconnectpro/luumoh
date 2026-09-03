class OrderLineItem {
  const OrderLineItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory OrderLineItem.fromMap(Map<String, dynamic> map) {
    return OrderLineItem(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      productId: map['product_id'] as String,
      productName: map['product_name'] as String? ?? 'Product',
      quantity: (map['quantity'] as num? ?? 0).toInt(),
      unitPrice: (map['unit_price'] as num? ?? 0).toDouble(),
      lineTotal: (map['line_total'] as num? ?? 0).toDouble(),
    );
  }

  final String id;
  final String orderId;
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
}
