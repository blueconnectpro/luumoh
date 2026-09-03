class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.productId,
    required this.storeId,
    required this.quantityDelta,
    required this.reason,
    required this.createdAt,
    this.note,
    this.createdBy,
  });

  factory InventoryMovement.fromMap(Map<String, dynamic> map) {
    return InventoryMovement(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      storeId: map['store_id'] as String,
      quantityDelta: (map['quantity_delta'] as num? ?? 0).toInt(),
      reason: map['reason'] as String? ?? 'correction',
      note: map['note'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String productId;
  final String storeId;
  final int quantityDelta;
  final String reason;
  final String? note;
  final String? createdBy;
  final DateTime createdAt;
}
