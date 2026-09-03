import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:luumoh_core/luumoh_core.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'checkout_frame.dart';

part 'features/notifications/notifications_feature.dart';
part 'features/orders/order_feedback.dart';
part 'features/restaurants/restaurants_feature.dart';
part 'features/address/address_feature.dart';
part 'features/tracking/tracking_feature.dart';

const _luumohLogoAsset = 'assets/branding/luumoh_logo.png';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CustomerApp(environment: AppEnvironment.fromDartDefines()));
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({required this.environment, super.key});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Luumoh',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0b72ff)),
        useMaterial3: true,
      ),
      home: _StartupPage(environment: environment),
    );
  }
}

class _StartupPage extends StatefulWidget {
  const _StartupPage({required this.environment});

  final AppEnvironment environment;

  @override
  State<_StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<_StartupPage> {
  late final Future<String?> _startup = _initialize();

  Future<String?> _initialize() async {
    final configError = widget.environment.supabaseConfigurationError;
    if (configError != null) {
      return configError;
    }

    try {
      await widget.environment
          .initializeSupabase()
          .timeout(const Duration(seconds: 12));
      await AppEnvironment.recoverPersistedSession(Supabase.instance.client);
      if (widget.environment.mapboxAccessToken.isNotEmpty) {
        mapbox.MapboxOptions.setAccessToken(
          widget.environment.mapboxAccessToken,
        );
      }
      return null;
    } on Object catch (error) {
      return 'Supabase failed to initialize: $error';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StatusScaffold(
            title: 'Starting Luumoh',
            message: 'Connecting to Supabase...',
            isLoading: true,
          );
        }

        final error = snapshot.data;
        if (error != null) {
          return _StatusScaffold(
            title: 'Setup needed',
            message: '$error\n\nRun with:\n'
                '--dart-define=SUPABASE_URL=...\n'
                '--dart-define=SUPABASE_PUBLISHABLE_KEY=...',
          );
        }

        return _AuthGate(environment: widget.environment);
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        final user = session?.user;

        if (user == null) {
          return const _CustomerAuthPage();
        }

        return CustomerHomePage(
          userEmail: user.email ?? 'Customer',
          mapboxAccessToken: environment.mapboxAccessToken,
        );
      },
    );
  }
}

class _CustomerAuthPage extends StatefulWidget {
  const _CustomerAuthPage();

  @override
  State<_CustomerAuthPage> createState() => _CustomerAuthPageState();
}

class _CustomerAuthPageState extends State<_CustomerAuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSignUp = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final auth = Supabase.instance.client.auth;

    try {
      if (_isSignUp) {
        final response = await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {
            'full_name': _fullNameController.text.trim(),
            'phone': _phoneController.text.trim(),
          },
        );

        if (response.session == null && mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Check your email to confirm signup')),
          );
        }
      } else {
        await auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on AuthException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(_friendlyAuthError(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (!email.contains('@') || !email.contains('.')) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter your email first')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      messenger.showSnackBar(
        const SnackBar(content: Text('Password reset email sent')),
      );
    } on AuthException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(_friendlyAuthError(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: _LuumohLogo(
                        size: 104,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _isSignUp ? 'Create customer account' : 'Sign in',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use a customer account to place orders and track rider ETA updates.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    if (_isSignUp) ...[
                      TextFormField(
                        controller: _fullNameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (!_isSignUp) {
                            return null;
                          }
                          if (value == null || value.trim().length < 2) {
                            return 'Enter your full name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (!email.contains('@') || !email.contains('.')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _isSubmitting ? null : _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.length < 6) {
                          return 'Use at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: Text(
                        _isSubmitting
                            ? 'Please wait...'
                            : _isSignUp
                                ? 'Create account'
                                : 'Sign in',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!_isSignUp)
                      TextButton(
                        onPressed: _isSubmitting ? null : _sendPasswordReset,
                        child: const Text('Forgot password?'),
                      ),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(
                        _isSignUp
                            ? 'I already have an account'
                            : 'Create a new account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _friendlyAuthError(Object error) {
  final message = error.toString();
  final lowerMessage = message.toLowerCase();
  if (lowerMessage.contains('failed host lookup') ||
      lowerMessage.contains('socketexception') ||
      lowerMessage.contains('no address associated with hostname')) {
    return 'Network error: this device cannot reach Supabase. Check the emulator/device internet connection or restart the emulator with DNS enabled.';
  }
  return 'Auth failed: $message';
}

String _friendlyLocationError(Object error) {
  final message = error.toString();
  final lowerMessage = message.toLowerCase();
  if (lowerMessage.contains('default location in california')) {
    return 'GPS is using the emulator default location. Search and pick a Mapbox match, or set the emulator location and try GPS again.';
  }
  if (lowerMessage.contains('location services are disabled')) {
    return 'Turn on device location services, then try GPS again.';
  }
  if (lowerMessage.contains('location permission')) {
    return 'Allow location permission to use GPS, or search and pick an address instead.';
  }
  return 'Current location failed. Search and pick an address instead.';
}

class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({
    required this.title,
    required this.message,
    this.isLoading = false,
  });

  final String title;
  final String message;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LuumohLogo(
                    size: 112,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                  ),
                  const SizedBox(height: 24),
                  if (isLoading) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LuumohLogo extends StatelessWidget {
  const _LuumohLogo({
    this.size = 92,
    this.backgroundColor,
  });

  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      _luumohLogoAsset,
      width: size * 0.72,
      height: size * 0.72,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Luumoh',
    );

    if (backgroundColor == null) {
      return SizedBox.square(dimension: size, child: Center(child: logo));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            blurRadius: 26,
            offset: const Offset(0, 14),
            color: Colors.black.withValues(alpha: 0.12),
          ),
        ],
      ),
      child: SizedBox.square(dimension: size, child: Center(child: logo)),
    );
  }
}

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({
    required this.userEmail,
    required this.mapboxAccessToken,
    super.key,
  });

  final String userEmail;
  final String mapboxAccessToken;

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  final _cart = <String, int>{};
  final _catalogByProductId = <String, CatalogItem>{};
  final _addressController = TextEditingController();
  final _promoCodeController = TextEditingController();
  late final PlatformRepository _repository;
  late final MonnifyPaymentService _payments;
  late final MapboxLocationService _mapboxLocation;
  late final Stream<List<OrderSummary>> _ordersStream;
  late final Stream<List<OrderReviewSummary>> _reviewsStream;
  late final Stream<List<ProductReviewSummary>> _productReviewsStream;
  late final Stream<List<PromoCodeSummary>> _promoCodesStream;
  StreamSubscription<List<CatalogItem>>? _catalogSubscription;
  StreamSubscription<List<CustomerAddress>>? _addressSubscription;
  StreamSubscription<Uri>? _paymentReturnSubscription;
  StreamSubscription<List<OrderSummary>>? _orderSubscription;
  List<CatalogItem> _catalogItems = const [];
  List<CustomerAddress> _addresses = const [];
  MapboxPoint? _draftAddressPoint;
  Object? _catalogError;
  Object? _addressError;
  bool _isCatalogLoading = true;
  bool _isAddressLoading = true;
  bool _isPlacingOrder = false;
  bool _isApplyingPromo = false;
  bool _isQuotingCheckout = false;
  bool _isSavingAddress = false;
  bool _isUpdatingAddress = false;
  bool _isResolvingAddress = false;
  bool _hasCheckedCurrentAddressAfterLogin = false;
  bool _isShowingCurrentAddressPrompt = false;
  String? _selectedAddressId;
  var _fulfillmentType = 'delivery';
  final _payingOrderIds = <String>{};
  final _cancellingOrderIds = <String>{};
  final _receivingOrderIds = <String>{};
  final _promptedDeliveredOrderIds = <String>{};
  final _favoriteStoreIds = <String>{};
  PromoQuote? _promoQuote;
  CheckoutQuote? _checkoutQuote;
  String? _lastHandledPaymentReturn;
  final _knownPaymentStatuses = <String, String>{};
  final _knownOrderStatuses = <String, String>{};
  final _shownPaymentResultNotices = <String>{};
  bool _hasSeededPaymentStatuses = false;
  var _quoteRequestId = 0;
  var _selectedDestination = 0;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _repository = PlatformRepository(client);
    _payments = MonnifyPaymentService(client);
    _mapboxLocation = MapboxLocationService(widget.mapboxAccessToken);
    _ordersStream = _repository.watchMyOrders().asBroadcastStream();
    _reviewsStream = _repository.watchPublicStoreReviews().asBroadcastStream();
    _productReviewsStream =
        _repository.watchAllProductReviews().asBroadcastStream();
    _promoCodesStream = _repository.watchPromoCodes().asBroadcastStream();
    _listenForPaymentReturns();
    _catalogSubscription = _repository.watchCatalog().listen(
      _handleCatalogUpdate,
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _catalogError = error;
            _isCatalogLoading = false;
          });
        }
      },
    );
    _addressSubscription = _repository.watchMyAddresses().listen(
      _handleAddressUpdate,
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _addressError = error;
            _isAddressLoading = false;
          });
        }
      },
    );
    _orderSubscription = _ordersStream.listen(_handleOrderUpdates);
  }

  @override
  void dispose() {
    _catalogSubscription?.cancel();
    _addressSubscription?.cancel();
    _paymentReturnSubscription?.cancel();
    _orderSubscription?.cancel();
    _addressController.dispose();
    _promoCodeController.dispose();
    super.dispose();
  }

  void _toggleFavoriteStore(String storeId) {
    setState(() {
      if (!_favoriteStoreIds.add(storeId)) {
        _favoriteStoreIds.remove(storeId);
      }
    });
  }

  void _listenForPaymentReturns() {
    final appLinks = AppLinks();
    appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handlePaymentReturn(uri);
      }
    }).ignore();
    _paymentReturnSubscription = appLinks.uriLinkStream.listen(
      _handlePaymentReturn,
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment return failed: $error')),
        );
      },
    );
  }

  Future<void> _handlePaymentReturn(Uri uri) async {
    if (!_isPaymentReturnUri(uri)) {
      return;
    }

    final orderId = _paymentReturnOrderId(uri);
    if (orderId == null || orderId.isEmpty) {
      return;
    }
    final paymentReference = _paymentReturnReference(uri);

    final returnKey = '${uri.toString()}::$orderId';
    if (_lastHandledPaymentReturn == returnKey) {
      return;
    }
    _lastHandledPaymentReturn = returnKey;

    _focusTracking();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
          content: Text('Returned from Monnify. Confirming payment...')),
    );

    await _confirmPaymentWithMonnify(
      orderId: orderId,
      paymentReference: paymentReference,
    );
    final order = await _waitForReturnedPayment(
      orderId,
      paymentReference: paymentReference,
    );
    if (!mounted) {
      return;
    }

    if (order?.paymentStatus == 'paid') {
      await _showPaymentResultPopup(order!);
      _focusTracking();
      return;
    }

    if (order?.paymentStatus == 'failed' || order?.paymentStatus == 'expired') {
      await _showPaymentResultPopup(order!);
      _focusTracking();
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Payment is still pending. View this order here.'),
      ),
    );
    _focusTracking();
  }

  Future<void> _confirmPaymentWithMonnify({
    required String orderId,
    String? paymentReference,
  }) async {
    try {
      await _payments.confirmPayment(
        orderId: orderId,
        paymentReference: paymentReference,
      );
    } on Object catch (error) {
      debugPrint('Monnify confirmation failed: $error');
    }
  }

  Future<OrderSummary?> _waitForReturnedPayment(
    String orderId, {
    String? paymentReference,
  }) async {
    for (var attempt = 0; attempt < 13; attempt += 1) {
      try {
        if (attempt == 3 || attempt == 7 || attempt == 11) {
          await _confirmPaymentWithMonnify(
            orderId: orderId,
            paymentReference: paymentReference,
          );
        }
        final order = await _repository.fetchOrder(orderId);
        if (order == null) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }

        if (order.paymentStatus == 'paid' ||
            order.paymentStatus == 'failed' ||
            order.paymentStatus == 'expired') {
          return order;
        }

        if (attempt == 12) {
          return order;
        }
      } on Object {
        if (attempt == 12) {
          return null;
        }
      }

      await Future<void>.delayed(const Duration(seconds: 2));
    }

    return null;
  }

  void _handleOrderUpdates(List<OrderSummary> orders) {
    if (!_hasSeededPaymentStatuses) {
      for (final order in orders) {
        _knownPaymentStatuses[order.id] = order.paymentStatus;
        _knownOrderStatuses[order.id] = order.status;
      }
      _hasSeededPaymentStatuses = true;
      return;
    }

    for (final order in orders) {
      final previousStatus = _knownPaymentStatuses[order.id];
      _knownPaymentStatuses[order.id] = order.paymentStatus;
      if (previousStatus != null &&
          previousStatus != order.paymentStatus &&
          _isTerminalPaymentStatus(order.paymentStatus)) {
        unawaited(_showPaymentResultPopup(order));
      }

      final previousOrderStatus = _knownOrderStatuses[order.id];
      _knownOrderStatuses[order.id] = order.status;
      if (previousOrderStatus != null &&
          previousOrderStatus != 'delivered' &&
          order.status == 'delivered') {
        unawaited(_maybePromptDeliveredOrderReview(order));
      }
    }
  }

  Future<void> _maybePromptDeliveredOrderReview(OrderSummary order) async {
    if (!mounted || !_promptedDeliveredOrderIds.add(order.id)) {
      return;
    }

    try {
      final existingReviews = await _repository
          .watchOrderReviewsForOrder(order.id)
          .first
          .timeout(const Duration(seconds: 6));
      if (!mounted || existingReviews.isNotEmpty) {
        return;
      }
    } on Object {
      if (!mounted) {
        return;
      }
    }

    await _reviewOrder(order);
  }

  Future<void> _showPaymentResultPopup(OrderSummary order) async {
    if (!mounted || !_isTerminalPaymentStatus(order.paymentStatus)) {
      return;
    }

    final noticeKey = '${order.id}:${order.paymentStatus}';
    if (!_shownPaymentResultNotices.add(noticeKey)) {
      return;
    }

    _focusTracking();
    final isPaid = order.paymentStatus == 'paid';
    final title = isPaid ? 'Payment successful' : 'Payment not completed';
    final message = isPaid
        ? 'Your payment for ${order.storeName} was confirmed. The store can now prepare your order.'
        : 'Payment ${_humanStatus(order.paymentStatus)} for ${order.storeName}. You can retry from Orders.';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isPaid ? Icons.check_circle : Icons.error_outline,
              color: isPaid
                  ? Colors.green.shade700
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('View order'),
          ),
        ],
      ),
    );
  }

  void _focusTracking() {
    if (!mounted) {
      return;
    }

    setState(() => _selectedDestination = 2);
  }

  Future<void> _openProfileDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final profile = await _repository.watchMyProfile().first;
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _ProfileDialog(
          repository: _repository,
          profile: profile,
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Profile failed to load: $error')),
      );
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _NotificationsPage(
          repository: _repository,
          audience: 'customer',
        ),
      ),
    );
  }

  void _handleCatalogUpdate(List<CatalogItem> items) {
    String? cartMessage;
    setState(() {
      _catalogItems = items;
      _catalogError = null;
      _isCatalogLoading = false;
      cartMessage = _reconcileCart(items);
    });

    if (cartMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(cartMessage!)),
          );
        }
      });
    }
    _refreshCheckoutQuote();
  }

  void _handleAddressUpdate(List<CustomerAddress> addresses) {
    CustomerAddress? addressToCheck;
    setState(() {
      _addresses = addresses;
      _addressError = null;
      _isAddressLoading = false;

      final selectedStillExists = addresses.any(
        (address) => address.id == _selectedAddressId,
      );
      if (!selectedStillExists) {
        _selectedAddressId = _addressController.text.trim().isEmpty
            ? _preferredAddress(addresses)?.id
            : null;
      }

      if (_addressController.text.trim().isEmpty) {
        final selectedAddress = _findAddressById(addresses, _selectedAddressId);
        if (selectedAddress != null) {
          _addressController.text = selectedAddress.address;
        }
      }

      addressToCheck = _findAddressById(addresses, _selectedAddressId) ??
          _preferredAddress(addresses);
    });
    _scheduleCurrentAddressCheck(addressToCheck);
  }

  Future<void> _reloadAddresses() async {
    try {
      final addresses = await _repository.fetchMyAddresses();
      if (mounted) {
        _handleAddressUpdate(addresses);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _addressError = error;
          _isAddressLoading = false;
        });
      }
    }
  }

  void _scheduleCurrentAddressCheck(CustomerAddress? savedAddress) {
    if (_hasCheckedCurrentAddressAfterLogin ||
        _isShowingCurrentAddressPrompt ||
        savedAddress == null) {
      return;
    }
    if ((savedAddress.latitude == null || savedAddress.longitude == null) &&
        !_mapboxLocation.isConfigured) {
      _hasCheckedCurrentAddressAfterLogin = true;
      return;
    }

    _hasCheckedCurrentAddressAfterLogin = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_checkCurrentAddressAgainstSaved(savedAddress));
      }
    });
  }

  Future<void> _checkCurrentAddressAgainstSaved(
    CustomerAddress savedAddress,
  ) async {
    try {
      final currentPoint = await _mapboxLocation.currentPoint();
      final savedPoint = await _pointForSavedAddress(savedAddress);
      if (savedPoint == null) {
        return;
      }

      final distanceKm = _distanceKm(
        _LatLng(currentPoint.latitude, currentPoint.longitude),
        _LatLng(savedPoint.latitude, savedPoint.longitude),
      );
      if (distanceKm <= 0.25) {
        return;
      }

      var currentAddress = '${currentPoint.latitude.toStringAsFixed(6)}, '
          '${currentPoint.longitude.toStringAsFixed(6)}';
      if (_mapboxLocation.isConfigured) {
        final reversed = await _mapboxLocation.reverseGeocode(currentPoint);
        if (reversed != null) {
          currentAddress = reversed.address;
        }
      }

      if (!mounted) {
        return;
      }
      await _showCurrentAddressChoice(
        savedAddress: savedAddress,
        currentAddress: currentAddress,
        currentPoint: currentPoint,
      );
    } on Object catch (error) {
      debugPrint('Current address check skipped: $error');
    }
  }

  Future<MapboxPoint?> _pointForSavedAddress(CustomerAddress address) async {
    if (address.latitude != null && address.longitude != null) {
      return MapboxPoint(
        latitude: address.latitude!,
        longitude: address.longitude!,
      );
    }
    if (!_mapboxLocation.isConfigured || address.address.trim().length < 3) {
      return null;
    }

    final results = await _mapboxLocation.searchAddresses(
      address.address,
      country: 'ng',
      limit: 1,
    );
    if (results.isEmpty) {
      return null;
    }
    return results.first.point;
  }

  Future<void> _showCurrentAddressChoice({
    required CustomerAddress savedAddress,
    required String currentAddress,
    required MapboxPoint currentPoint,
  }) async {
    if (_isShowingCurrentAddressPrompt) {
      return;
    }

    _isShowingCurrentAddressPrompt = true;
    try {
      final useCurrent = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Use current address?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your saved delivery address looks different from where you are now.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Current address',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(currentAddress),
                const SizedBox(height: 12),
                Text(
                  'Saved address',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(savedAddress.address),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep saved'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.my_location_outlined),
              label: const Text('Use current'),
            ),
          ],
        ),
      );

      if (useCurrent == true && mounted) {
        await _updateSavedAddressToCurrent(
          savedAddress: savedAddress,
          currentAddress: currentAddress,
          currentPoint: currentPoint,
        );
      }
    } finally {
      _isShowingCurrentAddressPrompt = false;
    }
  }

  Future<void> _updateSavedAddressToCurrent({
    required CustomerAddress savedAddress,
    required String currentAddress,
    required MapboxPoint currentPoint,
  }) async {
    setState(() => _isUpdatingAddress = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.updateCustomerAddress(
        addressId: savedAddress.id,
        label: savedAddress.label,
        address: currentAddress,
        isDefault: savedAddress.isDefault,
        latitude: currentPoint.latitude,
        longitude: currentPoint.longitude,
      );
      await _reloadAddresses();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAddressId = savedAddress.id;
        _draftAddressPoint = currentPoint;
        _addressController.text = currentAddress;
      });
      _refreshCheckoutQuote();
      messenger.showSnackBar(
        const SnackBar(content: Text('Delivery address updated')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Address update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAddress = false);
      }
    }
  }

  String? _reconcileCart(List<CatalogItem> items) {
    _catalogByProductId
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.productId, item)));

    var removed = 0;
    var adjusted = 0;
    for (final productId in _cart.keys.toList()) {
      final item = _catalogByProductId[productId];
      if (item == null || !item.isAvailable || item.quantityAvailable <= 0) {
        _cart.remove(productId);
        removed++;
        continue;
      }

      final quantity = _cart[productId] ?? 0;
      if (quantity > item.quantityAvailable) {
        _cart[productId] = item.quantityAvailable;
        adjusted++;
      }
    }

    if (removed > 0 && adjusted > 0) {
      return 'Cart updated because stock changed.';
    }
    if (removed > 0) {
      return 'Unavailable items were removed from your cart.';
    }
    if (adjusted > 0) {
      return 'Cart quantities were reduced to match live stock.';
    }
    return null;
  }

  void _addToCart(CatalogItem item) {
    final messenger = ScaffoldMessenger.of(context);
    final liveItem = _catalogByProductId[item.productId] ?? item;

    if (!liveItem.isAvailable || liveItem.quantityAvailable <= 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('${liveItem.name} is unavailable')),
      );
      return;
    }

    String? existingStoreId;
    for (final productId in _cart.keys) {
      existingStoreId = _catalogByProductId[productId]?.storeId;
      if (existingStoreId != null) {
        break;
      }
    }
    if (existingStoreId != null && existingStoreId != liveItem.storeId) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Checkout one store at a time')),
      );
      return;
    }

    final currentQuantity = _cart[liveItem.productId] ?? 0;
    if (currentQuantity >= liveItem.quantityAvailable) {
      messenger.showSnackBar(
        SnackBar(content: Text('${liveItem.name} is at its order limit')),
      );
      return;
    }

    setState(() {
      _cart[liveItem.productId] = currentQuantity + 1;
    });
    _refreshCheckoutQuote();
  }

  void _increaseQuantity(String productId) {
    final item = _catalogByProductId[productId];
    if (item == null) {
      return;
    }
    _addToCart(item);
  }

  void _decreaseQuantity(String productId) {
    final currentQuantity = _cart[productId] ?? 0;
    setState(() {
      if (currentQuantity <= 1) {
        _cart.remove(productId);
      } else {
        _cart[productId] = currentQuantity - 1;
      }
    });
    _refreshCheckoutQuote();
  }

  void _removeFromCart(String productId) {
    setState(() => _cart.remove(productId));
    _refreshCheckoutQuote();
  }

  Future<void> _clearCart() async {
    if (_cart.isEmpty) {
      return;
    }

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('This removes every item currently in your cart.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep cart'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.remove_shopping_cart_outlined),
            label: const Text('Clear'),
          ),
        ],
      ),
    );

    if (shouldClear == true && mounted) {
      setState(() {
        _cart.clear();
        _promoQuote = null;
        _checkoutQuote = null;
        _promoCodeController.clear();
      });
    }
  }

  Future<void> _reorder(OrderSummary order) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final items = await _repository.watchOrderItems(order.id).first;
      if (items.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('This order has no items to reorder')),
        );
        return;
      }

      final reorderCart = <String, int>{};
      var skipped = 0;
      var adjusted = 0;
      String? reorderStoreId;

      for (final lineItem in items) {
        final catalogItem = _catalogByProductId[lineItem.productId];
        if (catalogItem == null ||
            !catalogItem.isAvailable ||
            catalogItem.quantityAvailable <= 0) {
          skipped++;
          continue;
        }

        reorderStoreId ??= catalogItem.storeId;
        if (catalogItem.storeId != reorderStoreId) {
          skipped++;
          continue;
        }

        final quantity =
            lineItem.quantity.clamp(1, catalogItem.quantityAvailable);
        if (quantity < lineItem.quantity) {
          adjusted++;
        }
        reorderCart[catalogItem.productId] = quantity;
      }

      if (reorderCart.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('None of those items are available now')),
        );
        return;
      }

      String? existingStoreId;
      for (final productId in _cart.keys) {
        existingStoreId = _catalogByProductId[productId]?.storeId;
        if (existingStoreId != null) {
          break;
        }
      }

      if (_cart.isNotEmpty &&
          existingStoreId != null &&
          existingStoreId != reorderStoreId) {
        if (!mounted) {
          return;
        }
        final replaceCart = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace cart?'),
            content: const Text(
              'This order is from a different store. Replace your current cart with these items?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep cart'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.shopping_cart_checkout),
                label: const Text('Replace'),
              ),
            ],
          ),
        );
        if (replaceCart != true || !mounted) {
          return;
        }
      }

      setState(() {
        if (existingStoreId != null && existingStoreId != reorderStoreId) {
          _cart.clear();
        }
        for (final entry in reorderCart.entries) {
          final catalogItem = _catalogByProductId[entry.key];
          if (catalogItem == null) {
            continue;
          }
          final existingQuantity = _cart[entry.key] ?? 0;
          final mergedQuantity = (existingQuantity + entry.value)
              .clamp(1, catalogItem.quantityAvailable);
          if (mergedQuantity < existingQuantity + entry.value) {
            adjusted++;
          }
          _cart[entry.key] = mergedQuantity;
        }
      });
      _refreshCheckoutQuote();

      final details = [
        if (adjusted > 0) 'some quantities were adjusted',
        if (skipped > 0)
          '$skipped unavailable item${skipped == 1 ? '' : 's'} skipped',
      ];
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            details.isEmpty
                ? 'Added order items to cart'
                : 'Added available items to cart; ${details.join(', ')}',
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Reorder failed: $error')),
      );
    }
  }

  Future<void> _reportIssue(OrderSummary order) async {
    final result = await showDialog<_OrderIssueDraft>(
      context: context,
      builder: (context) => _ReportIssueDialog(order: order),
    );
    if (result == null || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.createOrderIssue(
        orderId: order.id,
        category: result.category,
        message: result.message,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Issue sent to support')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Issue report failed: $error')),
      );
    }
  }

  Future<void> _reviewOrder(OrderSummary order) async {
    var items = const <OrderLineItem>[];
    try {
      items = await _repository
          .watchOrderItems(order.id)
          .first
          .timeout(const Duration(seconds: 8));
    } on Object {
      items = const <OrderLineItem>[];
    }
    if (!mounted) {
      return;
    }

    final orderResult = await showDialog<_OrderReviewDraft>(
      context: context,
      builder: (context) => _ReviewOrderDialog(
        order: order,
        items: items,
      ),
    );
    if (orderResult == null || !mounted) {
      return;
    }

    final riderReview = order.riderId == null
        ? null
        : await showDialog<_RiderReviewDraft>(
            context: context,
            builder: (context) => _ReviewDeliveryDialog(order: order),
          );
    if (order.riderId != null && riderReview == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.submitOrderReview(
        orderId: order.id,
        rating: orderResult.rating,
        comment: orderResult.comment,
      );
      await Future.wait([
        for (final itemReview in orderResult.itemReviews)
          _repository.submitProductReview(
            orderId: order.id,
            productId: itemReview.productId,
            rating: itemReview.rating,
            comment: itemReview.comment,
          ),
        if (riderReview != null)
          _repository.submitRiderReview(
            orderId: order.id,
            rating: riderReview.rating,
            comment: riderReview.comment,
          ),
      ]);
      messenger.showSnackBar(
        const SnackBar(content: Text('Thanks for the thoughtful review')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Review failed: $error')),
      );
    }
  }

  Future<void> _markOrderReceived(OrderSummary order) async {
    if (_receivingOrderIds.contains(order.id)) {
      return;
    }

    setState(() => _receivingOrderIds.add(order.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.markOrderReceived(order.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Order marked received')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not mark received: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _receivingOrderIds.remove(order.id));
      }
    }
  }

  List<Map<String, dynamic>> _cartOrderItems() {
    return _cart.entries
        .map(
          (entry) => {
            'product_id': entry.key,
            'quantity': entry.value,
          },
        )
        .toList();
  }

  String? _cartStoreId() {
    String? storeId;
    for (final productId in _cart.keys) {
      final item = _catalogByProductId[productId];
      if (item == null) {
        continue;
      }
      storeId ??= item.storeId;
      if (storeId != item.storeId) {
        return null;
      }
    }
    return storeId;
  }

  Future<void> _applyPromoCode() async {
    final messenger = ScaffoldMessenger.of(context);
    final code = _promoCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _promoQuote = null);
      return;
    }

    final storeId = _cartStoreId();
    if (storeId == null) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Checkout one store before applying promo')),
      );
      return;
    }

    setState(() => _isApplyingPromo = true);
    try {
      final quote = await _repository.quoteOrderTotals(
        storeId: storeId,
        items: _cartOrderItems(),
        promoCode: code,
        fulfillmentType: _fulfillmentType,
        customerLatitude: _selectedDeliveryAddress()?.latitude,
        customerLongitude: _selectedDeliveryAddress()?.longitude,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _checkoutQuote = quote;
        _promoQuote = PromoQuote(
          isValid: quote.promoIsValid,
          message: quote.promoMessage,
          code: quote.promoCode ?? code,
          discountAmount: quote.discountAmount,
        );
      });
      messenger.showSnackBar(SnackBar(content: Text(quote.promoMessage)));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Promo check failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isApplyingPromo = false);
      }
    }
  }

  void _clearPromoCode() {
    setState(() {
      _promoCodeController.clear();
      _promoQuote = null;
    });
    _refreshCheckoutQuote();
  }

  Future<void> _refreshCheckoutQuote() async {
    final requestId = ++_quoteRequestId;
    final storeId = _cartStoreId();
    if (_cart.isEmpty || storeId == null) {
      if (mounted) {
        setState(() {
          _checkoutQuote = null;
          _isQuotingCheckout = false;
        });
      }
      return;
    }

    final promoCode = _promoCodeController.text.trim();
    if (mounted) {
      setState(() => _isQuotingCheckout = true);
    }

    try {
      final quote = await _repository.quoteOrderTotals(
        storeId: storeId,
        items: _cartOrderItems(),
        promoCode: promoCode.isEmpty ? null : promoCode,
        fulfillmentType: _fulfillmentType,
        customerLatitude: _selectedDeliveryAddress()?.latitude,
        customerLongitude: _selectedDeliveryAddress()?.longitude,
      );
      if (!mounted || requestId != _quoteRequestId) {
        return;
      }
      setState(() => _checkoutQuote = quote);
    } on Object {
      if (!mounted || requestId != _quoteRequestId) {
        return;
      }
      setState(() => _checkoutQuote = null);
    } finally {
      if (mounted && requestId == _quoteRequestId) {
        setState(() => _isQuotingCheckout = false);
      }
    }
  }

  void _selectAddress(CustomerAddress address) {
    setState(() {
      _selectedAddressId = address.id;
      _addressController.text = address.address;
      _draftAddressPoint = address.latitude == null || address.longitude == null
          ? null
          : MapboxPoint(
              latitude: address.latitude!,
              longitude: address.longitude!,
            );
    });
    _refreshCheckoutQuote();
  }

  Future<MapboxAddressResult?> _resolveAddressResultWithMapbox(
    String address, {
    bool updateController = true,
  }) async {
    if (!_mapboxLocation.isConfigured || address.trim().length < 3) {
      return null;
    }

    final results = await _mapboxLocation.searchAddresses(
      address,
      proximity: _draftAddressPoint,
      country: 'ng',
      limit: 1,
    );
    if (results.isEmpty) {
      return null;
    }
    final result = results.first;
    if (updateController) {
      _addressController.text = result.address;
    }
    return result;
  }

  Future<MapboxAddressResult?> _tryResolveAddressResultWithMapbox(
    String address, {
    bool updateController = false,
  }) async {
    try {
      return await _resolveAddressResultWithMapbox(
        address,
        updateController: updateController,
      );
    } on Object {
      return null;
    }
  }

  Future<MapboxPoint?> _useCurrentLocationForAddress([
    VoidCallback? refresh,
  ]) async {
    setState(() => _isResolvingAddress = true);
    refresh?.call();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final point = await _mapboxLocation.currentPoint();
      var address =
          '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
      if (_mapboxLocation.isConfigured) {
        final reversed = await _mapboxLocation.reverseGeocode(point);
        if (reversed != null) {
          address = reversed.address;
        }
      }
      setState(() {
        _selectedAddressId = null;
        _draftAddressPoint = point;
        _addressController.text = address;
      });
      refresh?.call();
      _refreshCheckoutQuote();
      messenger.showSnackBar(
        const SnackBar(content: Text('Current location added')),
      );
      return point;
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(_friendlyLocationError(error))),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
        refresh?.call();
      }
    }
  }

  Future<MapboxPoint?> _findTypedAddress([VoidCallback? refresh]) async {
    final query = _addressController.text.trim();
    if (!_mapboxLocation.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MAPBOX_ACCESS_TOKEN is not configured')),
      );
      return null;
    }
    if (query.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least 3 characters')),
      );
      return null;
    }

    setState(() => _isResolvingAddress = true);
    refresh?.call();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final results = await _mapboxLocation.searchAddresses(
        query,
        proximity: _draftAddressPoint,
        country: 'ng',
      );
      if (!mounted) {
        return null;
      }
      if (results.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No Mapbox address match found')),
        );
        return null;
      }
      final selected = await showModalBottomSheet<MapboxAddressResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _MapboxAddressResultsSheet(results: results),
      );
      if (selected == null || !mounted) {
        return null;
      }
      setState(() {
        _selectedAddressId = null;
        _draftAddressPoint = selected.point;
        _addressController.text = selected.address;
      });
      refresh?.call();
      _refreshCheckoutQuote();
      return selected.point;
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Address lookup failed: $error')),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
        refresh?.call();
      }
    }
  }

  Future<void> _saveCurrentAddress() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a delivery address first')),
      );
      return;
    }

    final label = await showDialog<String>(
      context: context,
      builder: (context) => const _SaveAddressDialog(),
    );
    if (label == null || !mounted) {
      return;
    }

    setState(() => _isSavingAddress = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      var addressToSave = address;
      var location = _draftAddressPoint;
      if (location == null && _mapboxLocation.isConfigured) {
        final result = await _tryResolveAddressResultWithMapbox(
          address,
          updateController: false,
        );
        if (result != null) {
          addressToSave = result.address;
          location = result.point;
        }
      }
      final addressId = await _repository.saveCustomerAddress(
        label: label,
        address: addressToSave,
        isDefault: _addresses.isEmpty,
        latitude: location?.latitude,
        longitude: location?.longitude,
      );
      await _reloadAddresses();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAddressId = addressId;
        _draftAddressPoint = location;
        _addressController.text = addressToSave;
      });
      _refreshCheckoutQuote();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            location == null
                ? 'Saved written address. Use Pick match later for a delivery pin.'
                : 'Saved delivery address',
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Address save failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingAddress = false);
      }
    }
  }

  Future<_LatLng?> _ensureCheckoutAddressIsSaved() async {
    final selectedAddress = _selectedDeliveryAddress();
    if (_fulfillmentType == 'pickup') {
      return null;
    }
    if (selectedAddress != null) {
      if (selectedAddress.latitude != null &&
          selectedAddress.longitude != null) {
        return _LatLng(selectedAddress.latitude!, selectedAddress.longitude!);
      }
      return null;
    }

    final address = _addressController.text.trim();
    if (address.isEmpty) {
      return null;
    }

    var addressToSave = address;
    var location = _draftAddressPoint;
    if (location == null && _mapboxLocation.isConfigured) {
      final result = await _tryResolveAddressResultWithMapbox(
        address,
        updateController: false,
      );
      if (result != null) {
        addressToSave = result.address;
        location = result.point;
      }
    }
    final addressId = await _repository.saveCustomerAddress(
      label: _addresses.isEmpty ? 'Home' : 'Delivery address',
      address: addressToSave,
      isDefault: _addresses.isEmpty,
      latitude: location?.latitude,
      longitude: location?.longitude,
    );
    await _reloadAddresses();
    if (mounted) {
      setState(() {
        _selectedAddressId = addressId;
        _draftAddressPoint = location;
        _addressController.text = addressToSave;
      });
    }
    if (location == null) {
      return null;
    }
    return _LatLng(location.latitude, location.longitude);
  }

  Future<void> _setDefaultAddress(CustomerAddress address) async {
    setState(() => _isUpdatingAddress = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.setDefaultCustomerAddress(address.id);
      await _reloadAddresses();
      if (!mounted) {
        return;
      }
      setState(() => _selectedAddressId = address.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${address.label} is now default')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Default address update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAddress = false);
      }
    }
  }

  Future<void> _deleteAddress(CustomerAddress address) async {
    setState(() => _isUpdatingAddress = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.deleteCustomerAddress(address.id);
      await _reloadAddresses();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Deleted ${address.label}')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Address delete failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAddress = false);
      }
    }
  }

  Future<void> _updateAddress({
    required CustomerAddress address,
    required String label,
    required String addressText,
    required MapboxPoint? point,
    required bool isDefault,
  }) async {
    if (addressText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a delivery address first')),
      );
      return;
    }

    setState(() => _isUpdatingAddress = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var typedAddress = addressText.trim();
      var resolvedPoint = point;
      if (resolvedPoint == null && _mapboxLocation.isConfigured) {
        final result = await _tryResolveAddressResultWithMapbox(
          typedAddress,
          updateController: false,
        );
        if (result != null) {
          typedAddress = result.address;
          resolvedPoint = result.point;
        }
      }
      await _repository.updateCustomerAddress(
        addressId: address.id,
        label: label.trim().isEmpty ? address.label : label.trim(),
        address: typedAddress,
        isDefault: isDefault,
        latitude: resolvedPoint?.latitude,
        longitude: resolvedPoint?.longitude,
      );
      await _reloadAddresses();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAddressId = address.id;
        _addressController.text = typedAddress;
        _draftAddressPoint = resolvedPoint;
      });
      _refreshCheckoutQuote();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            resolvedPoint == null
                ? 'Updated written address. Use Pick match later for a delivery pin.'
                : 'Address updated',
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Address update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAddress = false);
      }
    }
  }

  String _deliveryLocationLabel() {
    CustomerAddress? selected;
    for (final address in _addresses) {
      if (address.id == _selectedAddressId) {
        selected = address;
        break;
      }
    }
    final controllerAddress = _addressController.text.trim();
    if (selected != null) {
      return selected.label;
    }
    if (controllerAddress.isNotEmpty) {
      return controllerAddress;
    }
    final defaultAddress = _addresses.where((address) => address.isDefault);
    if (defaultAddress.isNotEmpty) {
      return defaultAddress.first.label;
    }
    return 'Add address';
  }

  void _setFulfillmentType(String value) {
    if (_fulfillmentType == value) {
      return;
    }
    setState(() => _fulfillmentType = value);
    _refreshCheckoutQuote();
  }

  CustomerAddress? _selectedDeliveryAddress() {
    if (_selectedAddressId == null &&
        _addressController.text.trim().isNotEmpty) {
      return null;
    }
    return _findAddressById(_addresses, _selectedAddressId) ??
        _preferredAddress(_addresses);
  }

  Future<void> _openProductDetails(CatalogItem item) async {
    final liveItem = _catalogByProductId[item.productId] ?? item;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProductDetailPage(
          item: liveItem,
          cartQuantity: _cart[liveItem.productId] ?? 0,
          reviewsStream: _repository.watchProductReviews(liveItem.productId),
          onAdd: _addToCart,
        ),
      ),
    );
  }

  Future<void> _openAddressSheet() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _AddressPage(
          initialAddresses: _addresses,
          addressesStream: _repository.watchMyAddresses(),
          selectedAddressId: _selectedAddressId,
          addressController: _addressController,
          draftAddressPoint: _draftAddressPoint,
          hasMapboxToken: _mapboxLocation.isConfigured,
          addressError: _addressError,
          isAddressLoading: _isAddressLoading,
          isSavingAddress: _isSavingAddress,
          isUpdatingAddress: _isUpdatingAddress,
          isResolvingAddress: _isResolvingAddress,
          onAddressTextChanged: () {
            setState(() {
              _selectedAddressId = null;
              _draftAddressPoint = null;
            });
          },
          onUseCurrentLocation: _useCurrentLocationForAddress,
          onFindTypedAddress: _findTypedAddress,
          onSaveAddress: (refresh) =>
              _saveCurrentAddress().whenComplete(refresh),
          onSelectAddress: _selectAddress,
          onSetDefaultAddress: _setDefaultAddress,
          onDeleteAddress: _deleteAddress,
          onUpdateAddress: _updateAddress,
        ),
      ),
    );
  }

  Widget _buildCartPane({
    VoidCallback? onChanged,
    bool closeBeforeCheckout = false,
    bool showTitle = true,
  }) {
    return _CartPane(
      fulfillmentType: _fulfillmentType,
      cart: _cart,
      catalogByProductId: _catalogByProductId,
      addresses: _addresses,
      selectedAddressId: _selectedAddressId,
      selectedDeliveryAddress: _selectedDeliveryAddress(),
      addressError: _addressError,
      isAddressLoading: _isAddressLoading,
      isSavingAddress: _isSavingAddress,
      isUpdatingAddress: _isUpdatingAddress,
      addressController: _addressController,
      promoCodeController: _promoCodeController,
      promoQuote: _promoQuote,
      checkoutQuote: _checkoutQuote,
      isSubmitting: _isPlacingOrder,
      isApplyingPromo: _isApplyingPromo,
      isQuotingCheckout: _isQuotingCheckout,
      showTitle: showTitle,
      onShowDetails: _openProductDetails,
      onIncrease: (productId) {
        _increaseQuantity(productId);
        onChanged?.call();
      },
      onDecrease: (productId) {
        _decreaseQuantity(productId);
        onChanged?.call();
      },
      onRemove: (productId) {
        _removeFromCart(productId);
        onChanged?.call();
      },
      onClearCart: () {
        _clearCart().whenComplete(() => onChanged?.call());
      },
      onSelectAddress: (address) {
        _selectAddress(address);
        onChanged?.call();
      },
      onSaveAddress: () {
        _saveCurrentAddress().whenComplete(() => onChanged?.call());
      },
      onSetDefaultAddress: (address) {
        _setDefaultAddress(address).whenComplete(() => onChanged?.call());
      },
      onDeleteAddress: (address) {
        _deleteAddress(address).whenComplete(() => onChanged?.call());
      },
      onManageAddresses: () {
        _openAddressSheet().whenComplete(() => onChanged?.call());
      },
      onApplyPromo: () {
        _applyPromoCode().whenComplete(() => onChanged?.call());
      },
      onClearPromo: () {
        _clearPromoCode();
        onChanged?.call();
      },
      onPlaceOrder: _cart.isEmpty || _isPlacingOrder
          ? null
          : () {
              if (closeBeforeCheckout) {
                Navigator.of(context).pop();
              }
              _placeOrder();
            },
    );
  }

  Future<void> _openCart() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setPageState) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Cart'),
                ),
                body: SafeArea(
                  child: _buildCartPane(
                    closeBeforeCheckout: true,
                    showTitle: false,
                    onChanged: () => setPageState(() {}),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartQuantity =
        _cart.values.fold<int>(0, (total, quantity) => total + quantity);
    final catalog = _CatalogPane(
      reviewsStream: _reviewsStream,
      productReviewsStream: _productReviewsStream,
      items: _catalogItems,
      isLoading: _isCatalogLoading,
      error: _catalogError,
      cart: _cart,
      selectedAddress: _selectedDeliveryAddress(),
      favoriteStoreIds: _favoriteStoreIds,
      onAdd: _addToCart,
      onShowDetails: _openProductDetails,
      onToggleFavoriteStore: _toggleFavoriteStore,
      fulfillmentType: _fulfillmentType,
      onFulfillmentChanged: _setFulfillmentType,
      showHomeSections: true,
    );
    final search = _CatalogPane(
      reviewsStream: _reviewsStream,
      productReviewsStream: _productReviewsStream,
      items: _catalogItems,
      isLoading: _isCatalogLoading,
      error: _catalogError,
      cart: _cart,
      selectedAddress: _selectedDeliveryAddress(),
      favoriteStoreIds: _favoriteStoreIds,
      onAdd: _addToCart,
      onShowDetails: _openProductDetails,
      onToggleFavoriteStore: _toggleFavoriteStore,
      fulfillmentType: _fulfillmentType,
      onFulfillmentChanged: _setFulfillmentType,
      showHomeSections: false,
    );
    final tracking = _TrackingPane(
      repository: _repository,
      ordersStream: _ordersStream,
      hasMapboxToken: _mapboxLocation.isConfigured,
      catalogByProductId: _catalogByProductId,
      payingOrderIds: _payingOrderIds,
      cancellingOrderIds: _cancellingOrderIds,
      receivingOrderIds: _receivingOrderIds,
      onPayNow: _payForOrder,
      onCancelOrder: _cancelPendingOrder,
      onMarkReceived: _markOrderReceived,
      onReorder: _reorder,
      onReportIssue: _reportIssue,
      onReviewOrder: _reviewOrder,
    );
    final restaurants = _RestaurantsPane(
      ordersStream: _ordersStream,
      reviewsStream: _reviewsStream,
      productReviewsStream: _productReviewsStream,
      promoCodesStream: _promoCodesStream,
      items: _catalogItems,
      isLoading: _isCatalogLoading,
      error: _catalogError,
      cart: _cart,
      selectedAddress: _selectedDeliveryAddress(),
      favoriteStoreIds: _favoriteStoreIds,
      onAdd: _addToCart,
      onShowDetails: _openProductDetails,
      onToggleFavoriteStore: _toggleFavoriteStore,
    );
    final account = _AccountPane(
      userEmail: widget.userEmail,
      selectedAddress: _selectedDeliveryAddress(),
      onEditProfile: _openProfileDialog,
      onManageAddresses: _openAddressSheet,
      onOpenNotifications: _openNotifications,
      onSignOut: () => Supabase.instance.client.auth.signOut(),
    );
    final pages = [catalog, search, tracking, restaurants, account];

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: _LuumohLogo(size: 42),
        ),
        title: TextButton.icon(
          onPressed: _openAddressSheet,
          icon: const Icon(Icons.location_on_outlined),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              _deliveryLocationLabel(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Cart',
            onPressed: _openCart,
            icon: Badge(
              isLabelVisible: cartQuantity > 0,
              label: Text(cartQuantity.toString()),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          _NotificationIcon(
            repository: _repository,
            audience: 'customer',
            onPressed: _openNotifications,
          ),
        ],
      ),
      body: pages[_selectedDestination],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedDestination,
        onDestinationSelected: (index) {
          setState(() => _selectedDestination = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Restaurants',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }

  Future<void> _placeOrder() async {
    final messenger = ScaffoldMessenger.of(context);
    final isPickup = _fulfillmentType == 'pickup';
    if (!isPickup && _addressController.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a delivery address')),
      );
      return;
    }

    _LatLng? deliveryLocation;
    try {
      deliveryLocation = await _ensureCheckoutAddressIsSaved();
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Address save failed: $error')),
      );
      return;
    }

    final cartItems = <MapEntry<CatalogItem, int>>[];
    for (final entry in _cart.entries) {
      final item = _catalogByProductId[entry.key];
      if (item == null || !item.isAvailable || item.quantityAvailable <= 0) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Cart contains unavailable items')),
        );
        return;
      }
      if (entry.value > item.quantityAvailable) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${item.name} is no longer available in that amount'),
          ),
        );
        return;
      }
      cartItems.add(MapEntry(item, entry.value));
    }

    if (cartItems.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Your cart is empty')),
      );
      return;
    }

    final firstStoreId = cartItems.first.key.storeId;
    final hasMixedStores = cartItems.any(
      (entry) => entry.key.storeId != firstStoreId,
    );

    if (hasMixedStores) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Checkout one store at a time')),
      );
      return;
    }

    setState(() => _isPlacingOrder = true);
    try {
      final orderId = await _repository.placeOrder(
        storeId: firstStoreId,
        deliveryAddress:
            isPickup ? 'Pickup at store' : _addressController.text.trim(),
        promoCode: _promoQuote?.isValid == true
            ? _promoQuote?.code ?? _promoCodeController.text.trim()
            : null,
        fulfillmentType: _fulfillmentType,
        customerLatitude: isPickup ? null : deliveryLocation?.latitude,
        customerLongitude: isPickup ? null : deliveryLocation?.longitude,
        items: cartItems
            .map(
              (entry) => {
                'product_id': entry.key.productId,
                'quantity': entry.value,
              },
            )
            .toList(),
      );
      final checkout = await _payments.initiateCheckout(orderId);
      if (!mounted) {
        return;
      }
      final paidOrder = await Navigator.of(context).push<OrderSummary?>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => _CheckoutPage(
            checkout: checkout,
            orderId: orderId,
            repository: _repository,
          ),
        ),
      );
      if (paidOrder != null && mounted) {
        if (paidOrder.paymentStatus == 'paid') {
          setState(() {
            _cart.clear();
            _promoQuote = null;
            _checkoutQuote = null;
            _promoCodeController.clear();
          });
        }
        await _showPaymentResultPopup(paidOrder);
        _focusTracking();
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Order failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPlacingOrder = false);
      }
    }
  }

  Future<void> _payForOrder(OrderSummary order) async {
    if (_payingOrderIds.contains(order.id)) {
      return;
    }

    setState(() => _payingOrderIds.add(order.id));
    final messenger = ScaffoldMessenger.of(context);

    try {
      final checkout = await _payments.initiateCheckout(order.id);
      if (!mounted) {
        return;
      }

      final paidOrder = await Navigator.of(context).push<OrderSummary?>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => _CheckoutPage(
            checkout: checkout,
            orderId: order.id,
            repository: _repository,
          ),
        ),
      );
      if (paidOrder != null && mounted) {
        await _showPaymentResultPopup(paidOrder);
        _focusTracking();
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Payment checkout failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _payingOrderIds.remove(order.id));
      }
    }
  }

  Future<void> _cancelPendingOrder(OrderSummary order) async {
    if (_cancellingOrderIds.contains(order.id)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel order?'),
        content:
            const Text('This releases the reserved stock for other customers.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _cancellingOrderIds.add(order.id));
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.cancelPendingOrder(order.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Order cancelled')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Cancel failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _cancellingOrderIds.remove(order.id));
      }
    }
  }
}

class _CatalogPane extends StatefulWidget {
  const _CatalogPane({
    required this.reviewsStream,
    required this.productReviewsStream,
    required this.items,
    required this.isLoading,
    required this.error,
    required this.cart,
    required this.selectedAddress,
    required this.favoriteStoreIds,
    required this.onAdd,
    required this.onShowDetails,
    required this.onToggleFavoriteStore,
    required this.fulfillmentType,
    required this.onFulfillmentChanged,
    required this.showHomeSections,
  });

  final Stream<List<OrderReviewSummary>> reviewsStream;
  final Stream<List<ProductReviewSummary>> productReviewsStream;
  final List<CatalogItem> items;
  final bool isLoading;
  final Object? error;
  final Map<String, int> cart;
  final CustomerAddress? selectedAddress;
  final Set<String> favoriteStoreIds;
  final ValueChanged<CatalogItem> onAdd;
  final ValueChanged<CatalogItem> onShowDetails;
  final ValueChanged<String> onToggleFavoriteStore;
  final String fulfillmentType;
  final ValueChanged<String> onFulfillmentChanged;
  final bool showHomeSections;

  @override
  State<_CatalogPane> createState() => _CatalogPaneState();
}

class _CatalogPaneState extends State<_CatalogPane> {
  final _searchController = TextEditingController();
  var _selectedCategory = 'all';
  var _selectedStoreId = 'all';
  var _showAvailableOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.error != null) {
      return _InlineState(
        title: 'Catalog failed to load',
        message: widget.error.toString(),
      );
    }

    if (widget.isLoading) {
      return const _InlineState(
        title: 'Loading products',
        message: 'Fetching available stores and inventory...',
        isLoading: true,
      );
    }

    if (widget.items.isEmpty) {
      return const _InlineState(
        title: 'No products available yet',
        message: 'Open a store and add inventory to see items here.',
      );
    }

    final categories = _catalogCategories(widget.items);
    final stores = _catalogStores(widget.items);
    if (_selectedCategory != 'all' && !categories.contains(_selectedCategory)) {
      _selectedCategory = 'all';
    }
    if (_selectedStoreId != 'all' &&
        !stores.any((store) => store.storeId == _selectedStoreId)) {
      _selectedStoreId = 'all';
    }
    final visibleItems = widget.items.where((item) {
      final matchesCategory =
          _selectedCategory == 'all' || item.category == _selectedCategory;
      final matchesStore =
          _selectedStoreId == 'all' || item.storeId == _selectedStoreId;
      final matchesAvailability = !_showAvailableOnly || item.isAvailable;
      final matchesSearch = widget.showHomeSections ||
          _matchesCatalogSearch(
            item,
            _searchController.text,
          );
      return matchesCategory &&
          matchesStore &&
          matchesAvailability &&
          matchesSearch;
    }).toList();
    if (widget.showHomeSections) {
      visibleItems.sort(_compareHomeCatalogItems);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CatalogHomeHeader(
          fulfillmentType: widget.fulfillmentType,
          onFulfillmentChanged: widget.onFulfillmentChanged,
        ),
        if (!widget.showHomeSections) ...[
          const SizedBox(height: 12),
          _CatalogFilters(
            searchController: _searchController,
            stores: stores,
            selectedCategory: _selectedCategory,
            selectedStoreId: _selectedStoreId,
            showAvailableOnly: _showAvailableOnly,
            shownCount: visibleItems.length,
            onSearchChanged: () => setState(() {}),
            onSelected: (value) => setState(() => _selectedCategory = value),
            onStoreSelected: (value) =>
                setState(() => _selectedStoreId = value),
            onAvailableOnlyChanged: (value) =>
                setState(() => _showAvailableOnly = value),
          ),
        ],
        if (widget.showHomeSections) ...[
          _HomeFavoriteRestaurantsSection(
            reviewsStream: widget.reviewsStream,
            productReviewsStream: widget.productReviewsStream,
            stores: _favoriteRestaurantStores(
              widget.items,
              widget.favoriteStoreIds,
            ),
            selectedAddress: widget.selectedAddress,
            favoriteStoreIds: widget.favoriteStoreIds,
            cart: widget.cart,
            onAdd: widget.onAdd,
            onShowDetails: widget.onShowDetails,
            onToggleFavoriteStore: widget.onToggleFavoriteStore,
          ),
          const SizedBox(height: 12),
          _HomeCategoryScroller(
            categories: categories,
            selectedCategory: _selectedCategory,
            onSelected: (value) => setState(() => _selectedCategory = value),
          ),
          const SizedBox(height: 14),
        ] else ...[
          const SizedBox(height: 18),
          Text(
            'Search',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
        ],
        if (widget.showHomeSections)
          Text(
            'Essentials near you',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          )
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  'Search results',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _selectedCategory = 'all';
                  _selectedStoreId = 'all';
                  _showAvailableOnly = false;
                  _searchController.clear();
                }),
                child: const Text('Clear'),
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (visibleItems.isEmpty)
          const _InlineState(
            title: 'No matching items',
            message: 'Try a different category, store, or search.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 620
                      ? 3
                      : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: visibleItems.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: columns == 2
                      ? 0.68
                      : columns == 3
                          ? 0.78
                          : 0.86,
                ),
                itemBuilder: (context, index) {
                  final item = visibleItems[index];
                  final cartQuantity = widget.cart[item.productId] ?? 0;
                  return _CatalogProductCard(
                    item: item,
                    cartQuantity: cartQuantity,
                    onAdd: widget.onAdd,
                    onShowDetails: widget.onShowDetails,
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

class _CatalogHomeHeader extends StatelessWidget {
  const _CatalogHomeHeader({
    required this.fulfillmentType,
    required this.onFulfillmentChanged,
  });

  final String fulfillmentType;
  final ValueChanged<String> onFulfillmentChanged;

  @override
  Widget build(BuildContext context) {
    return _FulfillmentToggle(
      value: fulfillmentType,
      onChanged: onFulfillmentChanged,
    );
  }
}

class _FulfillmentToggle extends StatelessWidget {
  const _FulfillmentToggle({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _FulfillmentSegment(
            value: 'delivery',
            groupValue: value,
            icon: Icons.delivery_dining_outlined,
            label: 'Delivery',
            onChanged: onChanged,
          ),
          _FulfillmentSegment(
            value: 'pickup',
            groupValue: value,
            icon: Icons.storefront_outlined,
            label: 'Pickup',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _FulfillmentSegment extends StatelessWidget {
  const _FulfillmentSegment({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.label,
    required this.onChanged,
  });

  final String value;
  final String groupValue;
  final IconData icon;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color:
                          selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogFilters extends StatelessWidget {
  const _CatalogFilters({
    required this.searchController,
    required this.stores,
    required this.selectedCategory,
    required this.selectedStoreId,
    required this.showAvailableOnly,
    required this.shownCount,
    required this.onSearchChanged,
    required this.onSelected,
    required this.onStoreSelected,
    required this.onAvailableOnlyChanged,
  });

  final TextEditingController searchController;
  final List<_CatalogStoreOption> stores;
  final String selectedCategory;
  final String selectedStoreId;
  final bool showAvailableOnly;
  final int shownCount;
  final VoidCallback onSearchChanged;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onStoreSelected;
  final ValueChanged<bool> onAvailableOnlyChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: searchController,
          textInputAction: TextInputAction.search,
          onChanged: (_) => onSearchChanged(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged();
                    },
                    icon: const Icon(Icons.close),
                  ),
            hintText: 'Search for food, convenience, African cuisine...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  avatar: const Icon(Icons.tune, size: 18),
                  label: const Text('Sort'),
                  onPressed: () {},
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('Open Now'),
                  selected: showAvailableOnly,
                  onSelected: onAvailableOnlyChanged,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: const Icon(Icons.star_outline, size: 18),
                  label: Text('$shownCount shown'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All stores'),
                  selected: selectedStoreId == 'all',
                  onSelected: (_) => onStoreSelected('all'),
                ),
              ),
              for (final store in stores)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(store.storeName),
                    selected: selectedStoreId == store.storeId,
                    onSelected: (_) => onStoreSelected(store.storeId),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HomeCategoryScroller extends StatelessWidget {
  const _HomeCategoryScroller({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final categoryId = index == 0 ? 'all' : categories[index - 1];
          final isSelected = selectedCategory == categoryId;
          final color = _categoryColor(categoryId);
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelected(isSelected ? 'all' : categoryId),
            child: SizedBox(
              width: 72,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      _categoryIcon(categoryId),
                      size: 20,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 18,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        categoryId == 'all' ? 'All' : _humanStatus(categoryId),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              height: 1,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CatalogProductCard extends StatelessWidget {
  const _CatalogProductCard({
    required this.item,
    required this.cartQuantity,
    required this.onAdd,
    required this.onShowDetails,
  });

  final CatalogItem item;
  final int cartQuantity;
  final ValueChanged<CatalogItem> onAdd;
  final ValueChanged<CatalogItem> onShowDetails;

  @override
  Widget build(BuildContext context) {
    final canAdd = item.isAvailable && cartQuantity < item.quantityAvailable;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => onShowDetails(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.34,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CatalogProductImage(imageUrl: item.imageUrl),
                  if (!item.isAvailable)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.36),
                      child: const Center(
                        child: _StatusPill(
                          label: 'Unavailable',
                          icon: Icons.block,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.storeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'NGN ${item.price.toStringAsFixed(0)}',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.isAvailable ? 'Available' : 'Unavailable',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: item.isAvailable
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: canAdd ? 'Add to cart' : 'Unavailable',
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 34,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: canAdd ? () => onAdd(item) : null,
                        icon: Icon(
                          cartQuantity == 0
                              ? Icons.add_shopping_cart
                              : Icons.shopping_cart_checkout,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductDetailPage extends StatefulWidget {
  const _ProductDetailPage({
    required this.item,
    required this.cartQuantity,
    required this.reviewsStream,
    required this.onAdd,
  });

  final CatalogItem item;
  final int cartQuantity;
  final Stream<List<ProductReviewSummary>> reviewsStream;
  final ValueChanged<CatalogItem> onAdd;

  @override
  State<_ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<_ProductDetailPage> {
  late var _cartQuantity = widget.cartQuantity;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final canAdd = item.isAvailable && _cartQuantity < item.quantityAvailable;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product details'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 1.16,
              child: _CatalogProductImage(imageUrl: item.imageUrl),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.storeName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'NGN ${item.price.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(_categoryIcon(item.category)),
                label: Text(_humanStatus(item.category)),
              ),
              Chip(
                avatar: Icon(
                  item.isAvailable
                      ? Icons.check_circle_outline
                      : Icons.block_outlined,
                  color: item.isAvailable ? scheme.primary : scheme.error,
                ),
                label: Text(
                  item.isAvailable ? 'Available' : 'Unavailable',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'About this item',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            item.description.trim().isEmpty
                ? 'No extra product details yet.'
                : item.description.trim(),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 20),
          _ProductReviewsSection(reviewsStream: widget.reviewsStream),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: canAdd
              ? () {
                  widget.onAdd(item);
                  setState(() => _cartQuantity += 1);
                }
              : null,
          icon: const Icon(Icons.add_shopping_cart),
          label: Text(
            item.isAvailable
                ? _cartQuantity == 0
                    ? 'Add to cart'
                    : '$_cartQuantity in cart'
                : 'Unavailable',
          ),
        ),
      ),
    );
  }
}

class _ProductReviewsSection extends StatelessWidget {
  const _ProductReviewsSection({required this.reviewsStream});

  final Stream<List<ProductReviewSummary>> reviewsStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProductReviewSummary>>(
      stream: reviewsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ReviewPanel(
            title: 'Item reviews',
            subtitle: 'Reviews are temporarily unavailable.',
            child: Text(
              snapshot.error.toString(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }

        final reviews = snapshot.data ?? const <ProductReviewSummary>[];
        if (reviews.isEmpty) {
          return const _ReviewPanel(
            title: 'Item reviews',
            subtitle: 'No item reviews yet.',
          );
        }

        final average =
            reviews.fold<int>(0, (sum, review) => sum + review.rating) /
                reviews.length;
        return _ReviewPanel(
          title: '${average.toStringAsFixed(1)}/5',
          subtitle:
              '${reviews.length} item review${reviews.length == 1 ? '' : 's'}',
          child: Column(
            children: [
              for (final review in reviews.take(10))
                _ProductReviewCard(review: review),
            ],
          ),
        );
      },
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.title,
    required this.subtitle,
    this.child,
  });

  final String title;
  final String subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.star,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (child != null) ...[
              const SizedBox(height: 12),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductReviewCard extends StatelessWidget {
  const _ProductReviewCard({required this.review});

  final ProductReviewSummary review;

  @override
  Widget build(BuildContext context) {
    final customerName = review.customerName?.trim();
    final comment = review.comment?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      customerName == null || customerName.isEmpty
                          ? 'Customer'
                          : customerName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Text(_stars(review.rating)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _formatDateTime(review.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (comment != null && comment.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(comment),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogProductImage extends StatelessWidget {
  const _CatalogProductImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.fastfood_outlined,
        size: 42,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    if (url == null || url.isEmpty) {
      return fallback;
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: 600,
      cacheHeight: 600,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _CartPane extends StatelessWidget {
  const _CartPane({
    required this.fulfillmentType,
    required this.cart,
    required this.catalogByProductId,
    required this.addresses,
    required this.selectedAddressId,
    required this.selectedDeliveryAddress,
    required this.addressError,
    required this.isAddressLoading,
    required this.isSavingAddress,
    required this.isUpdatingAddress,
    required this.addressController,
    required this.promoCodeController,
    required this.promoQuote,
    required this.checkoutQuote,
    required this.isSubmitting,
    required this.isApplyingPromo,
    required this.isQuotingCheckout,
    required this.showTitle,
    required this.onShowDetails,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onClearCart,
    required this.onSelectAddress,
    required this.onSaveAddress,
    required this.onSetDefaultAddress,
    required this.onDeleteAddress,
    required this.onManageAddresses,
    required this.onApplyPromo,
    required this.onClearPromo,
    required this.onPlaceOrder,
  });

  final String fulfillmentType;
  final Map<String, int> cart;
  final Map<String, CatalogItem> catalogByProductId;
  final List<CustomerAddress> addresses;
  final String? selectedAddressId;
  final CustomerAddress? selectedDeliveryAddress;
  final Object? addressError;
  final bool isAddressLoading;
  final bool isSavingAddress;
  final bool isUpdatingAddress;
  final TextEditingController addressController;
  final TextEditingController promoCodeController;
  final PromoQuote? promoQuote;
  final CheckoutQuote? checkoutQuote;
  final bool isSubmitting;
  final bool isApplyingPromo;
  final bool isQuotingCheckout;
  final bool showTitle;
  final ValueChanged<CatalogItem> onShowDetails;
  final ValueChanged<String> onIncrease;
  final ValueChanged<String> onDecrease;
  final ValueChanged<String> onRemove;
  final VoidCallback onClearCart;
  final ValueChanged<CustomerAddress> onSelectAddress;
  final VoidCallback onSaveAddress;
  final ValueChanged<CustomerAddress> onSetDefaultAddress;
  final ValueChanged<CustomerAddress> onDeleteAddress;
  final VoidCallback onManageAddresses;
  final VoidCallback onApplyPromo;
  final VoidCallback onClearPromo;
  final VoidCallback? onPlaceOrder;

  @override
  Widget build(BuildContext context) {
    final entries = cart.entries
        .map((entry) {
          final item = catalogByProductId[entry.key];
          return item == null ? null : MapEntry(item, entry.value);
        })
        .whereType<MapEntry<CatalogItem, int>>()
        .toList();
    final subtotal = entries.fold<double>(
      0,
      (sum, entry) => sum + (entry.key.price * entry.value),
    );
    final quote = checkoutQuote;
    final discount = quote?.discountAmount ??
        (promoQuote?.isValid == true ? promoQuote!.discountAmount : 0.0);
    final deliveryFee = quote?.deliveryFee ?? 0.0;
    final serviceFee = quote?.serviceFee ?? 0.0;
    final payableTotal =
        quote?.totalAmount ?? (subtotal - discount).clamp(0, subtotal);

    return ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      children: [
        if (showTitle) ...[
          Text('Cart', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
        ],
        if (cart.isEmpty)
          const Text('Your cart is empty')
        else ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: isSubmitting ? null : onClearCart,
              icon: const Icon(Icons.remove_shopping_cart_outlined),
              label: const Text('Clear cart'),
            ),
          ),
          const SizedBox(height: 4),
          for (final entry in entries)
            Card(
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: isSubmitting ? null : () => onShowDetails(entry.key),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.key.name),
                            const SizedBox(height: 2),
                            Text(
                              'NGN ${entry.key.price.toStringAsFixed(2)} | '
                              '${_availabilityLabel(entry.key.isAvailable)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reduce quantity',
                        onPressed: isSubmitting
                            ? null
                            : () => onDecrease(entry.key.productId),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          entry.value.toString(),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Increase quantity',
                        onPressed: isSubmitting ||
                                entry.value >= entry.key.quantityAvailable
                            ? null
                            : () => onIncrease(entry.key.productId),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      IconButton(
                        tooltip: 'Remove item',
                        onPressed: isSubmitting
                            ? null
                            : () => onRemove(entry.key.productId),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Items NGN ${subtotal.toStringAsFixed(2)}'),
                if (discount > 0)
                  Text('Discount -NGN ${discount.toStringAsFixed(2)}'),
                if (quote != null) ...[
                  Text(
                    fulfillmentType == 'pickup'
                        ? 'Pickup NGN 0.00'
                        : 'Delivery NGN ${deliveryFee.toStringAsFixed(2)}',
                  ),
                  Text('Service NGN ${serviceFee.toStringAsFixed(2)}'),
                ],
                if (isQuotingCheckout)
                  Text(
                    'Updating fees...',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Text(
                  'Total NGN ${payableTotal.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: promoCodeController,
                  enabled: !isSubmitting && !isApplyingPromo,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Promo code',
                    border: const OutlineInputBorder(),
                    helperText: promoQuote?.message,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Apply promo',
                onPressed: isSubmitting || isApplyingPromo || entries.isEmpty
                    ? null
                    : onApplyPromo,
                icon: isApplyingPromo
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.local_offer_outlined),
              ),
              IconButton(
                tooltip: 'Clear promo',
                onPressed:
                    isSubmitting || isApplyingPromo ? null : onClearPromo,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (fulfillmentType == 'pickup')
          const Card(
            child: ListTile(
              leading: Icon(Icons.storefront_outlined),
              title: Text('Pickup order'),
              subtitle: Text(
                'The store will prepare this for pickup and no delivery fee will be charged.',
              ),
            ),
          )
        else ...[
          if (selectedDeliveryAddress != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(selectedDeliveryAddress!.label),
                subtitle: Text(
                  selectedDeliveryAddress!.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: isSubmitting ? null : onManageAddresses,
                  child: const Text('Change'),
                ),
              ),
            )
          else ...[
            _AddressBookSection(
              addresses: addresses,
              selectedAddressId: selectedAddressId,
              error: addressError,
              isLoading: isAddressLoading,
              isUpdating: isUpdatingAddress,
              onSelectAddress: onSelectAddress,
              onSetDefaultAddress: onSetDefaultAddress,
              onDeleteAddress: onDeleteAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              enabled: !isSubmitting,
              decoration: const InputDecoration(
                labelText: 'Delivery address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isSubmitting || isSavingAddress ? null : onSaveAddress,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(isSavingAddress ? 'Saving...' : 'Save address'),
            ),
          ],
        ],
        const SizedBox(height: 8),
        FilledButton(
          onPressed: onPlaceOrder,
          child: Text(
              isSubmitting ? 'Creating checkout...' : 'Place order and pay'),
        ),
      ],
    );
  }
}

String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

List<_CustomerOrderFilter> _customerOrderFilters(bool showActive) {
  if (showActive) {
    return const [
      _CustomerOrderFilter('all', 'All', Icons.all_inbox_outlined),
      _CustomerOrderFilter('pending', 'Payment pending', Icons.payment),
      _CustomerOrderFilter('paid', 'New', Icons.receipt_long_outlined),
      _CustomerOrderFilter('accepted', 'Accepted', Icons.task_alt_outlined),
      _CustomerOrderFilter('preparing', 'Preparing', Icons.restaurant),
      _CustomerOrderFilter('ready_for_pickup', 'Ready', Icons.inventory_2),
      _CustomerOrderFilter(
        'out_for_delivery',
        'With rider',
        Icons.delivery_dining,
      ),
    ];
  }
  return const [
    _CustomerOrderFilter('all', 'All', Icons.history),
    _CustomerOrderFilter('delivered', 'Fulfilled', Icons.done_all),
    _CustomerOrderFilter('cancelled', 'Cancelled', Icons.cancel_outlined),
    _CustomerOrderFilter('failed', 'Failed payment', Icons.error_outline),
    _CustomerOrderFilter('expired', 'Expired', Icons.timer_off_outlined),
    _CustomerOrderFilter('refunded', 'Refunded', Icons.undo_outlined),
  ];
}

bool _matchesCustomerOrderFilter(OrderSummary order, String filter) {
  return switch (filter) {
    'pending' => order.paymentStatus == 'pending',
    'failed' => order.paymentStatus == 'failed',
    'expired' => order.paymentStatus == 'expired' || order.status == 'expired',
    'refunded' => order.paymentStatus == 'refunded',
    'fulfilled' || 'delivered' => order.status == 'delivered',
    'cancelled' => order.status == 'cancelled',
    'paid' => order.status == 'paid' && order.paymentStatus == 'paid',
    'accepted' => order.status == 'accepted',
    'preparing' => order.status == 'preparing',
    'ready_for_pickup' => order.status == 'ready_for_pickup',
    'out_for_delivery' =>
      order.status == 'out_for_delivery' || order.status == 'picked_up',
    'all' => true,
    _ => true,
  };
}

String _customerOrderFilterLabel(String value) {
  return switch (value) {
    'pending' => 'Payment pending',
    'paid' => 'New',
    'accepted' => 'Accepted',
    'preparing' => 'Preparing',
    'ready_for_pickup' => 'Ready',
    'out_for_delivery' => 'With rider',
    'fulfilled' || 'delivered' => 'Fulfilled',
    'cancelled' => 'Cancelled',
    'failed' => 'Failed payment',
    'expired' => 'Expired',
    'refunded' => 'Refunded',
    _ => 'All',
  };
}

String _customerOrderStatusLabel(OrderSummary order) {
  if (order.paymentStatus == 'pending') {
    return 'Pending';
  }
  if (order.paymentStatus == 'failed') {
    return 'Failed';
  }
  if (order.paymentStatus == 'expired') {
    return 'Expired';
  }
  if (order.paymentStatus == 'refunded') {
    return 'Refunded';
  }
  if (order.status == 'delivered') {
    return 'Delivered';
  }
  if (order.status == 'ready_for_pickup') {
    return 'Ready';
  }
  if (order.status == 'out_for_delivery' || order.status == 'picked_up') {
    return 'With rider';
  }
  return _humanStatus(order.status);
}

Color _customerOrderStatusColor(OrderSummary order) {
  if (order.paymentStatus == 'pending') {
    return const Color(0xffb45309);
  }
  if (order.paymentStatus == 'failed' ||
      order.paymentStatus == 'expired' ||
      order.status == 'cancelled') {
    return const Color(0xffdc2626);
  }
  if (order.paymentStatus == 'refunded') {
    return const Color(0xff2563eb);
  }
  if (order.status == 'delivered') {
    return const Color(0xff0f8f76);
  }
  if (order.status == 'out_for_delivery' || order.status == 'picked_up') {
    return const Color(0xff2563eb);
  }
  return const Color(0xff16a34a);
}

String _orderItemSummary(List<OrderLineItem> items) {
  if (items.isEmpty) {
    return 'Items loading';
  }
  return items
      .take(2)
      .map((item) => '${item.quantity} x ${item.productName}')
      .join(', ');
}

String? _orderPreviewImageUrl(
  List<OrderLineItem> items,
  Map<String, CatalogItem> catalogByProductId,
) {
  for (final item in items) {
    final catalogItem = catalogByProductId[item.productId];
    final urls = catalogItem?.imageUrls ?? const <String>[];
    if (urls.isNotEmpty) {
      return urls.first;
    }
    final imageUrl = catalogItem?.imageUrl;
    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      return imageUrl;
    }
  }
  return null;
}

String _storeInitials(String storeName) {
  final words = storeName
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return 'L';
  }
  if (words.length == 1) {
    final word = words.first;
    return word.substring(0, word.length < 2 ? word.length : 2).toUpperCase();
  }
  return '${words.first[0]}${words[1][0]}'.toUpperCase();
}

List<String> _catalogCategories(List<CatalogItem> items) {
  final categories = items
      .map((item) => item.category.trim().isEmpty ? 'general' : item.category)
      .toSet()
      .toList()
    ..sort((a, b) {
      final priority = _homeCategoryPriority(a).compareTo(
        _homeCategoryPriority(b),
      );
      if (priority != 0) {
        return priority;
      }
      return _humanStatus(a).compareTo(_humanStatus(b));
    });
  return categories;
}

class _RestaurantCategory {
  const _RestaurantCategory(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}

const _restaurantCategories = [
  _RestaurantCategory('all', 'All', Icons.apps_outlined),
  _RestaurantCategory('promotions', 'Promos', Icons.local_offer_outlined),
  _RestaurantCategory('bread', 'Bread', Icons.bakery_dining_outlined),
  _RestaurantCategory('chicken', 'Chicken', Icons.dinner_dining_outlined),
  _RestaurantCategory('beef', 'Beef', Icons.restaurant_menu),
  _RestaurantCategory('swallow', 'Swallow', Icons.rice_bowl_outlined),
  _RestaurantCategory('soup', 'Soup', Icons.ramen_dining),
  _RestaurantCategory('shawarma', 'Shawarma', Icons.lunch_dining_outlined),
  _RestaurantCategory('burgers', 'Burgers', Icons.lunch_dining),
];

const _restaurantStoreCategories = {
  'restaurant',
  'restaurants',
  'food',
  'foods',
  'eatery',
  'cafe',
  'coffee',
  'fast_food',
  'shawarma',
  'pizza',
  'bakery',
  'kitchen',
};

const _marketStoreCategories = {
  'grocery',
  'groceries',
  'store',
  'stores',
  'market',
  'supermarket',
  'convenience',
  'pharmacy',
  'retail',
};

const _restaurantProductCategories = {
  'african_cuisine',
  'bakery',
  'bread',
  'burger',
  'burgers',
  'chicken',
  'coffee_and_tea',
  'fast_food',
  'pizza',
  'protein',
  'rice',
  'shawarma',
  'soup',
  'swallow',
};

bool _isRestaurantStore(List<CatalogItem> storeItems) {
  if (storeItems.isEmpty) {
    return false;
  }

  final storeCategory = storeItems.first.storeCategory.trim().toLowerCase();
  if (_restaurantStoreCategories.contains(storeCategory)) {
    return true;
  }
  if (_marketStoreCategories.contains(storeCategory)) {
    return false;
  }

  return storeItems.any(
    (item) => _restaurantProductCategories.contains(
      item.category.trim().toLowerCase(),
    ),
  );
}

List<MapEntry<String, List<CatalogItem>>> _favoriteRestaurantStores(
  List<CatalogItem> items,
  Set<String> favoriteStoreIds,
) {
  if (favoriteStoreIds.isEmpty) {
    return const [];
  }

  final stores = _restaurantStores(items)
      .where((store) => favoriteStoreIds.contains(store.key))
      .toList();
  stores.sort(
    (a, b) => a.value.first.storeName.compareTo(b.value.first.storeName),
  );
  return stores;
}

List<MapEntry<String, List<CatalogItem>>> _restaurantStores(
  List<CatalogItem> items,
) {
  final byStore = <String, List<CatalogItem>>{};
  for (final item in items) {
    byStore.putIfAbsent(item.storeId, () => []).add(item);
  }
  return byStore.entries.toList()
    ..sort(
      (a, b) => a.value.first.storeName.compareTo(b.value.first.storeName),
    );
}

List<MapEntry<String, List<CatalogItem>>> _orderAgainStores(
  List<MapEntry<String, List<CatalogItem>>> stores,
  List<OrderSummary> orders,
) {
  final storesById = {for (final store in stores) store.key: store};
  final deliveredOrders = orders
      .where(
        (order) =>
            order.status == 'delivered' &&
            order.paymentStatus == 'paid' &&
            storesById.containsKey(order.storeId),
      )
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final seen = <String>{};
  final orderedStores = <MapEntry<String, List<CatalogItem>>>[];
  for (final order in deliveredOrders) {
    if (seen.add(order.storeId)) {
      orderedStores.add(storesById[order.storeId]!);
    }
  }
  return orderedStores;
}

List<PromoCodeSummary> _activePromoCodes(List<PromoCodeSummary> promos) {
  final now = DateTime.now();
  return promos
      .where(
        (promo) =>
            promo.isActive &&
            promo.storeId != null &&
            (promo.startsAt == null || !promo.startsAt!.isAfter(now)) &&
            (promo.endsAt == null || promo.endsAt!.isAfter(now)) &&
            (promo.maxRedemptions == null ||
                promo.redemptionCount < promo.maxRedemptions!),
      )
      .toList();
}

String _promoBadgeLabel(PromoCodeSummary promo) {
  if (promo.discountType == 'percentage') {
    return '-${promo.discountValue.toStringAsFixed(0)}% some items';
  }
  return '-${_formatNaira(promo.discountValue)}';
}

bool _matchesRestaurantSearch(
  List<CatalogItem> storeItems,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }

  final first = storeItems.first;
  return first.storeName.toLowerCase().contains(normalized) ||
      storeItems.any(
        (item) =>
            item.name.toLowerCase().contains(normalized) ||
            item.description.toLowerCase().contains(normalized) ||
            item.category.toLowerCase().contains(normalized) ||
            _humanStatus(item.category).toLowerCase().contains(normalized),
      );
}

bool _matchesRestaurantCategory(
  List<CatalogItem> storeItems,
  String category,
  bool hasDeal,
) {
  final normalized = category.trim().toLowerCase();
  if (normalized == 'all') {
    return true;
  }
  if (normalized == 'promotions') {
    return hasDeal;
  }

  return storeItems.any((item) {
    final haystack =
        '${item.category} ${_humanStatus(item.category)} ${item.name} ${item.description}'
            .toLowerCase();
    return switch (normalized) {
      'bread' => haystack.contains('bread') ||
          haystack.contains('bakery') ||
          haystack.contains('buns'),
      'chicken' => haystack.contains('chicken') ||
          haystack.contains('wings') ||
          haystack.contains('poultry'),
      'beef' => haystack.contains('beef') ||
          haystack.contains('suya') ||
          haystack.contains('meat'),
      'swallow' => haystack.contains('swallow') ||
          haystack.contains('eba') ||
          haystack.contains('amala') ||
          haystack.contains('fufu') ||
          haystack.contains('semo'),
      'soup' => haystack.contains('soup') ||
          haystack.contains('egusi') ||
          haystack.contains('okra') ||
          haystack.contains('ogbono'),
      'shawarma' => haystack.contains('shawarma') || haystack.contains('wrap'),
      'burgers' => haystack.contains('burger'),
      _ => haystack.contains(normalized),
    };
  });
}

List<MapEntry<String, List<CatalogItem>>> _sortRestaurantStores(
  List<MapEntry<String, List<CatalogItem>>> stores,
  String sortMode,
  CustomerAddress? selectedAddress,
) {
  final sorted = [...stores];
  sorted.sort((a, b) {
    final firstA = a.value.first;
    final firstB = b.value.first;
    if (sortMode == 'price') {
      final distanceA = _storeDistanceFromAddress(firstA, selectedAddress);
      final distanceB = _storeDistanceFromAddress(firstB, selectedAddress);
      final feeA =
          distanceA == null ? double.infinity : _fuelDeliveryCost(distanceA);
      final feeB =
          distanceB == null ? double.infinity : _fuelDeliveryCost(distanceB);
      final priceSort = feeA.compareTo(feeB);
      if (priceSort != 0) {
        return priceSort;
      }
    } else if (sortMode == 'distance') {
      final distanceA =
          _storeDistanceFromAddress(firstA, selectedAddress) ?? double.infinity;
      final distanceB =
          _storeDistanceFromAddress(firstB, selectedAddress) ?? double.infinity;
      final distanceSort = distanceA.compareTo(distanceB);
      if (distanceSort != 0) {
        return distanceSort;
      }
    }
    return firstA.storeName.compareTo(firstB.storeName);
  });
  return sorted;
}

String _restaurantSortLabel(String value) {
  return switch (value) {
    'price' => 'price',
    'distance' => 'distance',
    _ => 'recommended',
  };
}

IconData _categoryIcon(String category) {
  switch (category.trim().toLowerCase()) {
    case 'all':
      return Icons.apps_outlined;
    case 'dairy':
      return Icons.local_drink_outlined;
    case 'pantry':
      return Icons.kitchen_outlined;
    case 'snacks':
      return Icons.cookie_outlined;
    case 'cooking_oil':
      return Icons.oil_barrel_outlined;
    case 'grocery':
    case 'grocery bundle':
      return Icons.local_grocery_store_outlined;
    case 'fresh produce':
      return Icons.eco_outlined;
    case 'african_cuisine':
    case 'rice':
      return Icons.rice_bowl_outlined;
    case 'protein':
      return Icons.set_meal_outlined;
    case 'pizza':
      return Icons.local_pizza_outlined;
    case 'fast_food':
      return Icons.fastfood_outlined;
    case 'coffee_and_tea':
      return Icons.local_cafe_outlined;
    default:
      return Icons.category_outlined;
  }
}

Color _categoryColor(String category) {
  switch (category.trim().toLowerCase()) {
    case 'all':
      return const Color(0xff0b72ff);
    case 'dairy':
      return const Color(0xff0b72ff);
    case 'pantry':
      return const Color(0xfff2a91f);
    case 'snacks':
      return const Color(0xff9a61ff);
    case 'cooking_oil':
      return const Color(0xffe94f37);
    case 'grocery':
    case 'grocery bundle':
      return const Color(0xff18a957);
    case 'fresh produce':
      return const Color(0xff22a06b);
    case 'african_cuisine':
    case 'rice':
      return const Color(0xff00a6a6);
    case 'protein':
      return const Color(0xffd9480f);
    default:
      return const Color(0xff64748b);
  }
}

List<_CatalogStoreOption> _catalogStores(List<CatalogItem> items) {
  final byStoreId = <String, String>{};
  for (final item in items) {
    byStoreId[item.storeId] = item.storeName;
  }

  final stores = byStoreId.entries
      .map(
        (entry) => _CatalogStoreOption(
          storeId: entry.key,
          storeName: entry.value,
        ),
      )
      .toList()
    ..sort((a, b) => a.storeName.compareTo(b.storeName));
  return stores;
}

bool _matchesCatalogSearch(CatalogItem item, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }

  return item.name.toLowerCase().contains(normalized) ||
      item.description.toLowerCase().contains(normalized) ||
      item.storeName.toLowerCase().contains(normalized) ||
      item.category.toLowerCase().contains(normalized) ||
      _humanStatus(item.category).toLowerCase().contains(normalized);
}

int _compareHomeCatalogItems(CatalogItem a, CatalogItem b) {
  final categoryPriority = _homeCategoryPriority(a.category)
      .compareTo(_homeCategoryPriority(b.category));
  if (categoryPriority != 0) {
    return categoryPriority;
  }

  final availabilityPriority =
      (b.isAvailable ? 1 : 0).compareTo(a.isAvailable ? 1 : 0);
  if (availabilityPriority != 0) {
    return availabilityPriority;
  }

  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

int _homeCategoryPriority(String category) {
  switch (category.trim().toLowerCase()) {
    case 'dairy':
      return 0;
    case 'pantry':
      return 1;
    case 'snacks':
      return 2;
    case 'cooking_oil':
      return 3;
    case 'grocery':
    case 'grocery bundle':
    case 'fresh produce':
      return 4;
    case 'african_cuisine':
    case 'rice':
    case 'protein':
      return 5;
    default:
      return 6;
  }
}

CustomerAddress? _preferredAddress(List<CustomerAddress> addresses) {
  if (addresses.isEmpty) {
    return null;
  }

  for (final address in addresses) {
    if (address.isDefault) {
      return address;
    }
  }

  return addresses.first;
}

CustomerAddress? _findAddressById(
  List<CustomerAddress> addresses,
  String? id,
) {
  if (id == null) {
    return null;
  }

  for (final address in addresses) {
    if (address.id == id) {
      return address;
    }
  }

  return null;
}

bool _isPaymentReturnUri(Uri uri) {
  if (uri.scheme == 'luumoh' && uri.host == 'payment-return') {
    return true;
  }

  return uri.pathSegments.contains('payment-return');
}

String? _paymentReturnOrderId(Uri uri) {
  return uri.queryParameters['orderId'] ??
      uri.queryParameters['order_id'] ??
      uri.queryParameters['order'];
}

String? _paymentReturnReference(Uri uri) {
  return uri.queryParameters['paymentReference'] ??
      uri.queryParameters['payment_reference'] ??
      uri.queryParameters['transactionReference'] ??
      uri.queryParameters['transaction_reference'];
}

bool _isTerminalPaymentStatus(String status) {
  return status == 'paid' ||
      status == 'failed' ||
      status == 'expired' ||
      status == 'refunded';
}

bool _isActiveCustomerOrder(OrderSummary order) {
  const terminalStatuses = {
    'delivered',
    'completed',
    'cancelled',
    'declined',
    'rejected',
    'expired',
    'failed',
  };
  if (terminalStatuses.contains(order.status)) {
    return false;
  }
  if (order.paymentStatus == 'pending') {
    return true;
  }
  if (order.paymentStatus != 'paid') {
    return false;
  }
  return true;
}

int _trackingStageForOrder(OrderSummary order) {
  if (order.paymentStatus == 'pending') {
    return 0;
  }
  return switch (order.status) {
    'paid' => 0,
    'accepted' || 'assigned' => 1,
    'preparing' => 2,
    'ready_for_pickup' || 'picked_up' => 3,
    'out_for_delivery' => 4,
    'delivered' => 4,
    _ => order.paymentStatus == 'paid' ? 1 : 0,
  };
}

String _trackingStageTitle(OrderSummary order) {
  if (order.paymentStatus == 'pending') {
    return 'Checkout is waiting for payment';
  }
  return switch (order.status) {
    'paid' => 'Store is confirming your order',
    'accepted' || 'assigned' => 'Store accepted your order',
    'preparing' => 'Store is preparing your items',
    'ready_for_pickup' => order.riderId == null
        ? 'Looking for a rider'
        : 'Rider is heading to the store',
    'picked_up' || 'out_for_delivery' => 'Rider is on route to you',
    _ => _humanStatus(order.status),
  };
}

bool _shouldShowRiderTracking(OrderSummary order) {
  if (!_isActiveCustomerOrder(order) || order.paymentStatus != 'paid') {
    return false;
  }

  return switch (order.status) {
    'assigned' ||
    'accepted' ||
    'preparing' ||
    'ready_for_pickup' ||
    'picked_up' ||
    'out_for_delivery' =>
      true,
    _ => false,
  };
}

bool _isOrderEtaLate(OrderSummary order) {
  if (order.status == 'delivered' || order.status == 'cancelled') {
    return false;
  }
  final etaMinutes = order.etaMinutes;
  final etaUpdatedAt = order.etaUpdatedAt;
  if (etaMinutes == null || etaUpdatedAt == null) {
    return false;
  }
  return DateTime.now().isAfter(
    etaUpdatedAt.toLocal().add(Duration(minutes: etaMinutes)),
  );
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month ${_formatTime(local)}';
}
