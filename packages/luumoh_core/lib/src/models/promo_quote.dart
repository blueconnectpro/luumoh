class PromoQuote {
  const PromoQuote({
    required this.isValid,
    required this.message,
    required this.discountAmount,
    this.promoCodeId,
    this.code,
    this.discountType,
    this.discountValue,
  });

  factory PromoQuote.fromMap(Map<String, dynamic> map) {
    return PromoQuote(
      isValid: _boolValue(map['is_valid']),
      message: map['message'] as String? ?? '',
      promoCodeId: map['promo_code_id'] as String?,
      code: map['code'] as String?,
      discountAmount: (map['discount_amount'] as num? ?? 0).toDouble(),
      discountType: map['discount_type'] as String?,
      discountValue: (map['discount_value'] as num?)?.toDouble(),
    );
  }

  final bool isValid;
  final String message;
  final String? promoCodeId;
  final String? code;
  final double discountAmount;
  final String? discountType;
  final double? discountValue;
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
