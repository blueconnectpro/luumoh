import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class MonnifyCheckout {
  const MonnifyCheckout({
    required this.paymentId,
    required this.paymentReference,
    required this.amount,
    required this.currencyCode,
    required this.apiKey,
    required this.contractCode,
    required this.paymentDescription,
    required this.customerName,
    required this.customerEmail,
    this.checkoutUrl,
    this.redirectUrl,
  });

  factory MonnifyCheckout.fromMap(Map<String, dynamic> map) {
    return MonnifyCheckout(
      paymentId: map['paymentId'] as String,
      paymentReference: map['paymentReference'] as String,
      amount: (map['amount'] as num? ?? 0).toDouble(),
      currencyCode: map['currencyCode'] as String? ?? 'NGN',
      apiKey: map['apiKey'] as String? ?? '',
      contractCode: map['contractCode'] as String? ?? '',
      paymentDescription:
          map['paymentDescription'] as String? ?? 'Luumoh order',
      customerName: map['customerName'] as String? ?? 'Luumoh Customer',
      customerEmail: map['customerEmail'] as String? ?? '',
      checkoutUrl: map['checkoutUrl'] as String?,
      redirectUrl: map['redirectUrl'] as String?,
    );
  }

  final String paymentId;
  final String paymentReference;
  final double amount;
  final String currencyCode;
  final String apiKey;
  final String contractCode;
  final String paymentDescription;
  final String customerName;
  final String customerEmail;
  final String? checkoutUrl;
  final String? redirectUrl;
}

class MonnifyPaymentConfirmation {
  const MonnifyPaymentConfirmation({
    required this.paymentReference,
    required this.paymentStatus,
    this.providerStatus,
  });

  factory MonnifyPaymentConfirmation.fromMap(Map<String, dynamic> map) {
    return MonnifyPaymentConfirmation(
      paymentReference: map['paymentReference'] as String? ?? '',
      paymentStatus: map['paymentStatus'] as String? ?? 'pending',
      providerStatus: map['providerStatus'] as String?,
    );
  }

  final String paymentReference;
  final String paymentStatus;
  final String? providerStatus;
}

class MonnifyPaymentService {
  MonnifyPaymentService(this._client);

  final SupabaseClient _client;
  static const _functionTimeout = Duration(seconds: 35);

  Future<MonnifyCheckout> initiateCheckout(String orderId) async {
    final response = await _client.functions.invoke(
      'monnify-initiate',
      body: {'orderId': orderId},
    ).timeout(_functionTimeout);

    final data = response.data;
    if (data is! Map) {
      throw StateError('Unexpected Monnify response: $data');
    }

    return MonnifyCheckout.fromMap(Map<String, dynamic>.from(data));
  }

  Future<MonnifyPaymentConfirmation> confirmPayment({
    String? orderId,
    String? paymentReference,
  }) async {
    final response = await _client.functions.invoke(
      'monnify-confirm',
      body: {
        if (orderId != null) 'orderId': orderId,
        if (paymentReference != null) 'paymentReference': paymentReference,
      },
    ).timeout(_functionTimeout);

    final data = response.data;
    if (data is! Map) {
      throw StateError('Unexpected Monnify confirmation response: $data');
    }

    return MonnifyPaymentConfirmation.fromMap(Map<String, dynamic>.from(data));
  }
}
