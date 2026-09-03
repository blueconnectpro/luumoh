class StoreInventoryItem {
  const StoreInventoryItem({
    required this.productId,
    required this.storeId,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.storeMarkedAvailable,
    required this.quantityOnHand,
    required this.quantityReserved,
    required this.quantityAvailable,
    required this.reorderLevel,
    this.sku,
    this.imageUrl,
    this.imageUrls = const [],
    this.unavailableUntil,
  });

  factory StoreInventoryItem.fromMap(Map<String, dynamic> map) {
    final imageUrls = _stringList(map['image_urls']);
    final primaryImageUrl = map['image_url'] as String?;
    return StoreInventoryItem(
      productId: map['product_id'] as String,
      storeId: map['store_id'] as String,
      name: map['name'] as String? ?? 'Product',
      description: map['description'] as String? ?? '',
      price: (map['price'] as num? ?? 0).toDouble(),
      category: map['category'] as String? ?? 'general',
      storeMarkedAvailable: _boolValue(map['store_marked_available']),
      quantityOnHand: (map['quantity_on_hand'] as num? ?? 0).toInt(),
      quantityReserved: (map['quantity_reserved'] as num? ?? 0).toInt(),
      quantityAvailable: (map['quantity_available'] as num? ?? 0).toInt(),
      reorderLevel: (map['reorder_level'] as num? ?? 0).toInt(),
      sku: map['sku'] as String?,
      imageUrl: primaryImageUrl,
      imageUrls: imageUrls.isEmpty
          ? [
              if (primaryImageUrl != null && primaryImageUrl.trim().isNotEmpty)
                primaryImageUrl,
            ]
          : imageUrls,
      unavailableUntil: _parseDateTime(map['unavailable_until']),
    );
  }

  final String productId;
  final String storeId;
  final String name;
  final String description;
  final double price;
  final String category;
  final bool storeMarkedAvailable;
  final int quantityOnHand;
  final int quantityReserved;
  final int quantityAvailable;
  final int reorderLevel;
  final String? sku;
  final String? imageUrl;
  final List<String> imageUrls;
  final DateTime? unavailableUntil;
}

bool _boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return fallback;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

DateTime? _parseDateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
