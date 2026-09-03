import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:luumoh_core/luumoh_core.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

part 'features/notifications/notifications_sheet.dart';
part 'features/orders/orders_feature.dart';
part 'features/delivery/lifecycle_feature.dart';
part 'features/map/rider_map_feature.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(RiderApp(environment: AppEnvironment.fromDartDefines()));
}

class RiderApp extends StatelessWidget {
  const RiderApp({required this.environment, super.key});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Luumoh Rider',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1d4ed8)),
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
            title: 'Starting Luumoh Rider',
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

        return _RiderAuthGate(environment: widget.environment);
      },
    );
  }
}

class _RiderAuthGate extends StatelessWidget {
  const _RiderAuthGate({required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session == null) {
          return const _RiderSignInPage();
        }

        return RiderHomePage(
          userEmail: session.user.email ?? 'Rider',
          mapboxAccessToken: environment.mapboxAccessToken,
        );
      },
    );
  }
}

class _RiderSignInPage extends StatefulWidget {
  const _RiderSignInPage();

  @override
  State<_RiderSignInPage> createState() => _RiderSignInPageState();
}

class _RiderSignInPageState extends State<_RiderSignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Sign in failed: $error')));
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
        SnackBar(content: Text('Password reset failed: $error')),
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
                    Text(
                      'Rider sign in',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use a rider account to accept pickup-ready orders.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
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
                      onFieldSubmitted: (_) => _isSubmitting ? null : _signIn(),
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
                    FilledButton.icon(
                      onPressed: _isSubmitting ? null : _signIn,
                      icon: const Icon(Icons.login),
                      label: Text(_isSubmitting ? 'Signing in...' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isSubmitting ? null : _sendPasswordReset,
                      child: const Text('Forgot password?'),
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

class RiderHomePage extends StatefulWidget {
  const RiderHomePage({
    required this.userEmail,
    required this.mapboxAccessToken,
    super.key,
  });

  final String userEmail;
  final String mapboxAccessToken;

  @override
  State<RiderHomePage> createState() => _RiderHomePageState();
}

class _RiderHomePageState extends State<RiderHomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final PlatformRepository _repository;
  late final MapboxLocationService _mapboxLocation;
  bool _isUpdatingAvailability = false;
  Timer? _locationTimer;
  String? _liveLocationOrderId;
  final Set<String> _sharingLocationOrderIds = {};

  @override
  void initState() {
    super.initState();
    _repository = PlatformRepository(Supabase.instance.client);
    _mapboxLocation = MapboxLocationService(widget.mapboxAccessToken);
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  void _pushRiderPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _openProfilePage() {
    _pushRiderPage(
      _RiderAccountPage(
        repository: _repository,
        userEmail: widget.userEmail,
      ),
    );
  }

  void _openNotifications() {
    _pushRiderPage(
      _RiderStandalonePage(
        title: 'Notifications',
        child: _NotificationsSheet(
          repository: _repository,
          audience: 'rider',
          embedded: true,
        ),
      ),
    );
  }

  void _openWallet() {
    _pushRiderPage(
      _RiderStandalonePage(
        title: 'Wallet',
        child: _RiderSettlementsPane(repository: _repository),
      ),
    );
  }

  void _openRecentOrders() {
    _pushRiderPage(
      _RiderStandalonePage(
        title: 'Orders',
        child: _RiderOrdersPane(
          repository: _repository,
          onUpdateEta: _updateEta,
          onOutForDelivery: _markOutForDelivery,
          onDelivered: _markDelivered,
          onShareLocation: _shareLocation,
          onToggleLiveLocation: _toggleLiveLocation,
          onNavigate: _openNavigation,
          onCallCustomer: _callCustomer,
          onMessageCustomer: _messageCustomer,
          liveLocationOrderId: _liveLocationOrderId,
          sharingLocationOrderIds: _sharingLocationOrderIds,
        ),
      ),
    );
  }

  void _openHelp() {
    _pushRiderPage(
      const _RiderStandalonePage(
        title: 'Get help',
        child: _RiderHelpSheet(embedded: true),
      ),
    );
  }

  void _openMenu() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _accept(OrderSummary order) async {
    final messenger = ScaffoldMessenger.of(context);
    final eta = order.etaMinutes ?? 25;
    try {
      await _repository.acceptOrder(
        orderId: order.id,
        etaMinutes: eta,
        note: 'Rider accepted pickup and is heading to store',
      );
      await _shareLocation(order, silent: true);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Order accepted. Head to ${order.storeName}.')),
      );
      await _openNavigation(order, _RiderRouteTarget.store);
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Accept failed: $error')),
      );
    }
  }

  Future<void> _decline(OrderSummary order) async {
    final shouldDecline = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline order?'),
        content: Text(
          'This will release order #${_shortId(order.id)} for another rider.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (shouldDecline != true || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.declineOrder(
        orderId: order.id,
        note: 'Rider declined pickup offer',
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Order declined')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Decline failed: $error')),
      );
    }
  }

  Future<void> _setAvailability(bool isOnline) async {
    setState(() => _isUpdatingAvailability = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.setRiderAvailability(isOnline);
      messenger.showSnackBar(
        SnackBar(
            content: Text(isOnline ? 'You are online' : 'You are offline')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Availability update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAvailability = false);
      }
    }
  }

  Future<void> _updateEta(OrderSummary order) async {
    final eta = await showDialog<int>(
      context: context,
      builder: (context) => _EtaDialog(
        title: 'Update ETA',
        initialEta: order.etaMinutes ?? 20,
      ),
    );

    if (eta == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.updateEta(
        orderId: order.id,
        etaMinutes: eta,
        note: 'Rider updated ETA',
      );
      messenger.showSnackBar(
        SnackBar(content: Text('ETA updated to ${eta}m')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('ETA update failed: $error')),
      );
    }
  }

  Future<void> _markDelivered(OrderSummary order) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.updateRiderOrderStatus(
        orderId: order.id,
        status: 'delivered',
        note: 'Delivered to customer',
      );
      if (_liveLocationOrderId == order.id) {
        _stopLiveLocation();
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Delivery complete')),
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Color(0xff16a34a)),
          title: const Text('Delivery successful'),
          content: Text(
            'Order #${_shortId(order.id)} has been added to recent deliveries.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Delivery update failed: $error')),
      );
    }
  }

  Future<Position> _currentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('Location services are disabled on this device.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
          'Location permission is required to share live tracking.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  Future<void> _shareLocation(OrderSummary order, {bool silent = false}) async {
    setState(() => _sharingLocationOrderIds.add(order.id));
    final messenger = ScaffoldMessenger.of(context);

    try {
      final position = await _currentPosition();
      await _repository.updateRiderLocation(
        orderId: order.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        heading: position.heading.isNaN ? null : position.heading,
        speedMps: position.speed.isNaN ? null : position.speed,
        note: silent ? 'Live rider location update' : 'Rider shared location',
      );

      if (!silent) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Location shared')),
        );
      }
    } on Object catch (error) {
      if (_liveLocationOrderId == order.id) {
        _stopLiveLocation();
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Location update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _sharingLocationOrderIds.remove(order.id));
      }
    }
  }

  void _stopLiveLocation() {
    _locationTimer?.cancel();
    _locationTimer = null;
    if (mounted) {
      setState(() => _liveLocationOrderId = null);
    } else {
      _liveLocationOrderId = null;
    }
  }

  Future<void> _toggleLiveLocation(OrderSummary order) async {
    if (_liveLocationOrderId == order.id) {
      _stopLiveLocation();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live location stopped')),
      );
      return;
    }

    _locationTimer?.cancel();
    setState(() => _liveLocationOrderId = order.id);
    await _shareLocation(order, silent: true);
    if (!mounted || _liveLocationOrderId != order.id) {
      return;
    }

    _locationTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_shareLocation(order, silent: true)),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Live location started')),
    );
  }

  Future<void> _markOutForDelivery(OrderSummary order) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.updateRiderOrderStatus(
        orderId: order.id,
        status: 'out_for_delivery',
        note: 'Rider confirmed pickup',
      );
      await _shareLocation(order, silent: true);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Pickup confirmed. Navigate to customer.')),
      );
      await _openNavigation(order, _RiderRouteTarget.customer);
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Pickup update failed: $error')),
      );
    }
  }

  Future<void> _openNavigation(
      OrderSummary order, _RiderRouteTarget target) async {
    final destination = await _resolveNavigationDestination(order, target);
    MapboxPoint? origin;
    if (destination != null) {
      try {
        origin = await _mapboxLocation.currentPoint();
      } on Object {
        origin = null;
      }
    }

    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final address = _navigationAddress(order, target);
    if (destination == null && address.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No route destination is available yet')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _RiderNavigationPage(
          order: order,
          target: target,
          mapboxLocation: _mapboxLocation,
          initialOrigin: origin,
          destination: destination,
        ),
      ),
    );
  }

  Future<MapboxPoint?> _resolveNavigationDestination(
    OrderSummary order,
    _RiderRouteTarget target,
  ) async {
    final existing = _destinationPoint(order, target);
    if (existing != null) {
      return existing;
    }

    final address = _navigationAddress(order, target);
    if (address.isEmpty || !_mapboxLocation.isConfigured) {
      return null;
    }

    try {
      final results = await _mapboxLocation.searchAddresses(
        address,
        country: 'ng',
        limit: 1,
      );
      return results.isEmpty ? null : results.first.point;
    } on Object {
      return null;
    }
  }

  Future<void> _callCustomer(OrderSummary order) async {
    await _launchContactUri(order.customerPhone, scheme: 'tel');
  }

  Future<void> _messageCustomer(OrderSummary order) async {
    await _launchContactUri(order.customerPhone, scheme: 'sms');
  }

  Future<void> _launchContactUri(String? phone,
      {required String scheme}) async {
    final normalized = phone?.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (normalized == null || normalized.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No customer phone number is available')),
      );
      return;
    }

    final opened = await launchUrl(Uri(scheme: scheme, path: normalized));
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open $scheme app')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RiderAvailability?>(
      stream: _repository.watchMyRiderAvailability(),
      builder: (context, snapshot) {
        final availability = snapshot.data;
        final isOnline = availability?.isOnline ?? false;
        final isAvailabilityLoading =
            snapshot.connectionState == ConnectionState.waiting;

        return Scaffold(
          key: _scaffoldKey,
          drawer: _RiderNavigationDrawer(
            userEmail: widget.userEmail,
            onWallet: _openWallet,
            onRecentOrders: _openRecentOrders,
            onNotifications: _openNotifications,
            onProfile: _openProfilePage,
            onHelp: _openHelp,
            onSignOut: () => Supabase.instance.client.auth.signOut(),
          ),
          body: _RiderLifecyclePane(
            repository: _repository,
            hasMapboxToken: widget.mapboxAccessToken.isNotEmpty,
            isOnline: isOnline,
            isAvailabilityLoading: isAvailabilityLoading,
            isAvailabilitySubmitting: _isUpdatingAvailability,
            onAvailabilityChanged: _setAvailability,
            onAccept: _accept,
            onDecline: _decline,
            onUpdateEta: _updateEta,
            onConfirmPickup: _markOutForDelivery,
            onConfirmDropOff: _markDelivered,
            onShareLocation: _shareLocation,
            onToggleLiveLocation: _toggleLiveLocation,
            onNavigate: _openNavigation,
            onCallCustomer: _callCustomer,
            onMessageCustomer: _messageCustomer,
            onOpenMenu: _openMenu,
            liveLocationOrderId: _liveLocationOrderId,
            sharingLocationOrderIds: _sharingLocationOrderIds,
          ),
        );
      },
    );
  }
}

class _RiderNavigationDrawer extends StatelessWidget {
  const _RiderNavigationDrawer({
    required this.userEmail,
    required this.onWallet,
    required this.onRecentOrders,
    required this.onNotifications,
    required this.onProfile,
    required this.onHelp,
    required this.onSignOut,
  });

  final String userEmail;
  final VoidCallback onWallet;
  final VoidCallback onRecentOrders;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final VoidCallback onHelp;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xffdcfce7),
                    foregroundColor: Color(0xff047857),
                    child: Icon(Icons.delivery_dining),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Luumoh Rider',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        Text(
                          userEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _RiderDrawerTile(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Wallet',
              onTap: onWallet,
            ),
            _RiderDrawerTile(
              icon: Icons.history,
              label: 'Recent orders',
              onTap: onRecentOrders,
            ),
            _RiderDrawerTile(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              onTap: onNotifications,
            ),
            _RiderDrawerTile(
              icon: Icons.account_circle_outlined,
              label: 'Account/Profile',
              onTap: onProfile,
            ),
            _RiderDrawerTile(
              icon: Icons.support_agent_outlined,
              label: 'Get help',
              onTap: onHelp,
            ),
            const Spacer(),
            const Divider(height: 1),
            _RiderDrawerTile(
              icon: Icons.logout,
              label: 'Log out',
              onTap: onSignOut,
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderDrawerTile extends StatelessWidget {
  const _RiderDrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) => onTap());
      },
    );
  }
}

class _RiderHelpSheet extends StatelessWidget {
  const _RiderHelpSheet({this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: embedded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Get help',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.receipt_long_outlined),
            title: Text('Order issue'),
            subtitle: Text('Report pickup, drop-off, or customer problems.'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.location_searching),
            title: Text('Location help'),
            subtitle: Text('Check GPS, navigation, and live tracking issues.'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.payments_outlined),
            title: Text('Wallet support'),
            subtitle: Text('Ask about payout status or settlement records.'),
          ),
          const SizedBox(height: 8),
          if (!embedded)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check),
              label: const Text('Done'),
            ),
        ],
      ),
    );

    return embedded ? content : SafeArea(child: content);
  }
}

enum _RiderRouteTarget { store, customer }

class _RiderStandalonePage extends StatelessWidget {
  const _RiderStandalonePage({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: child),
    );
  }
}

class _RiderAccountPage extends StatelessWidget {
  const _RiderAccountPage({
    required this.repository,
    required this.userEmail,
  });

  final PlatformRepository repository;
  final String userEmail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account/Profile')),
      body: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: repository.watchMyProfile(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _InlineState(
                title: 'Profile failed to load',
                message: '${snapshot.error}',
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _InlineState(
                title: 'Loading profile',
                message: 'Fetching rider profile...',
                isLoading: true,
              );
            }

            final profile = snapshot.data;
            final name = profile?.fullName.trim();
            final phone = profile?.phone?.trim();
            final displayName = name == null || name.isEmpty ? 'Rider' : name;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: const Color(0xffdcfce7),
                    foregroundColor: const Color(0xff047857),
                    child: Text(
                      displayName[0].toUpperCase(),
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  userEmail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: const Text('Phone'),
                        subtitle: Text(
                          phone == null || phone.isEmpty ? 'Not set' : phone,
                        ),
                      ),
                      const Divider(height: 1),
                      const ListTile(
                        leading: Icon(Icons.verified_user_outlined),
                        title: Text('Role'),
                        subtitle: Text('Rider'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => _ProfileDialog(
                      repository: repository,
                      profile: profile,
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit profile'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MapCircleButton extends StatelessWidget {
  const _MapCircleButton({
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? const Color(0xff059669) : Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: filled ? Colors.white : Colors.black87,
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.icon,
    required this.color,
    this.label,
  });

  final IconData icon;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 10),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x22000000), blurRadius: 8),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                label!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
        Container(width: 3, height: 18, color: Colors.black87),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.black87, width: 4),
          ),
        ),
      ],
    );
  }
}

class _RouteStopLine extends StatelessWidget {
  const _RouteStopLine({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderIdentityBlock extends StatelessWidget {
  const _OrderIdentityBlock({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _numericOrderCode(order.id),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                '#${_shortId(order.id)} | ${_customerName(order)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                order.storeName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
        _RiderEtaChip(order: order),
      ],
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(14),
        ),
        child: Icon(icon),
      ),
    );
  }
}

class _RiderSettlementsPane extends StatelessWidget {
  const _RiderSettlementsPane({required this.repository});

  final PlatformRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RiderSettlementSummary>>(
      stream: repository.watchRiderSettlements(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Earnings failed to load',
            message: '${snapshot.error}',
          );
        }

        final settlements = snapshot.data ?? const <RiderSettlementSummary>[];
        final pendingTotal = settlements
            .where((item) => item.status == 'pending')
            .fold<double>(0, (total, item) => total + item.riderPayoutAmount);
        final paidTotal = settlements
            .where((item) => item.status == 'paid')
            .fold<double>(0, (total, item) => total + item.riderPayoutAmount);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Earnings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RiderMetricTile(
                  label: 'Pending',
                  value: 'NGN ${pendingTotal.toStringAsFixed(0)}',
                ),
                _RiderMetricTile(
                  label: 'Paid',
                  value: 'NGN ${paidTotal.toStringAsFixed(0)}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (settlements.isEmpty)
              const Text('Delivered order payouts will appear here.')
            else
              for (final settlement in settlements.take(12))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text(
                      '${settlement.storeName} | NGN ${settlement.riderPayoutAmount.toStringAsFixed(2)}',
                    ),
                    subtitle: Text(
                      'Order #${_shortId(settlement.orderId)} | '
                      '${_humanStatus(settlement.status)} | '
                      '${_formatDateTime(settlement.updatedAt)}',
                    ),
                    trailing: settlement.status == 'paid'
                        ? const Icon(Icons.verified_outlined)
                        : null,
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _RiderLocationPanel extends StatelessWidget {
  const _RiderLocationPanel({
    required this.repository,
    required this.orderId,
    this.compact = false,
  });

  final PlatformRepository repository;
  final String orderId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RiderLocationUpdate>>(
      stream: repository.watchRiderLocations(orderId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Location failed: ${snapshot.error}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
        }

        final locations = snapshot.data ?? const <RiderLocationUpdate>[];
        final latest = locations.isEmpty ? null : locations.first;
        if (latest == null) {
          return Row(
            children: [
              const Icon(Icons.location_searching, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  compact
                      ? 'No live location shared yet'
                      : 'Live location will appear after sharing starts.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 8 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.my_location, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${latest.latitude.toStringAsFixed(6)}, '
                    '${latest.longitude.toStringAsFixed(6)}\n'
                    'Updated ${_formatDateTime(latest.createdAt)}'
                    '${latest.accuracyMeters == null ? '' : ' | accuracy ${latest.accuracyMeters!.toStringAsFixed(0)}m'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RiderWorkSummary extends StatelessWidget {
  const _RiderWorkSummary({required this.orders});

  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final activeCount = orders.where(_isActiveRiderOrder).length;
    final deliveredOrders =
        orders.where((order) => order.status == 'delivered').toList();
    final deliveredToday = deliveredOrders
        .where((order) => _isSameLocalDay(order.updatedAt, now))
        .toList();
    final earningsToday = deliveredToday.fold<double>(
      0,
      (total, order) => total + order.riderPayoutAmount,
    );

    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width < 700 ? 2 : 4,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _RiderMetricTile(label: 'Active', value: activeCount.toString()),
        _RiderMetricTile(
          label: 'Delivered today',
          value: deliveredToday.length.toString(),
        ),
        _RiderMetricTile(
          label: 'Earnings today',
          value: 'NGN ${earningsToday.toStringAsFixed(0)}',
        ),
        _RiderMetricTile(
          label: 'All delivered',
          value: deliveredOrders.length.toString(),
        ),
      ],
    );
  }
}

class _RiderMetricTile extends StatelessWidget {
  const _RiderMetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({
    required this.repository,
    required this.profile,
  });

  final PlatformRepository repository;
  final UserProfile? profile;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile?.fullName);
    _phoneController = TextEditingController(text: widget.profile?.phone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.updateMyProfile(
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Profile update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                enabled: !_isSaving,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 2) {
                    return 'Enter your full name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                enabled: !_isSaving,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _isSaving ? null : _save(),
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

class _RiderEtaChip extends StatelessWidget {
  const _RiderEtaChip({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    final isLate = _isOrderEtaLate(order);
    final isSoon = !isLate && _isOrderEtaDueSoon(order);
    final colorScheme = Theme.of(context).colorScheme;

    return Chip(
      avatar: Icon(
        isLate
            ? Icons.timer_off_outlined
            : isSoon
                ? Icons.schedule
                : Icons.delivery_dining_outlined,
        size: 18,
      ),
      label: Text(
        isLate
            ? 'Late'
            : isSoon
                ? 'Due soon'
                : order.etaMinutes == null
                    ? 'ETA --'
                    : 'ETA ${order.etaMinutes}m',
      ),
      backgroundColor: isLate
          ? colorScheme.errorContainer
          : isSoon
              ? colorScheme.tertiaryContainer
              : null,
    );
  }
}

class _OrderItemsList extends StatelessWidget {
  const _OrderItemsList({
    required this.repository,
    required this.orderId,
  });

  final PlatformRepository repository;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderLineItem>>(
      stream: repository.watchOrderItems(orderId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text('Items failed: ${snapshot.error}'),
          );
        }

        final items = snapshot.data ?? const <OrderLineItem>[];
        if (items.isEmpty) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Text('Order items will appear here.'),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Items', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(item.productName)),
                    Text('x${item.quantity}'),
                    const SizedBox(width: 12),
                    Text('NGN ${item.lineTotal.toStringAsFixed(2)}'),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EtaDialog extends StatefulWidget {
  const _EtaDialog({
    required this.title,
    this.initialEta = 20,
  });

  final String title;
  final int initialEta;

  @override
  State<_EtaDialog> createState() => _EtaDialogState();
}

class _EtaDialogState extends State<_EtaDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEta.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(int.parse(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final eta in const [10, 15, 20, 30, 45])
                    ActionChip(
                      label: Text('${eta}m'),
                      onPressed: () => _controller.text = eta.toString(),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ETA minutes',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final eta = int.tryParse(value?.trim() ?? '');
                  if (eta == null || eta < 0) {
                    return 'Enter a valid ETA';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
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

class _InlineState extends StatelessWidget {
  const _InlineState({
    required this.title,
    required this.message,
    this.isLoading = false,
  });

  final String title;
  final String message;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

String _humanStatus(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
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

String _formatRiderRevenue(double value) {
  return 'NGN ${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}';
}

bool _isActiveRiderOrder(OrderSummary order) {
  return !_isFinishedRiderOrder(order);
}

bool _isFinishedRiderOrder(OrderSummary order) {
  return order.status == 'delivered' ||
      order.status == 'cancelled' ||
      order.status == 'expired' ||
      order.paymentStatus == 'expired' ||
      order.paymentStatus == 'failed' ||
      order.paymentStatus == 'refunded';
}

bool _riderOrderMatchesFilter(OrderSummary order, String filter) {
  return switch (filter) {
    'ready_for_pickup' => order.status == 'ready_for_pickup',
    'out_for_delivery' => order.status == 'out_for_delivery',
    'delivered' => order.status == 'delivered',
    'cancelled' => order.status == 'cancelled',
    'expired' => order.status == 'expired' || order.paymentStatus == 'expired',
    'declined' => order.status == 'cancelled' &&
        (order.cancellationReason ?? '').toLowerCase().contains('rider'),
    'failed' => order.paymentStatus == 'failed',
    _ => true,
  };
}

bool _matchesRiderOrderSearch(OrderSummary order, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }

  return order.id.toLowerCase().contains(normalized) ||
      _numericOrderCode(order.id).toLowerCase().contains(normalized) ||
      order.storeName.toLowerCase().contains(normalized) ||
      order.storeAddress.toLowerCase().contains(normalized) ||
      _customerName(order).toLowerCase().contains(normalized) ||
      (order.customerPhone ?? '').toLowerCase().contains(normalized) ||
      order.deliveryAddress.toLowerCase().contains(normalized) ||
      order.status.toLowerCase().contains(normalized) ||
      _humanStatus(order.status).toLowerCase().contains(normalized) ||
      order.paymentStatus.toLowerCase().contains(normalized) ||
      _humanStatus(order.paymentStatus).toLowerCase().contains(normalized) ||
      _formatRiderRevenue(order.riderPayoutAmount)
          .toLowerCase()
          .contains(normalized);
}

String _riderFilterLabel(String filter) {
  return switch (filter) {
    'ready_for_pickup' => 'Pickup',
    'out_for_delivery' => 'Drop-off',
    'delivered' => 'Fulfilled',
    'cancelled' => 'Cancelled',
    'expired' => 'Expired',
    'declined' => 'Declined',
    'failed' => 'Failed payment',
    _ => 'All',
  };
}

bool _isSameLocalDay(DateTime value, DateTime day) {
  final localValue = value.toLocal();
  final localDay = day.toLocal();
  return localValue.year == localDay.year &&
      localValue.month == localDay.month &&
      localValue.day == localDay.day;
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

bool _isOrderEtaDueSoon(OrderSummary order) {
  if (order.status == 'delivered' || order.status == 'cancelled') {
    return false;
  }
  final etaMinutes = order.etaMinutes;
  final etaUpdatedAt = order.etaUpdatedAt;
  if (etaMinutes == null || etaUpdatedAt == null) {
    return false;
  }
  final dueAt = etaUpdatedAt.toLocal().add(Duration(minutes: etaMinutes));
  final remaining = dueAt.difference(DateTime.now());
  return !remaining.isNegative && remaining.inMinutes <= 10;
}

String _shortId(String value) {
  return value.length <= 8 ? value : value.substring(0, 8);
}

String _storeAddress(OrderSummary order) {
  if (order.storeAddress.trim().isNotEmpty) {
    return order.storeAddress.trim();
  }
  if (order.storeLatitude != null && order.storeLongitude != null) {
    return '${order.storeLatitude!.toStringAsFixed(5)}, '
        '${order.storeLongitude!.toStringAsFixed(5)}';
  }
  return 'Store address pending';
}

String _customerName(OrderSummary order) {
  final name = order.customerName?.trim();
  return name == null || name.isEmpty ? 'Customer' : name;
}

String _numericOrderCode(String id) {
  final digits = id.replaceAll(RegExp('[^0-9]'), '');
  if (digits.length >= 12) {
    return digits.substring(0, 12);
  }
  return digits.isEmpty ? '#${_shortId(id)}' : digits.padRight(8, '0');
}

MapboxPoint? _destinationPoint(OrderSummary order, _RiderRouteTarget target) {
  final latitude = switch (target) {
    _RiderRouteTarget.store => order.storeLatitude,
    _RiderRouteTarget.customer => order.deliveryLatitude,
  };
  final longitude = switch (target) {
    _RiderRouteTarget.store => order.storeLongitude,
    _RiderRouteTarget.customer => order.deliveryLongitude,
  };

  if (latitude == null || longitude == null) {
    return null;
  }
  return MapboxPoint(latitude: latitude, longitude: longitude);
}

String _navigationAddress(OrderSummary order, _RiderRouteTarget target) {
  return switch (target) {
    _RiderRouteTarget.store => order.storeAddress,
    _RiderRouteTarget.customer => order.deliveryAddress,
  }
      .trim();
}

List<Uri> _navigationUris({
  required OrderSummary order,
  required _RiderRouteTarget target,
  required MapboxPoint? origin,
  required MapboxPoint? destination,
  required MapboxLocationService mapboxLocation,
}) {
  final destinationName = _navigationDestinationName(order, target);
  final address = _navigationAddress(order, target);

  if (destination == null) {
    if (address.isEmpty) {
      return const [];
    }
    final query = '$destinationName, $address';
    return [
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        if (origin != null && origin.isValid)
          'origin': '${origin.latitude},${origin.longitude}',
        'destination': query,
        'travelmode': 'driving',
      }),
      Uri(
        scheme: 'google.navigation',
        queryParameters: {'q': query, 'mode': 'd'},
      ),
      Uri(
        scheme: 'geo',
        path: '0,0',
        queryParameters: {'q': query},
      ),
      Uri.https('www.mapbox.com', '/search/', {'query': query}),
    ];
  }

  final destinationPair = '${destination.longitude},${destination.latitude}';
  final originPair = origin == null || !origin.isValid
      ? null
      : '${origin.longitude},${origin.latitude}';
  final latLngPair = '${destination.latitude},${destination.longitude}';
  final label =
      address.isEmpty ? destinationName : '$destinationName, $address';

  return [
    Uri(
      scheme: 'mapbox',
      host: 'directions',
      path: '/v5/mapbox/driving-traffic/$destinationPair',
      queryParameters: {
        if (originPair != null) 'origin': originPair,
        'destination_name': destinationName,
      },
    ),
    mapboxLocation.navigationUri(
      origin: origin,
      destination: destination,
      destinationName: destinationName,
    ),
    Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (origin != null && origin.isValid)
        'origin': '${origin.latitude},${origin.longitude}',
      'destination': latLngPair,
      'travelmode': 'driving',
    }),
    Uri(
      scheme: 'google.navigation',
      queryParameters: {'q': latLngPair, 'mode': 'd'},
    ),
    Uri(
      scheme: 'geo',
      path: latLngPair,
      queryParameters: {'q': '$latLngPair($label)'},
    ),
  ];
}

MapboxPoint _riderMapCenter(List<MapboxPoint> points) {
  if (points.isEmpty) {
    return const MapboxPoint(latitude: 6.5244, longitude: 3.3792);
  }
  final latitude =
      points.fold<double>(0, (total, point) => total + point.latitude) /
          points.length;
  final longitude =
      points.fold<double>(0, (total, point) => total + point.longitude) /
          points.length;
  return MapboxPoint(latitude: latitude, longitude: longitude);
}

String _navigationDestinationName(
  OrderSummary order,
  _RiderRouteTarget target,
) {
  return switch (target) {
    _RiderRouteTarget.store => order.storeName,
    _RiderRouteTarget.customer => _customerName(order),
  };
}
