class CatalogItem {
  const CatalogItem({
    required this.productId,
    required this.storeId,
    required this.storeName,
    required this.storeCategory,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.quantityAvailable,
    required this.reorderLevel,
    required this.isAvailable,
    this.imageUrl,
    this.imageUrls = const [],
    this.storeLatitude,
    this.storeLongitude,
  });

  factory CatalogItem.fromMap(Map<String, dynamic> map) {
    final imageUrls = _stringList(map['image_urls']);
    final primaryImageUrl = map['image_url'] as String?;
    return CatalogItem(
      productId: map['product_id'] as String,
      storeId: map['store_id'] as String,
      storeName: map['store_name'] as String? ?? 'Store',
      storeCategory: map['store_category'] as String? ?? 'general',
      name: map['name'] as String? ?? 'Product',
      description: map['description'] as String? ?? '',
      price: (map['price'] as num? ?? 0).toDouble(),
      category: map['category'] as String? ?? 'general',
      quantityAvailable: (map['quantity_available'] as num? ?? 0).toInt(),
      reorderLevel: (map['reorder_level'] as num? ?? 5).toInt(),
      isAvailable: _boolValue(map['is_available']),
      imageUrl: primaryImageUrl,
      imageUrls: imageUrls.isEmpty
          ? [
              if (primaryImageUrl != null && primaryImageUrl.trim().isNotEmpty)
                primaryImageUrl,
            ]
          : imageUrls,
      storeLatitude: (map['store_latitude'] as num?)?.toDouble(),
      storeLongitude: (map['store_longitude'] as num?)?.toDouble(),
    );
  }

  final String productId;
  final String storeId;
  final String storeName;
  final String storeCategory;
  final String name;
  final String description;
  final double price;
  final String category;
  final int quantityAvailable;
  final int reorderLevel;
  final bool isAvailable;
  final String? imageUrl;
  final List<String> imageUrls;
  final double? storeLatitude;
  final double? storeLongitude;
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
