class PaymentWebhookEventSummary {
  const PaymentWebhookEventSummary({
    required this.id,
    required this.provider,
    required this.signatureValid,
    required this.processingStatus,
    required this.createdAt,
    this.paymentReference,
    this.providerTransactionReference,
    this.eventType,
    this.paymentStatus,
    this.verificationStatus,
    this.processingError,
    this.paymentId,
    this.orderId,
    this.storeId,
    this.storeName,
  });

  factory PaymentWebhookEventSummary.fromMap(Map<String, dynamic> map) {
    return PaymentWebhookEventSummary(
      id: map['id'] as String,
      provider: map['provider'] as String? ?? 'monnify',
      paymentReference: map['payment_reference'] as String?,
      providerTransactionReference:
          map['provider_transaction_reference'] as String?,
      eventType: map['event_type'] as String?,
      paymentStatus: map['payment_status'] as String?,
      signatureValid: _boolValue(map['signature_valid']),
      verificationStatus: (map['verification_status'] as num?)?.toInt(),
      processingStatus: map['processing_status'] as String? ?? 'received',
      processingError: map['processing_error'] as String?,
      paymentId: map['payment_id'] as String?,
      orderId: map['order_id'] as String?,
      storeId: map['store_id'] as String?,
      storeName: map['store_name'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String provider;
  final String? paymentReference;
  final String? providerTransactionReference;
  final String? eventType;
  final String? paymentStatus;
  final bool signatureValid;
  final int? verificationStatus;
  final String processingStatus;
  final String? processingError;
  final String? paymentId;
  final String? orderId;
  final String? storeId;
  final String? storeName;
  final DateTime createdAt;
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
