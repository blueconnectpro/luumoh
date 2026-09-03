class CheckoutQuote {
  const CheckoutQuote({
    required this.itemsSubtotal,
    required this.discountAmount,
    required this.deliveryFee,
    required this.serviceFee,
    required this.totalAmount,
    required this.storePayoutAmount,
    required this.riderPayoutAmount,
    required this.platformFeeAmount,
    required this.promoIsValid,
    required this.promoMessage,
    this.promoCode,
  });

  factory CheckoutQuote.fromMap(Map<String, dynamic> map) {
    return CheckoutQuote(
      itemsSubtotal: (map['items_subtotal'] as num? ?? 0).toDouble(),
      discountAmount: (map['discount_amount'] as num? ?? 0).toDouble(),
      deliveryFee: (map['delivery_fee'] as num? ?? 0).toDouble(),
      serviceFee: (map['service_fee'] as num? ?? 0).toDouble(),
      totalAmount: (map['total_amount'] as num? ?? 0).toDouble(),
      storePayoutAmount: (map['store_payout_amount'] as num? ?? 0).toDouble(),
      riderPayoutAmount: (map['rider_payout_amount'] as num? ?? 0).toDouble(),
      platformFeeAmount: (map['platform_fee_amount'] as num? ?? 0).toDouble(),
      promoCode: map['promo_code'] as String?,
      promoIsValid: _boolValue(map['promo_is_valid']),
      promoMessage: map['promo_message'] as String? ?? '',
    );
  }

  final double itemsSubtotal;
  final double discountAmount;
  final double deliveryFee;
  final double serviceFee;
  final double totalAmount;
  final double storePayoutAmount;
  final double riderPayoutAmount;
  final double platformFeeAmount;
  final String? promoCode;
  final bool promoIsValid;
  final String promoMessage;
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
