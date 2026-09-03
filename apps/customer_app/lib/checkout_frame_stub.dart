import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:luumoh_core/luumoh_core.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  late final WebViewController _controller;
  var _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'LuumohCheckout',
        onMessageReceived: _handleSdkMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (error) {
            final message = error.description;
            setState(() {
              _isLoading = false;
              _error = message;
            });
            widget.onError?.call(message);
          },
        ),
      )
      ..loadHtmlString(_checkoutHtml(widget.checkout));
  }

  void _handleSdkMessage(JavaScriptMessage message) {
    final decoded = jsonDecode(message.message);
    if (decoded is! Map) {
      return;
    }
    final payload = Map<String, dynamic>.from(decoded);
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

  String _checkoutHtml(MonnifyCheckout checkout) {
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

    return '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <script src="https://sdk.monnify.com/plugin/monnify.js"></script>
  <style>
    html, body {
      margin: 0;
      min-height: 100%;
      background: #f8fafc;
      color: #0f172a;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    .state {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      text-align: center;
    }
    .panel {
      max-width: 360px;
      border: 1px solid #dbe3ef;
      border-radius: 18px;
      background: white;
      padding: 22px;
      box-shadow: 0 18px 45px rgba(15, 23, 42, .08);
    }
    button {
      border: 0;
      border-radius: 999px;
      background: #0b72ff;
      color: white;
      padding: 12px 18px;
      font-weight: 700;
      margin-top: 12px;
    }
  </style>
</head>
<body>
  <div class="state">
    <div class="panel">
      <h3>Opening secure checkout</h3>
      <p>Monnify checkout should appear here. If it closes, Luumoh will confirm your payment automatically.</p>
      <button onclick="openCheckout()">Open checkout</button>
    </div>
  </div>
  <script>
    function post(event, response, message) {
      LuumohCheckout.postMessage(JSON.stringify({
        event: event,
        response: response || {},
        message: message || ''
      }));
    }

    function openCheckout() {
      try {
        var config = $payload;
        config.onComplete = function (response) { post('complete', response); };
        config.onClose = function (response) { post('close', response); };
        window.MonnifySDK.initialize(config);
      } catch (error) {
        post('error', {}, String(error));
      }
    }

    window.addEventListener('load', function () {
      setTimeout(openCheckout, 500);
    });
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    );
  }
}
