// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:luumoh_core/luumoh_core.dart';

const supportsEmbeddedCheckout = true;

class MonnifyCheckoutFrame extends StatefulWidget {
  const MonnifyCheckoutFrame({
    required this.checkout,
    required this.onComplete,
    required this.onClose,
    this.onError,
    super.key,
  });

  final MonnifyCheckout checkout;
  final ValueChanged<Map<String, dynamic>> onComplete;
  final ValueChanged<Map<String, dynamic>> onClose;
  final ValueChanged<String>? onError;

  @override
  State<MonnifyCheckoutFrame> createState() => _MonnifyCheckoutFrameState();
}

class _MonnifyCheckoutFrameState extends State<MonnifyCheckoutFrame> {
  StreamSubscription<html.MessageEvent>? _messageSubscription;
  bool _isLaunching = true;
  bool _hasLaunched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _messageSubscription = html.window.onMessage.listen(_handleMessage);
    unawaited(_launchSdk());
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _handleMessage(html.MessageEvent event) {
    final data = event.data;
    if (data is! Map || data['source'] != 'luumoh-monnify-sdk') {
      return;
    }

    final payload = Map<String, dynamic>.from(data);
    final response = payload['response'] is Map
        ? Map<String, dynamic>.from(payload['response'] as Map)
        : <String, dynamic>{};
    switch (payload['event']) {
      case 'complete':
        widget.onComplete(response);
        break;
      case 'close':
        widget.onClose(response);
        break;
      case 'error':
        final message = payload['message']?.toString() ?? 'Checkout failed';
        setState(() => _error = message);
        widget.onError?.call(message);
        break;
    }
  }

  Future<void> _launchSdk() async {
    setState(() {
      _isLaunching = true;
      _error = null;
    });
    try {
      await _ensureSdkLoaded();
      _runCheckoutScript();
      if (mounted) {
        setState(() {
          _isLaunching = false;
          _hasLaunched = true;
        });
      }
    } on Object catch (error) {
      final message = error.toString();
      if (mounted) {
        setState(() {
          _isLaunching = false;
          _error = message;
        });
      }
      widget.onError?.call(message);
    }
  }

  Future<void> _ensureSdkLoaded() async {
    final existing = html.document.getElementById('monnify-sdk-script');
    if (existing != null) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return;
    }

    final completer = Completer<void>();
    final script = html.ScriptElement()
      ..id = 'monnify-sdk-script'
      ..src = 'https://sdk.monnify.com/plugin/monnify.js'
      ..async = true;
    script.onLoad.first.then((_) => completer.complete());
    script.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError('Monnify SDK failed to load');
      }
    });
    html.document.head?.append(script);
    await completer.future.timeout(const Duration(seconds: 18));
  }

  void _runCheckoutScript() {
    final checkout = widget.checkout;
    final payload = jsonEncode({
      'amount': checkout.amount,
      'currency': checkout.currencyCode,
      'reference': checkout.paymentReference,
      'customerFullName': checkout.customerName,
      'customerName': checkout.customerName,
      'customerEmail': checkout.customerEmail,
      'apiKey': checkout.apiKey,
      'contractCode': checkout.contractCode,
      'paymentDescription': checkout.paymentDescription,
      'redirectUrl': checkout.redirectUrl,
      'paymentMethods': ['CARD', 'ACCOUNT_TRANSFER', 'USSD', 'PHONE_NUMBER'],
      'metadata': {
        'paymentId': checkout.paymentId,
        'paymentReference': checkout.paymentReference,
      },
    });

    final script = html.ScriptElement()
      ..text = '''
(function () {
  try {
    var config = $payload;
    config.onComplete = function (response) {
      window.postMessage({ source: 'luumoh-monnify-sdk', event: 'complete', response: response || {} }, window.location.origin);
    };
    config.onClose = function (response) {
      window.postMessage({ source: 'luumoh-monnify-sdk', event: 'close', response: response || {} }, window.location.origin);
    };
    window.MonnifySDK.initialize(config);
  } catch (error) {
    window.postMessage({ source: 'luumoh-monnify-sdk', event: 'error', message: String(error) }, window.location.origin);
  }
})();
''';
    html.document.body?.append(script);
    script.remove();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLaunching)
              const CircularProgressIndicator()
            else if (_error != null)
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 38,
              )
            else
              Icon(
                Icons.verified_user_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 38,
              ),
            const SizedBox(height: 12),
            Text(
              _isLaunching
                  ? 'Opening Monnify secure checkout...'
                  : _error ?? 'Monnify checkout is open in this app.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLaunching ? null : _launchSdk,
              icon: Icon(_hasLaunched ? Icons.refresh : Icons.lock_open),
              label: Text(_hasLaunched ? 'Reopen checkout' : 'Open checkout'),
            ),
          ],
        ),
      ),
    );
  }
}
