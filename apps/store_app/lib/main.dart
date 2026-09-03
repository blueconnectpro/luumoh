import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:luumoh_core/luumoh_core.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:supabase_flutter/supabase_flutter.dart';

part 'features/inventory/product_form_dialog.dart';
part 'features/inventory/stock_dialogs.dart';
part 'features/orders/orders_pane.dart';

final configuredStoreId = AppEnvironment.storeIdFromConfig();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(StoreApp(environment: AppEnvironment.fromDartDefines()));
}

class StoreApp extends StatelessWidget {
  const StoreApp({required this.environment, super.key});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Luumoh Store',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff16a34a),
          brightness: Brightness.light,
        ).copyWith(
          surface: Colors.white,
          onSurface: const Color(0xff111827),
          error: const Color(0xffdc2626),
          errorContainer: const Color(0xffffe4e6),
          onErrorContainer: const Color(0xff7f1d1d),
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xff111827),
          surfaceTintColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xff16a34a),
            foregroundColor: Colors.white,
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Color(0xff16a34a)
                : const Color(0xffdc2626),
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Color(0xffbbf7d0)
                : const Color(0xffffe4e6),
          ),
        ),
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
            title: 'Starting Luumoh Store',
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
                '--dart-define=SUPABASE_PUBLISHABLE_KEY=...\n'
                '--dart-define=STORE_ID=...',
          );
        }

        return _StoreAuthGate(environment: widget.environment);
      },
    );
  }
}

class _StoreAuthGate extends StatelessWidget {
  const _StoreAuthGate({required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session == null) {
          return const _StoreSignInPage();
        }

        return _StoreScopeGate(
          userEmail: session.user.email ?? 'Store staff',
          environment: environment,
        );
      },
    );
  }
}

class _StoreScopeGate extends StatefulWidget {
  const _StoreScopeGate({
    required this.userEmail,
    required this.environment,
  });

  final String userEmail;
  final AppEnvironment environment;

  @override
  State<_StoreScopeGate> createState() => _StoreScopeGateState();
}

class _StoreScopeGateState extends State<_StoreScopeGate> {
  late final PlatformRepository _repository;
  late final Future<List<StoreMember>> _membershipsFuture;

  @override
  void initState() {
    super.initState();
    _repository = PlatformRepository(Supabase.instance.client);
    _membershipsFuture = _repository.fetchMyStoreMemberships();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StoreMember>>(
      future: _membershipsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StatusScaffold(
            title: 'Store access failed',
            message: '${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _StatusScaffold(
            title: 'Loading store access',
            message: 'Checking your store membership...',
            isLoading: true,
          );
        }

        final memberships = snapshot.data ?? const <StoreMember>[];
        if (memberships.isEmpty) {
          return const _StatusScaffold(
            title: 'No store assigned',
            message: 'Ask an admin to add this account as a store member.',
          );
        }

        final selectedMembership = _selectStoreMembership(memberships);
        return StoreHomePage(
          userEmail: widget.userEmail,
          storeId: selectedMembership.storeId,
          mapboxAccessToken: widget.environment.mapboxAccessToken,
        );
      },
    );
  }
}

StoreMember _selectStoreMembership(List<StoreMember> memberships) {
  if (_isUuid(configuredStoreId)) {
    for (final membership in memberships) {
      if (membership.storeId == configuredStoreId) {
        return membership;
      }
    }
  }

  return memberships.first;
}

bool _isUuid(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

class _StoreSignInPage extends StatefulWidget {
  const _StoreSignInPage();

  @override
  State<_StoreSignInPage> createState() => _StoreSignInPageState();
}

class _StoreSignInPageState extends State<_StoreSignInPage> {
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
                      'Store sign in',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use a store member account for this store.',
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

class StoreHomePage extends StatefulWidget {
  const StoreHomePage({
    required this.userEmail,
    required this.storeId,
    required this.mapboxAccessToken,
    super.key,
  });

  final String userEmail;
  final String storeId;
  final String mapboxAccessToken;

  @override
  State<StoreHomePage> createState() => _StoreHomePageState();
}

class _StoreHomePageState extends State<StoreHomePage> {
  late final PlatformRepository _repository;
  late final MapboxLocationService _mapboxLocation;
  var _selectedSection = 0;

  @override
  void initState() {
    super.initState();
    _repository = PlatformRepository(Supabase.instance.client);
    _mapboxLocation = MapboxLocationService(widget.mapboxAccessToken);
    _registerPresence(true);
  }

  @override
  void dispose() {
    _registerPresence(false);
    super.dispose();
  }

  void _registerPresence(bool isActive) {
    unawaited(
      _repository.registerStoreStaffPresence(
        storeId: widget.storeId,
        isActive: isActive,
      ),
    );
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
          onSignOut: _signOut,
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
          audience: 'store',
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will stop receiving store updates on this device until you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    _registerPresence(false);
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _setAvailability(StoreInventoryItem product, bool value) async {
    await _setProductUnavailability(
      product,
      value ? 'available' : 'indefinite',
    );
  }

  Future<void> _setProductUnavailability(
    StoreInventoryItem product,
    String mode,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.setProductUnavailability(
        productId: product.productId,
        mode: mode,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            mode == 'available'
                ? '${product.name} is available'
                : '${product.name} is unavailable',
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Availability update failed: $error')),
      );
    }
  }

  Future<void> _setStoreOpen(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.setStoreAvailabilityStatus(
        storeId: widget.storeId,
        mode: value ? 'open' : 'closed_today',
      );
      messenger.showSnackBar(
        SnackBar(content: Text(value ? 'Store opened' : 'Store closed')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Store status update failed: $error')),
      );
    }
  }

  Future<void> _createProduct() async {
    final draft = await showDialog<_ProductDraft>(
      context: context,
      builder: (context) => _ProductFormDialog(
        repository: _repository,
        storeId: widget.storeId,
      ),
    );

    if (draft == null || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.createProduct(
        storeId: widget.storeId,
        name: draft.name,
        description: draft.description,
        price: draft.price,
        category: draft.category,
        initialStock: draft.initialStock,
        reorderLevel: draft.reorderLevel,
        sku: draft.sku,
        imageUrl: draft.imageUrl,
        imageUrls: draft.imageUrls,
        isAvailable: draft.isAvailable,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Created ${draft.name}')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Product creation failed: $error')),
      );
    }
  }

  Future<void> _updateOrderStatus(OrderSummary order, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (status == 'ready_for_pickup') {
        final riderId = await _repository.markStoreOrderReadyAndDispatch(
          orderId: order.id,
          etaMinutes: order.etaMinutes,
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              order.fulfillmentType == 'pickup'
                  ? 'Order marked ready for pickup'
                  : riderId == null
                      ? 'Order marked ready. No online rider was available yet.'
                      : 'Order ready. Nearest online rider notified.',
            ),
          ),
        );
      } else {
        await _repository.updateStoreOrderStatus(
          orderId: order.id,
          status: status,
        );
        messenger.showSnackBar(
          SnackBar(content: Text('Order marked ${_humanStatus(status)}')),
        );
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Order update failed: $error')),
      );
    }
  }

  Future<void> _updatePreparationTime(
    OrderSummary order,
    int preparationMinutes,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.updateStorePreparationTime(
        orderId: order.id,
        preparationMinutes: preparationMinutes,
      );
      messenger.showSnackBar(
        SnackBar(
            content: Text('Preparation time set to ${preparationMinutes}m')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Preparation time update failed: $error')),
      );
    }
  }

  Future<void> _modifyOrderItem({
    required OrderSummary order,
    required OrderLineItem item,
    required String action,
    String? replacementProductId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.modifyStoreOrderItem(
        orderId: order.id,
        orderItemId: item.id,
        action: action,
        replacementProductId: replacementProductId,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Order updated and accepted')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Order modification failed: $error')),
      );
    }
  }

  Future<void> _cancelOrder(OrderSummary order) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline order'),
        content: const Text(
          'Already accepted orders will not be cancelled when changing store availability. Decline only when this order cannot be fulfilled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep order'),
          ),
          for (final reason in const [
            'Vendor closed',
            'Too busy',
            'Item unavailable',
          ])
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffffe4e6),
                foregroundColor: const Color(0xffb91c1c),
              ),
              onPressed: () => Navigator.of(context).pop(reason),
              child: Text(reason),
            ),
        ],
      ),
    );

    if (reason != null && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await _repository.updateStoreOrderStatus(
          orderId: order.id,
          status: 'cancelled',
          note: reason,
        );
        messenger.showSnackBar(
          SnackBar(content: Text('Order declined: $reason')),
        );
      } on Object catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('Decline failed: $error')),
        );
      }
    }
  }

  void _openSection(int index) {
    setState(() => _selectedSection = index);
  }

  Future<void> _openMorePage(String title, Widget child) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _StoreMorePage(
          title: title,
          child: child,
        ),
      ),
    );
  }

  Future<void> _openSupportPage() =>
      _openMorePage('Support', _StoreIssuesPane(repository: _repository));

  Future<void> _openReviewsPage() => _openMorePage(
        'Reviews',
        _StoreReviewsPane(repository: _repository, storeId: widget.storeId),
      );

  Future<void> _openPromosPage() => _openMorePage(
        'Promo codes',
        _StorePromosPane(repository: _repository, storeId: widget.storeId),
      );

  Future<void> _openSettlementsPage() => _openMorePage(
        'Settlements',
        _StoreSettlementsPane(repository: _repository, storeId: widget.storeId),
      );

  Future<void> _openAccountPage() => _openMorePage(
        'Account',
        _StoreAccountPane(
          repository: _repository,
          storeId: widget.storeId,
          mapboxLocation: _mapboxLocation,
          userEmail: widget.userEmail,
          onManageAccount: _openProfileDialog,
          onSignOut: _signOut,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final home = _StoreHomeDashboard(
      repository: _repository,
      storeId: widget.storeId,
      onStatusChanged: _updateOrderStatus,
      onPreparationTimeChanged: _updatePreparationTime,
      onModifyOrderItem: _modifyOrderItem,
      onCancelOrder: _cancelOrder,
      onViewAllOrders: () => _openSection(1),
    );
    final inventory = _InventoryPane(
      repository: _repository,
      storeId: widget.storeId,
      onAvailabilityChanged: _setAvailability,
      onUnavailabilityModeChanged: _setProductUnavailability,
      onCreateProduct: _createProduct,
    );
    final orders = _OrdersPane(
      repository: _repository,
      storeId: widget.storeId,
      onStatusChanged: _updateOrderStatus,
      onPreparationTimeChanged: _updatePreparationTime,
      onModifyOrderItem: _modifyOrderItem,
      onCancelOrder: _cancelOrder,
    );
    final hours = _StoreOpeningHoursPane(
      repository: _repository,
      storeId: widget.storeId,
    );
    final pages = [home, orders, inventory, hours];
    final selectedSection = _selectedSection.clamp(0, pages.length - 1).toInt();
    const destinations = [
      _StoreDestination(
        label: 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
      ),
      _StoreDestination(
        label: 'Orders',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
      ),
      _StoreDestination(
        label: 'Inventory',
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
      ),
      _StoreDestination(
        label: 'Hours',
        icon: Icons.schedule_outlined,
        selectedIcon: Icons.schedule,
      ),
    ];

    return Scaffold(
      drawer: _StoreDrawer(
        userEmail: widget.userEmail,
        onSupport: () => unawaited(_openSupportPage()),
        onReviews: () => unawaited(_openReviewsPage()),
        onPromos: () => unawaited(_openPromosPage()),
        onSettlements: () => unawaited(_openSettlementsPage()),
        onAccount: () => unawaited(_openAccountPage()),
      ),
      appBar: AppBar(
        title: const Text('Luumoh Store'),
        actions: [
          _StoreStatusControl(
            repository: _repository,
            storeId: widget.storeId,
            onChanged: _setStoreOpen,
          ),
          _NotificationIcon(
            repository: _repository,
            audience: 'store',
            onPressed: _openNotifications,
          ),
          IconButton(
            tooltip: 'Manage account',
            onPressed: _openProfileDialog,
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 840) {
            return Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedSection,
                  onDestinationSelected: _openSection,
                  labelType: constraints.maxWidth >= 1120
                      ? NavigationRailLabelType.all
                      : NavigationRailLabelType.selected,
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages[selectedSection]),
              ],
            );
          }

          return pages[selectedSection];
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 840) {
            return const SizedBox.shrink();
          }

          return NavigationBar(
            selectedIndex: selectedSection,
            onDestinationSelected: _openSection,
            destinations: [
              for (final destination in destinations)
                NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StoreDestination {
  const _StoreDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _StoreMorePage extends StatelessWidget {
  const _StoreMorePage({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

class _StoreDrawer extends StatelessWidget {
  const _StoreDrawer({
    required this.userEmail,
    required this.onSupport,
    required this.onReviews,
    required this.onPromos,
    required this.onSettlements,
    required this.onAccount,
  });

  final String userEmail;
  final VoidCallback onSupport;
  final VoidCallback onReviews;
  final VoidCallback onPromos;
  final VoidCallback onSettlements;
  final VoidCallback onAccount;

  void _open(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ListTile(
              title: const Text('Luumoh Store'),
              subtitle: Text(
                userEmail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Support'),
              onTap: () => _open(context, onSupport),
            ),
            ListTile(
              leading: const Icon(Icons.reviews_outlined),
              title: const Text('Reviews'),
              onTap: () => _open(context, onReviews),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Settlements'),
              onTap: () => _open(context, onSettlements),
            ),
            ListTile(
              leading: const Icon(Icons.local_offer_outlined),
              title: const Text('Promo codes'),
              onTap: () => _open(context, onPromos),
            ),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Account'),
              onTap: () => _open(context, onAccount),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreAccountPane extends StatelessWidget {
  const _StoreAccountPane({
    required this.repository,
    required this.storeId,
    required this.mapboxLocation,
    required this.userEmail,
    required this.onManageAccount,
    required this.onSignOut,
  });

  final PlatformRepository repository;
  final String storeId;
  final MapboxLocationService mapboxLocation;
  final String userEmail;
  final VoidCallback onManageAccount;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Manage account',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(userEmail),
                  subtitle: const Text('Store staff account'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: onManageAccount,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit profile'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onSignOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Log out'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _StoreLocationCard(
          repository: repository,
          storeId: storeId,
          mapboxLocation: mapboxLocation,
        ),
      ],
    );
  }
}

class _StoreLocationCard extends StatelessWidget {
  const _StoreLocationCard({
    required this.repository,
    required this.storeId,
    required this.mapboxLocation,
  });

  final PlatformRepository repository;
  final String storeId;
  final MapboxLocationService mapboxLocation;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StoreSummary?>(
      stream: repository.watchStore(storeId),
      builder: (context, snapshot) {
        final store = snapshot.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('Store location'),
                  subtitle: Text(
                    store == null
                        ? 'Loading store address...'
                        : store.address.trim().isEmpty
                            ? 'No store address saved'
                            : store.address,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: store == null
                      ? null
                      : () => showDialog<void>(
                            context: context,
                            builder: (context) => _StoreLocationDialog(
                              repository: repository,
                              store: store,
                              mapboxLocation: mapboxLocation,
                            ),
                          ),
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('Update store address'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StoreLocationDialog extends StatefulWidget {
  const _StoreLocationDialog({
    required this.repository,
    required this.store,
    required this.mapboxLocation,
  });

  final PlatformRepository repository;
  final StoreSummary store;
  final MapboxLocationService mapboxLocation;

  @override
  State<_StoreLocationDialog> createState() => _StoreLocationDialogState();
}

class _StoreLocationDialogState extends State<_StoreLocationDialog> {
  late final TextEditingController _addressController;
  MapboxPoint? _point;
  bool _isResolving = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: widget.store.address);
    if (widget.store.latitude != null && widget.store.longitude != null) {
      _point = MapboxPoint(
        latitude: widget.store.latitude!,
        longitude: widget.store.longitude!,
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_useCurrentLocation());
        }
      });
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isResolving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final point = await widget.mapboxLocation.currentPoint();
      var address =
          '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
      if (widget.mapboxLocation.isConfigured) {
        final result = await widget.mapboxLocation.reverseGeocode(point);
        if (result != null) {
          address = result.address;
        }
      }
      setState(() {
        _point = point;
        _addressController.text = address;
      });
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Current location failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isResolving = false);
      }
    }
  }

  Future<void> _findAddress() async {
    final query = _addressController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (!widget.mapboxLocation.isConfigured) {
      messenger.showSnackBar(
        const SnackBar(content: Text('MAPBOX_ACCESS_TOKEN is not configured')),
      );
      return;
    }
    if (query.length < 3) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter at least 3 characters')),
      );
      return;
    }

    setState(() => _isResolving = true);
    try {
      final results = await widget.mapboxLocation.searchAddresses(
        query,
        proximity: _point,
        country: 'ng',
      );
      if (!mounted) {
        return;
      }
      if (results.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No Mapbox address match found')),
        );
        return;
      }
      final selected = await showModalBottomSheet<MapboxAddressResult>(
        context: context,
        showDragHandle: true,
        builder: (context) => _StoreAddressResultsSheet(results: results),
      );
      if (selected == null || !mounted) {
        return;
      }
      setState(() {
        _point = selected.point;
        _addressController.text = selected.address;
      });
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Address lookup failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isResolving = false);
      }
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a store address')),
      );
      return;
    }

    var point = _point;
    setState(() => _isSaving = true);
    try {
      if (point == null && widget.mapboxLocation.isConfigured) {
        final results = await widget.mapboxLocation.searchAddresses(
          address,
          country: 'ng',
          limit: 1,
        );
        if (results.isNotEmpty) {
          point = results.first.point;
        }
      }
      if (point == null) {
        throw StateError('Choose current location or find the address first.');
      }
      await widget.repository.updateStoreLocation(
        storeId: widget.store.id,
        address: _addressController.text.trim(),
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Store location updated')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Store location update failed: $error')),
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
      title: const Text('Store address'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StoreLocationMapPreview(
                point: _point,
                enabled: widget.mapboxLocation.isConfigured,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                enabled: !_isSaving,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.search,
                onSubmitted:
                    _isResolving || _isSaving ? null : (_) => _findAddress(),
                onChanged: (_) => setState(() => _point = null),
                decoration: const InputDecoration(
                  labelText: 'Store address',
                  helperText: 'Search or use GPS to pin the store for riders.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _isResolving || _isSaving ? null : _useCurrentLocation,
                    icon: const Icon(Icons.my_location_outlined),
                    label: Text(_isResolving ? 'Finding...' : 'Use GPS'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isResolving || _isSaving ? null : _findAddress,
                    icon: const Icon(Icons.search),
                    label: const Text('Find address'),
                  ),
                ],
              ),
              if (_point != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Pinned at ${_point!.latitude.toStringAsFixed(6)}, ${_point!.longitude.toStringAsFixed(6)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
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
          icon: const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'Saving...' : 'Save address'),
        ),
      ],
    );
  }
}

class _StoreLocationMapPreview extends StatelessWidget {
  const _StoreLocationMapPreview({
    required this.point,
    required this.enabled,
  });

  final MapboxPoint? point;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 180,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (enabled && point != null)
              mapbox.MapWidget(
                key: ValueKey(
                  'store-location-${point!.latitude.toStringAsFixed(4)}-'
                  '${point!.longitude.toStringAsFixed(4)}',
                ),
                styleUri: mapbox.MapboxStyles.STANDARD,
                viewport: mapbox.CameraViewportState(
                  center: mapbox.Point(
                    coordinates:
                        mapbox.Position(point!.longitude, point!.latitude),
                  ),
                  zoom: 15,
                ),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: const Center(
                  child: Icon(Icons.map_outlined, size: 48),
                ),
              ),
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 18,
                      color: Colors.black.withValues(alpha: 0.18),
                    ),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.storefront, color: Color(0xff16a34a)),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text(
                    point == null
                        ? enabled
                            ? 'No store pin yet'
                            : 'Mapbox token is not configured'
                        : 'Store pin ready for rider pickup navigation',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreAddressResultsSheet extends StatelessWidget {
  const _StoreAddressResultsSheet({required this.results});

  final List<MapboxAddressResult> results;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: results.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Choose store address',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            );
          }
          final result = results[index - 1];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(result.name),
            subtitle: Text(result.address),
            onTap: () => Navigator.of(context).pop(result),
          );
        },
      ),
    );
  }
}

class _StoreHomeDashboard extends StatelessWidget {
  const _StoreHomeDashboard({
    required this.repository,
    required this.storeId,
    required this.onStatusChanged,
    required this.onPreparationTimeChanged,
    required this.onModifyOrderItem,
    required this.onCancelOrder,
    required this.onViewAllOrders,
  });

  final PlatformRepository repository;
  final String storeId;
  final void Function(OrderSummary order, String status) onStatusChanged;
  final void Function(OrderSummary order, int preparationMinutes)
      onPreparationTimeChanged;
  final void Function({
    required OrderSummary order,
    required OrderLineItem item,
    required String action,
    String? replacementProductId,
  }) onModifyOrderItem;
  final ValueChanged<OrderSummary> onCancelOrder;
  final VoidCallback onViewAllOrders;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderSummary>>(
      stream: repository.watchStoreOrders(storeId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Home failed to load',
            message: '${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _InlineState(
            title: 'Loading store home',
            message: 'Fetching current orders...',
            isLoading: true,
          );
        }

        final orders = snapshot.data ?? const <OrderSummary>[];
        final newOrders = orders
            .where(
              (order) =>
                  order.paymentStatus == 'paid' && order.status == 'paid',
            )
            .toList();
        final acceptedOrders = orders
            .where(
              (order) =>
                  order.paymentStatus == 'paid' &&
                  (order.status == 'accepted' || order.status == 'preparing'),
            )
            .toList();
        final readyOrders = orders
            .where(
              (order) =>
                  order.paymentStatus == 'paid' &&
                  order.status == 'ready_for_pickup',
            )
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Store home',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onViewAllOrders,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('All orders'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _StoreTodayMetrics(orders: orders),
            const SizedBox(height: 12),
            _StoreOrderSection(
              title: 'New orders',
              emptyText: 'No new orders',
              orders: newOrders,
              repository: repository,
              onStatusChanged: onStatusChanged,
              onPreparationTimeChanged: onPreparationTimeChanged,
              onModifyOrderItem: onModifyOrderItem,
              onCancelOrder: onCancelOrder,
            ),
            if (acceptedOrders.isNotEmpty) ...[
              const SizedBox(height: 12),
              _StoreOrderSection(
                title: 'Accepted',
                emptyText: 'No accepted orders',
                orders: acceptedOrders,
                repository: repository,
                onStatusChanged: onStatusChanged,
                onPreparationTimeChanged: onPreparationTimeChanged,
                onModifyOrderItem: onModifyOrderItem,
                onCancelOrder: onCancelOrder,
              ),
            ],
            if (readyOrders.isNotEmpty) ...[
              const SizedBox(height: 12),
              _StoreOrderSection(
                title: 'Ready for delivery',
                emptyText: 'No ready orders',
                orders: readyOrders,
                repository: repository,
                onStatusChanged: onStatusChanged,
                onPreparationTimeChanged: onPreparationTimeChanged,
                onModifyOrderItem: onModifyOrderItem,
                onCancelOrder: onCancelOrder,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StoreOrderSection extends StatelessWidget {
  const _StoreOrderSection({
    required this.title,
    required this.emptyText,
    required this.orders,
    required this.repository,
    required this.onStatusChanged,
    required this.onPreparationTimeChanged,
    required this.onModifyOrderItem,
    required this.onCancelOrder,
  });

  final String title;
  final String emptyText;
  final List<OrderSummary> orders;
  final PlatformRepository repository;
  final void Function(OrderSummary order, String status) onStatusChanged;
  final void Function(OrderSummary order, int preparationMinutes)
      onPreparationTimeChanged;
  final void Function({
    required OrderSummary order,
    required OrderLineItem item,
    required String action,
    String? replacementProductId,
  }) onModifyOrderItem;
  final ValueChanged<OrderSummary> onCancelOrder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            _CountBadge(count: orders.length),
          ],
        ),
        const SizedBox(height: 10),
        if (orders.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(emptyText, textAlign: TextAlign.center),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount =
                  (constraints.maxWidth / 156).floor().clamp(2, 6);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: orders.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 236,
                ),
                itemBuilder: (context, index) => _StoreOrderCard(
                  repository: repository,
                  order: orders[index],
                  onStatusChanged: onStatusChanged,
                  onPreparationTimeChanged: onPreparationTimeChanged,
                  onModifyOrderItem: onModifyOrderItem,
                  onCancelOrder: onCancelOrder,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _StoreOpeningHoursPane extends StatelessWidget {
  const _StoreOpeningHoursPane({
    required this.repository,
    required this.storeId,
  });

  final PlatformRepository repository;
  final String storeId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoreOpeningHour>>(
      stream: repository.watchStoreOpeningHours(storeId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Opening hours failed to load',
            message: '${snapshot.error}',
          );
        }

        final hours = snapshot.data ?? const <StoreOpeningHour>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Opening hours',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Set normal opening times. Temporary busy or closed status only affects new incoming orders.',
            ),
            const SizedBox(height: 12),
            for (var day = 0; day < 7; day++)
              Card(
                child: _OpeningHourRow(
                  repository: repository,
                  storeId: storeId,
                  dayOfWeek: day,
                  hour: _openingHourForDay(hours, day),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StoreStatusControl extends StatelessWidget {
  const _StoreStatusControl({
    required this.repository,
    required this.storeId,
    required this.onChanged,
  });

  final PlatformRepository repository;
  final String storeId;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StoreSummary?>(
      stream: repository.watchStore(storeId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Tooltip(
            message: 'Store status failed to load',
            child: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
          );
        }

        final store = snapshot.data;
        if (store == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ActionChip(
                avatar: Icon(_storeStatusIcon(store), size: 18),
                label: Text(_storeStatusLabel(store)),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => _StoreAvailabilitySheet(
                    repository: repository,
                    store: store,
                    onChanged: onChanged,
                  ),
                ),
              ),
              Switch(
                value: store.isOpen,
                onChanged: onChanged,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StoreAvailabilitySheet extends StatelessWidget {
  const _StoreAvailabilitySheet({
    required this.repository,
    required this.store,
    required this.onChanged,
  });

  final PlatformRepository repository;
  final StoreSummary store;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            store.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'Changing availability only affects new orders. Already accepted orders stay active.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onChanged(true);
                },
                icon: const Icon(Icons.storefront),
                label: const Text('Open'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await repository.setStoreAvailabilityStatus(
                    storeId: store.id,
                    mode: 'busy_30',
                  );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Store set busy for 30 mins')),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xffdc2626),
                  side: const BorderSide(color: Color(0xfffecaca)),
                ),
                icon: const Icon(Icons.timelapse),
                label: const Text('Set busy 30 mins'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onChanged(false);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xffdc2626),
                  side: const BorderSide(color: Color(0xfffecaca)),
                ),
                icon: const Icon(Icons.today_outlined),
                label: const Text('Close for the day'),
              ),
            ],
          ),
          const Divider(height: 28),
          Text(
            'Opening hours',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<StoreOpeningHour>>(
            stream: repository.watchStoreOpeningHours(store.id),
            builder: (context, snapshot) {
              final hours = snapshot.data ?? const <StoreOpeningHour>[];
              return Column(
                children: [
                  for (var day = 0; day < 7; day++)
                    _OpeningHourRow(
                      repository: repository,
                      storeId: store.id,
                      dayOfWeek: day,
                      hour: _openingHourForDay(hours, day),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OpeningHourRow extends StatelessWidget {
  const _OpeningHourRow({
    required this.repository,
    required this.storeId,
    required this.dayOfWeek,
    required this.hour,
  });

  final PlatformRepository repository;
  final String storeId;
  final int dayOfWeek;
  final StoreOpeningHour? hour;

  @override
  Widget build(BuildContext context) {
    final label = hour == null
        ? 'Default open'
        : hour!.isClosed
            ? 'Closed'
            : '${hour!.opensAt} - ${hour!.closesAt}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule),
      title: Text(_dayName(dayOfWeek)),
      subtitle: Text(label),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Edit hours',
            onPressed: () async {
              final draft = await showDialog<_OpeningHourDraft>(
                context: context,
                builder: (context) => _OpeningHourDialog(
                  dayOfWeek: dayOfWeek,
                  hour: hour,
                ),
              );
              if (draft == null) {
                return;
              }
              await repository.upsertStoreOpeningHour(
                storeId: storeId,
                dayOfWeek: dayOfWeek,
                opensAt: draft.opensAt,
                closesAt: draft.closesAt,
                isClosed: draft.isClosed,
              );
            },
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
          IconButton(
            tooltip: 'Closed',
            onPressed: () => repository.upsertStoreOpeningHour(
              storeId: storeId,
              dayOfWeek: dayOfWeek,
              opensAt: '09:00',
              closesAt: '21:00',
              isClosed: true,
            ),
            icon: const Icon(Icons.block),
          ),
        ],
      ),
    );
  }
}

class _OpeningHourDraft {
  const _OpeningHourDraft({
    required this.opensAt,
    required this.closesAt,
    required this.isClosed,
  });

  final String opensAt;
  final String closesAt;
  final bool isClosed;
}

class _OpeningHourDialog extends StatefulWidget {
  const _OpeningHourDialog({
    required this.dayOfWeek,
    required this.hour,
  });

  final int dayOfWeek;
  final StoreOpeningHour? hour;

  @override
  State<_OpeningHourDialog> createState() => _OpeningHourDialogState();
}

class _OpeningHourDialogState extends State<_OpeningHourDialog> {
  late var _opensAt = _parseTimeOfDay(widget.hour?.opensAt) ??
      const TimeOfDay(hour: 9, minute: 0);
  late var _closesAt = _parseTimeOfDay(widget.hour?.closesAt) ??
      const TimeOfDay(hour: 21, minute: 0);
  late var _isClosed = widget.hour?.isClosed ?? false;

  Future<void> _pickOpenTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _opensAt,
    );
    if (value != null) {
      setState(() => _opensAt = value);
    }
  }

  Future<void> _pickCloseTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _closesAt,
    );
    if (value != null) {
      setState(() => _closesAt = value);
    }
  }

  void _save() {
    Navigator.of(context).pop(
      _OpeningHourDraft(
        opensAt: _formatTimeOfDayForDb(_opensAt),
        closesAt: _formatTimeOfDayForDb(_closesAt),
        isClosed: _isClosed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${_dayName(widget.dayOfWeek)} hours'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Closed for this day'),
            value: _isClosed,
            onChanged: (value) => setState(() => _isClosed = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isClosed ? null : _pickOpenTime,
                  icon: const Icon(Icons.schedule),
                  label: Text('Open ${_opensAt.format(context)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isClosed ? null : _pickCloseTime,
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text('Close ${_closesAt.format(context)}'),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({
    required this.repository,
    required this.profile,
    required this.onSignOut,
  });

  final PlatformRepository repository;
  final UserProfile? profile;
  final Future<void> Function() onSignOut;

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

  Future<void> _signOut() async {
    Navigator.of(context).pop();
    await widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage account'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(widget.profile?.fullName.isNotEmpty == true
                    ? widget.profile!.fullName
                    : 'Store account'),
                subtitle: Text(
                  [
                    if (widget.profile?.role.isNotEmpty == true)
                      _humanStatus(widget.profile!.role),
                    if (widget.profile?.phone != null &&
                        widget.profile!.phone!.trim().isNotEmpty)
                      widget.profile!.phone!,
                  ].join(' | '),
                ),
              ),
              const Divider(),
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
        TextButton.icon(
          onPressed: _isSaving ? null : _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
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

class _InventoryPane extends StatefulWidget {
  const _InventoryPane({
    required this.repository,
    required this.storeId,
    required this.onAvailabilityChanged,
    required this.onUnavailabilityModeChanged,
    required this.onCreateProduct,
  });

  final PlatformRepository repository;
  final String storeId;
  final Future<void> Function(StoreInventoryItem product, bool value)
      onAvailabilityChanged;
  final Future<void> Function(StoreInventoryItem product, String mode)
      onUnavailabilityModeChanged;
  final VoidCallback onCreateProduct;

  @override
  State<_InventoryPane> createState() => _InventoryPaneState();
}

class _InventoryPaneState extends State<_InventoryPane> {
  final _searchController = TextEditingController();
  final _updatingAvailabilityProductIds = <String>{};
  late Stream<List<StoreInventoryItem>> _inventoryStream;
  var _lastProducts = const <StoreInventoryItem>[];
  var _selectedCategory = 'all';

  @override
  void initState() {
    super.initState();
    _inventoryStream = widget.repository.watchStoreInventory(widget.storeId);
  }

  @override
  void didUpdateWidget(covariant _InventoryPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId ||
        oldWidget.repository != widget.repository) {
      _lastProducts = const <StoreInventoryItem>[];
      _inventoryStream = widget.repository.watchStoreInventory(widget.storeId);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshInventory() {
    setState(() {
      _inventoryStream = widget.repository.watchStoreInventory(widget.storeId);
    });
  }

  Future<void> _handleAvailabilityChanged(
    StoreInventoryItem product,
    bool value,
  ) async {
    if (_updatingAvailabilityProductIds.contains(product.productId)) {
      return;
    }
    setState(() => _updatingAvailabilityProductIds.add(product.productId));
    try {
      await widget.onAvailabilityChanged(product, value);
    } finally {
      if (mounted) {
        setState(
          () => _updatingAvailabilityProductIds.remove(product.productId),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoreInventoryItem>>(
      stream: _inventoryStream,
      initialData: _lastProducts,
      builder: (context, snapshot) {
        final products = snapshot.data ?? _lastProducts;
        if (snapshot.hasData) {
          _lastProducts = products;
        }

        if (snapshot.hasError && products.isEmpty) {
          return _InlineState(
            title: 'Inventory failed to load',
            message: '${snapshot.error}\n\nMake sure this signed-in user is a '
                'member of the selected store.',
            action: FilledButton.icon(
              onPressed: _refreshInventory,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            products.isEmpty) {
          return const _InlineState(
            title: 'Loading inventory',
            message: 'Fetching products and stock...',
            isLoading: true,
          );
        }

        final categories = _inventoryCategories(products);
        if (_selectedCategory != 'all' &&
            !categories.contains(_selectedCategory)) {
          _selectedCategory = 'all';
        }
        final visibleProducts = products.where((product) {
          final matchesCategory = _selectedCategory == 'all' ||
              product.category == _selectedCategory;
          final matchesSearch = _matchesInventorySearch(
            product,
            _searchController.text,
          );
          return matchesCategory && matchesSearch;
        }).toList();

        if (products.isEmpty) {
          return _InlineState(
            title: 'No products yet',
            message: 'Add your first product to publish it to customers.',
            action: FilledButton.icon(
              onPressed: widget.onCreateProduct,
              icon: const Icon(Icons.add_box),
              label: const Text('Add product'),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _InventoryHeader(
              products: products,
              hasRefreshError: snapshot.hasError,
              categories: categories,
              selectedCategory: _selectedCategory,
              searchController: _searchController,
              onCreateProduct: widget.onCreateProduct,
              onRefresh: _refreshInventory,
              onSearchChanged: () => setState(() {}),
              onCategorySelected: (category) =>
                  setState(() => _selectedCategory = category),
            ),
            const SizedBox(height: 12),
            if (visibleProducts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No products match these filters')),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount =
                      (constraints.maxWidth / 184).floor().clamp(2, 6);
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: visibleProducts.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    itemBuilder: (context, index) => _InventoryProductCard(
                      product: visibleProducts[index],
                      repository: widget.repository,
                      isUpdating: _updatingAvailabilityProductIds.contains(
                        visibleProducts[index].productId,
                      ),
                      onAvailabilityChanged: _handleAvailabilityChanged,
                      onUnavailabilityModeChanged:
                          widget.onUnavailabilityModeChanged,
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _InventoryHeader extends StatelessWidget {
  const _InventoryHeader({
    required this.products,
    required this.hasRefreshError,
    required this.categories,
    required this.selectedCategory,
    required this.searchController,
    required this.onCreateProduct,
    required this.onRefresh,
    required this.onSearchChanged,
    required this.onCategorySelected,
  });

  final List<StoreInventoryItem> products;
  final bool hasRefreshError;
  final List<String> categories;
  final String selectedCategory;
  final TextEditingController searchController;
  final VoidCallback onCreateProduct;
  final VoidCallback onRefresh;
  final VoidCallback onSearchChanged;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    final liveCount = products
        .where((product) =>
            product.storeMarkedAvailable &&
            (product.unavailableUntil == null ||
                product.unavailableUntil!.isBefore(DateTime.now())))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Menu & inventory',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            FilledButton.icon(
              onPressed: onCreateProduct,
              icon: const Icon(Icons.add_box),
              label: const Text('Add product'),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Refresh inventory',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (hasRefreshError) ...[
          const SizedBox(height: 8),
          const _InventoryNotice(
            icon: Icons.cloud_sync_outlined,
            message: 'Showing the latest saved inventory. Pulling fresh stock '
                'again in the background.',
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InventoryMetricPill(
              icon: Icons.restaurant_menu,
              label: '${products.length} products',
              color: const Color(0xff2563eb),
            ),
            _InventoryMetricPill(
              icon: Icons.check_circle,
              label: '$liveCount live',
              color: const Color(0xff16a34a),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
            labelText: 'Search menu, inventory, or SKU',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: selectedCategory == 'all',
              onSelected: (_) => onCategorySelected('all'),
            ),
            for (final category in categories)
              ChoiceChip(
                label: Text(_humanStatus(category)),
                selected: selectedCategory == category,
                onSelected: (_) => onCategorySelected(category),
              ),
          ],
        ),
      ],
    );
  }
}

class _InventoryMetricPill extends StatelessWidget {
  const _InventoryMetricPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryNotice extends StatelessWidget {
  const _InventoryNotice({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(icon, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryProductCard extends StatelessWidget {
  const _InventoryProductCard({
    required this.product,
    required this.repository,
    required this.isUpdating,
    required this.onAvailabilityChanged,
    required this.onUnavailabilityModeChanged,
  });

  final StoreInventoryItem product;
  final PlatformRepository repository;
  final bool isUpdating;
  final Future<void> Function(StoreInventoryItem product, bool value)
      onAvailabilityChanged;
  final Future<void> Function(StoreInventoryItem product, String mode)
      onUnavailabilityModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unavailableToday = product.unavailableUntil != null &&
        product.unavailableUntil!.isAfter(DateTime.now());
    final available = product.storeMarkedAvailable && !unavailableToday;
    final statusColor = available
        ? Colors.green.shade700
        : unavailableToday
            ? Colors.orange.shade800
            : theme.colorScheme.error;
    final statusText = available
        ? 'Live'
        : unavailableToday
            ? 'Today'
            : 'Hidden';

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => _InventoryItemDetailPage(
              repository: repository,
              initialProduct: product,
              onAvailabilityChanged: onAvailabilityChanged,
              onUnavailabilityModeChanged: onUnavailabilityModeChanged,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 2.15,
                child: _InventoryProductImage(
                  imageUrl: product.imageUrl,
                  fallbackIcon: Icons.restaurant_menu,
                  iconColor: statusColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.82,
                    child: Switch(
                      value: available,
                      onChanged: isUpdating
                          ? null
                          : (value) => unawaited(
                                onAvailabilityChanged(product, value),
                              ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _humanStatus(product.category),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  _InventoryProductRating(
                    repository: repository,
                    productId: product.productId,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatNaira(product.price),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _InventoryBadge(
                    icon: available
                        ? Icons.check_circle
                        : Icons.visibility_off_outlined,
                    label: statusText,
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                available
                    ? 'Available to customers'
                    : unavailableToday
                        ? 'Unavailable today'
                        : 'Unavailable to customers',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryItemDetailPage extends StatefulWidget {
  const _InventoryItemDetailPage({
    required this.repository,
    required this.initialProduct,
    required this.onAvailabilityChanged,
    required this.onUnavailabilityModeChanged,
  });

  final PlatformRepository repository;
  final StoreInventoryItem initialProduct;
  final Future<void> Function(StoreInventoryItem product, bool value)
      onAvailabilityChanged;
  final Future<void> Function(StoreInventoryItem product, String mode)
      onUnavailabilityModeChanged;

  @override
  State<_InventoryItemDetailPage> createState() =>
      _InventoryItemDetailPageState();
}

class _InventoryItemDetailPageState extends State<_InventoryItemDetailPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final TextEditingController _reorderController;
  late final TextEditingController _skuController;
  late final TextEditingController _imageUrlController;
  bool _isSaving = false;
  bool _isUpdatingAvailability = false;
  bool _isUploadingImages = false;

  @override
  void initState() {
    super.initState();
    final product = widget.initialProduct;
    _nameController = TextEditingController(text: product.name);
    _descriptionController = TextEditingController(text: product.description);
    _categoryController = TextEditingController(text: product.category);
    _priceController =
        TextEditingController(text: product.price.toStringAsFixed(2));
    _stockController =
        TextEditingController(text: product.quantityOnHand.toString());
    _reorderController =
        TextEditingController(text: product.reorderLevel.toString());
    _skuController = TextEditingController(text: product.sku ?? '');
    _imageUrlController = TextEditingController(
      text: (product.imageUrls.isEmpty
              ? [
                  if (product.imageUrl != null) product.imageUrl!,
                ]
              : product.imageUrls)
          .join('\n'),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    _skuController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _save(StoreInventoryItem product) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    final targetStock = int.parse(_stockController.text.trim());
    final stockDelta = targetStock - product.quantityOnHand;

    try {
      await widget.repository.updateProduct(
        productId: product.productId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        category: _categoryController.text.trim().isEmpty
            ? 'general'
            : _categoryController.text.trim(),
        reorderLevel: int.parse(_reorderController.text.trim()),
        sku: _skuController.text.trim().isEmpty
            ? null
            : _skuController.text.trim(),
        imageUrl: _primaryImageUrl(_imageUrlsFromController(
          _imageUrlController,
        )),
        imageUrls: _imageUrlsFromController(_imageUrlController),
        isAvailable: product.storeMarkedAvailable,
      );

      if (stockDelta != 0) {
        await widget.repository.adjustInventory(
          productId: product.productId,
          delta: stockDelta,
          reason: 'correction',
          note: 'Set exact stock from inventory detail page',
        );
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Updated ${_nameController.text.trim()}')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Inventory update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _setAvailability(StoreInventoryItem product, bool value) async {
    if (_isUpdatingAvailability) {
      return;
    }
    setState(() => _isUpdatingAvailability = true);
    try {
      await widget.onAvailabilityChanged(product, value);
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAvailability = false);
      }
    }
  }

  Future<void> _setUnavailabilityMode(
    StoreInventoryItem product,
    String mode,
  ) async {
    if (_isUpdatingAvailability) {
      return;
    }
    setState(() => _isUpdatingAvailability = true);
    try {
      await widget.onUnavailabilityModeChanged(product, mode);
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAvailability = false);
      }
    }
  }

  Future<void> _uploadImages(StoreInventoryItem product) async {
    final files = await _pickProductImages();
    if (files.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isUploadingImages = true);
    try {
      final uploadedUrls = <String>[];
      for (final file in files) {
        final imageUrl = await widget.repository.uploadProductImage(
          storeId: product.storeId,
          fileName: file.name,
          bytes: file.bytes,
          contentType: _contentTypeForFile(file.name),
        );
        uploadedUrls.add(imageUrl);
      }
      final urls = {
        ..._imageUrlsFromController(_imageUrlController),
        ...uploadedUrls,
      }.toList(growable: false);
      _imageUrlController.text = urls.join('\n');
      messenger.showSnackBar(
        SnackBar(content: Text('${uploadedUrls.length} image(s) uploaded')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Image upload failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingImages = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoreInventoryItem>>(
      stream:
          widget.repository.watchStoreInventory(widget.initialProduct.storeId),
      builder: (context, snapshot) {
        final product = _currentInventoryItemFromSnapshot(
          snapshot.data,
          widget.initialProduct,
        );
        final unavailableToday = product.unavailableUntil != null &&
            product.unavailableUntil!.isAfter(DateTime.now());
        final available = product.storeMarkedAvailable && !unavailableToday;
        final statusColor = available
            ? const Color(0xff16a34a)
            : unavailableToday
                ? Colors.orange.shade800
                : Theme.of(context).colorScheme.error;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(product.name),
            actions: [
              IconButton(
                tooltip: 'Movement history',
                icon: const Icon(Icons.history),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => _InventoryMovementDialog(
                    repository: widget.repository,
                    product: product,
                  ),
                ),
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 108),
              children: [
                _InventoryProductImage(
                  imageUrl: product.imageUrl,
                  fallbackIcon: Icons.restaurant_menu,
                  iconColor: statusColor,
                  height: 220,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _InventoryBadge(
                        icon: available
                            ? Icons.check_circle
                            : Icons.visibility_off_outlined,
                        label: available
                            ? 'Available to customers'
                            : unavailableToday
                                ? 'Unavailable today'
                                : 'Hidden from customers',
                        color: statusColor,
                      ),
                    ),
                    Switch(
                      value: available,
                      onChanged: _isSaving || _isUpdatingAvailability
                          ? null
                          : (value) => unawaited(
                                _setAvailability(product, value),
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionPanel(
                  title: 'Product details',
                  children: [
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isSaving,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Product name',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredText,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      enabled: !_isSaving,
                      textInputAction: TextInputAction.next,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Detailed description',
                        helperText: 'Ingredients, sizes, prep notes, allergens',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _categoryController,
                      enabled: !_isSaving,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredText,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _priceController,
                            enabled: !_isSaving,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Price',
                              border: OutlineInputBorder(),
                            ),
                            validator: _positiveNumber,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _skuController,
                            enabled: !_isSaving,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'SKU',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _imageUrlController,
                      enabled: !_isSaving,
                      textInputAction: TextInputAction.next,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Gallery image URLs',
                        helperText:
                            'One URL per line. The first image is primary.',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    _ProductImagePreviewStrip(
                      imageUrls: _imageUrlsFromController(_imageUrlController),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isSaving || _isUploadingImages
                          ? null
                          : () => unawaited(_uploadImages(product)),
                      icon: const Icon(Icons.upload_file),
                      label: Text(
                        _isUploadingImages
                            ? 'Uploading...'
                            : 'Upload product images',
                      ),
                    ),
                  ],
                ),
                _SectionPanel(
                  title: 'Menu status',
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _isSaving || _isUpdatingAvailability
                              ? null
                              : () => unawaited(
                                    _setUnavailabilityMode(
                                      product,
                                      'available',
                                    ),
                                  ),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Available now'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isSaving || _isUpdatingAvailability
                              ? null
                              : () => unawaited(
                                    _setUnavailabilityMode(product, 'today'),
                                  ),
                          icon: const Icon(Icons.today_outlined),
                          label: const Text('Unavailable today'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isSaving || _isUpdatingAvailability
                              ? null
                              : () => unawaited(
                                    _setUnavailabilityMode(
                                      product,
                                      'indefinite',
                                    ),
                                  ),
                          icon: const Icon(Icons.block),
                          label: const Text('Unavailable indefinitely'),
                        ),
                      ],
                    ),
                  ],
                ),
                _SectionPanel(
                  title: 'Customer item reviews',
                  children: [
                    _InventoryProductRating(
                      repository: widget.repository,
                      productId: product.productId,
                    ),
                  ],
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : () => _save(product),
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? 'Saving...' : 'Save changes'),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InventoryProductRating extends StatelessWidget {
  const _InventoryProductRating({
    required this.repository,
    required this.productId,
    this.compact = false,
  });

  final PlatformRepository repository;
  final String productId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProductReviewSummary>>(
      stream: repository.watchProductReviews(productId),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? const <ProductReviewSummary>[];
        if (reviews.isEmpty) {
          return compact
              ? const SizedBox.shrink()
              : const Text('Delivered item reviews will appear here.');
        }

        final average =
            reviews.fold<int>(0, (sum, review) => sum + review.rating) /
                reviews.length;
        if (compact) {
          return _InventoryBadge(
            icon: Icons.star,
            label: average.toStringAsFixed(1),
            color: const Color(0xffca8a04),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _InventoryBadge(
                  icon: Icons.star,
                  label: '${average.toStringAsFixed(1)}/5',
                  color: const Color(0xffca8a04),
                ),
                const SizedBox(width: 8),
                Text(
                  '${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final review in reviews.take(5)) ...[
              _StoreProductReviewTile(review: review),
              if (review != reviews.take(5).last) const Divider(height: 18),
            ],
          ],
        );
      },
    );
  }
}

class _StoreProductReviewTile extends StatelessWidget {
  const _StoreProductReviewTile({required this.review});

  final ProductReviewSummary review;

  @override
  Widget build(BuildContext context) {
    final comment = review.comment?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                review.customerName?.trim().isNotEmpty == true
                    ? review.customerName!
                    : 'Customer',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Text(_stars(review.rating)),
          ],
        ),
        if (comment != null && comment.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(comment),
        ],
        const SizedBox(height: 4),
        Text(
          _formatDateTime(review.updatedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _InventoryProductImage extends StatelessWidget {
  const _InventoryProductImage({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.iconColor,
    this.height,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final Color iconColor;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: url == null || url.isEmpty
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(fallbackIcon, color: iconColor, size: 38),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(fallbackIcon, color: iconColor, size: 38),
                ),
              ),
      ),
    );
  }
}

class _InventoryBadge extends StatelessWidget {
  const _InventoryBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreSettlementsPane extends StatelessWidget {
  const _StoreSettlementsPane({
    required this.repository,
    required this.storeId,
  });

  final PlatformRepository repository;
  final String storeId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoreSettlementSummary>>(
      stream: repository.watchStoreSettlements(storeId: storeId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Settlements failed to load',
            message: '${snapshot.error}',
          );
        }

        final settlements = snapshot.data ?? const <StoreSettlementSummary>[];
        final pendingTotal = settlements
            .where((item) => item.status == 'pending')
            .fold<double>(0, (total, item) => total + item.payoutAmount);
        final paidTotal = settlements
            .where((item) => item.status == 'paid')
            .fold<double>(0, (total, item) => total + item.payoutAmount);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Settlements',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('Pending ${_formatNaira(pendingTotal)}')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OperationsStat(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Pending',
                  value: _formatNaira(pendingTotal),
                ),
                _OperationsStat(
                  icon: Icons.verified_outlined,
                  label: 'Paid',
                  value: _formatNaira(paidTotal),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (settlements.isEmpty)
              const Text('Paid order payouts will appear here.')
            else
              for (final settlement in settlements.take(20))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(
                      'Order #${_shortId(settlement.orderId)} | ${_formatNaira(settlement.payoutAmount)}',
                    ),
                    subtitle: Text(
                      'Items ${_formatNaira(settlement.grossItemsAmount)} | '
                      'Discount ${_formatNaira(settlement.discountAmount)} | '
                      '${_humanStatus(settlement.status)}',
                    ),
                    trailing: settlement.paidAt == null
                        ? null
                        : Text(_formatDateTime(settlement.paidAt!)),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _StoreIssuesPane extends StatefulWidget {
  const _StoreIssuesPane({
    required this.repository,
  });

  final PlatformRepository repository;

  @override
  State<_StoreIssuesPane> createState() => _StoreIssuesPaneState();
}

class _StoreIssuesPaneState extends State<_StoreIssuesPane> {
  var _filter = 'open';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderIssueSummary>>(
      stream: widget.repository.watchOrderIssues(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Support issues failed to load',
            message: '${snapshot.error}',
          );
        }

        final issues = snapshot.data ?? const <OrderIssueSummary>[];
        final visibleIssues = issues.where((issue) {
          return switch (_filter) {
            'open' => issue.status == 'open',
            'in_review' => issue.status == 'in_review',
            'resolved' => issue.status == 'resolved',
            'closed' => issue.status == 'closed',
            'all' => true,
            _ => true,
          };
        }).toList();
        final openCount =
            issues.where((issue) => issue.status == 'open').length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Support issues',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('$openCount open')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in const [
                  'open',
                  'in_review',
                  'resolved',
                  'closed',
                  'all',
                ])
                  ChoiceChip(
                    label: Text(_humanStatus(status)),
                    selected: _filter == status,
                    onSelected: (_) => setState(() => _filter = status),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (issues.isEmpty)
              const Text('No customer issues yet')
            else if (visibleIssues.isEmpty)
              const Text('No issues match this status')
            else
              for (final issue in visibleIssues.take(20))
                _StoreIssueTile(issue: issue),
          ],
        );
      },
    );
  }
}

class _StoreIssueTile extends StatelessWidget {
  const _StoreIssueTile({required this.issue});

  final OrderIssueSummary issue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_humanStatus(issue.category)} | #${_shortId(issue.orderId)}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Chip(label: Text(_humanStatus(issue.status))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_humanStatus(issue.orderStatus)} | '
            '${_humanStatus(issue.paymentStatus)} | '
            'NGN ${issue.totalAmount.toStringAsFixed(2)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(issue.message),
          if (issue.adminNote != null && issue.adminNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Admin note: ${issue.adminNote}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          _OrderContactLine(
            icon: Icons.person_outline,
            label: 'Customer',
            value: _contactText(
              name: issue.customerName,
              phone: issue.customerPhone,
              fallback: 'Customer ${_shortId(issue.customerId)}',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Updated ${_formatDateTime(issue.updatedAt)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StoreReviewsPane extends StatelessWidget {
  const _StoreReviewsPane({
    required this.repository,
    required this.storeId,
  });

  final PlatformRepository repository;
  final String storeId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderReviewSummary>>(
      stream: repository.watchOrderReviews(storeId: storeId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Reviews failed to load',
            message: '${snapshot.error}',
          );
        }

        final reviews = snapshot.data ?? const <OrderReviewSummary>[];
        final average = reviews.isEmpty
            ? 0.0
            : reviews.fold<int>(0, (total, review) => total + review.rating) /
                reviews.length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reviews',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.star_outline, size: 18),
                  label: Text(
                    reviews.isEmpty
                        ? 'No ratings'
                        : '${average.toStringAsFixed(1)}/5',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (reviews.isEmpty)
              const Text('Delivered order reviews will appear here.')
            else
              for (final review in reviews.take(20))
                _StoreReviewTile(review: review),
          ],
        );
      },
    );
  }
}

class _StoreReviewTile extends StatelessWidget {
  const _StoreReviewTile({required this.review});

  final OrderReviewSummary review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order #${_shortId(review.orderId)}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Chip(
                avatar: const Icon(Icons.star_outline, size: 18),
                label: Text('${review.rating}/5'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _OrderContactLine(
            icon: Icons.person_outline,
            label: 'Customer',
            value: _contactText(
              name: review.customerName,
              phone: review.customerPhone,
              fallback: 'Customer ${_shortId(review.customerId)}',
            ),
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment!),
          ],
          const SizedBox(height: 4),
          Text(
            'Updated ${_formatDateTime(review.updatedAt)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StorePromosPane extends StatefulWidget {
  const _StorePromosPane({
    required this.repository,
    required this.storeId,
  });

  final PlatformRepository repository;
  final String storeId;

  @override
  State<_StorePromosPane> createState() => _StorePromosPaneState();
}

class _StorePromosPaneState extends State<_StorePromosPane> {
  Future<void> _openPromoDialog([PromoCodeSummary? promo]) {
    return showDialog<void>(
      context: context,
      builder: (context) => _StorePromoCodeDialog(
        repository: widget.repository,
        storeId: widget.storeId,
        promo: promo,
      ),
    );
  }

  Future<void> _deletePromo(PromoCodeSummary promo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${promo.code}?'),
        content: const Text(
          'Codes with redemptions will be deactivated so order history stays intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.deleteStorePromoCode(promo.id);
      messenger.showSnackBar(const SnackBar(content: Text('Promo removed')));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Promo removal failed: $error')),
      );
    }
  }

  Future<void> _togglePromo(PromoCodeSummary promo) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.updateStorePromoCode(
        promoId: promo.id,
        code: promo.code,
        discountType: promo.discountType,
        discountValue: promo.discountValue,
        description: promo.description,
        minOrderAmount: promo.minOrderAmount,
        maxRedemptions: promo.maxRedemptions,
        isActive: !promo.isActive,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(promo.isActive ? 'Promo paused' : 'Promo activated'),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Promo update failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PromoCodeSummary>>(
      stream: widget.repository.watchPromoCodes(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Promos failed to load',
            message: '${snapshot.error}',
          );
        }

        final promos = (snapshot.data ?? const <PromoCodeSummary>[])
            .where((promo) =>
                promo.storeId == null || promo.storeId == widget.storeId)
            .toList();
        final storePromos =
            promos.where((promo) => promo.storeId == widget.storeId).toList();
        final platformPromos =
            promos.where((promo) => promo.storeId == null).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Promo codes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => unawaited(_openPromoDialog()),
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (storePromos.isEmpty)
              const Text('No store promo codes yet.')
            else
              for (final promo in storePromos.take(20))
                _StorePromoTile(
                  promo: promo,
                  onEdit: () => unawaited(_openPromoDialog(promo)),
                  onToggleActive: () => unawaited(_togglePromo(promo)),
                  onDelete: () => unawaited(_deletePromo(promo)),
                ),
            if (platformPromos.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Platform promos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final promo in platformPromos.take(10))
                _StorePromoTile(promo: promo),
            ],
          ],
        );
      },
    );
  }
}

class _StorePromoTile extends StatelessWidget {
  const _StorePromoTile({
    required this.promo,
    this.onEdit,
    this.onToggleActive,
    this.onDelete,
  });

  final PromoCodeSummary promo;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleActive;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discount = promo.discountType == 'percent'
        ? '${promo.discountValue.toStringAsFixed(0)}%'
        : 'NGN ${promo.discountValue.toStringAsFixed(2)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_offer_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(promo.code, style: theme.textTheme.titleMedium),
                Text(
                    '$discount off | Min NGN ${promo.minOrderAmount.toStringAsFixed(2)}'),
                Text(
                  '${promo.redemptionCount}/${promo.maxRedemptions?.toString() ?? 'unlimited'} used',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Chip(
            label: Text(
              promo.storeId == null
                  ? 'Platform'
                  : promo.isActive
                      ? 'Active'
                      : 'Paused',
            ),
          ),
          if (onEdit != null || onToggleActive != null || onDelete != null)
            PopupMenuButton<String>(
              tooltip: 'Manage promo',
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit?.call();
                  case 'toggle':
                    onToggleActive?.call();
                  case 'delete':
                    onDelete?.call();
                }
              },
              itemBuilder: (context) => [
                if (onEdit != null)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                if (onToggleActive != null)
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(promo.isActive ? 'Pause' : 'Activate'),
                  ),
                if (onDelete != null)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Remove'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StorePromoCodeDialog extends StatefulWidget {
  const _StorePromoCodeDialog({
    required this.repository,
    required this.storeId,
    this.promo,
  });

  final PlatformRepository repository;
  final String storeId;
  final PromoCodeSummary? promo;

  @override
  State<_StorePromoCodeDialog> createState() => _StorePromoCodeDialogState();
}

class _StorePromoCodeDialogState extends State<_StorePromoCodeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _discountController;
  late final TextEditingController _minimumController;
  late final TextEditingController _maxRedemptionsController;
  late var _discountType = widget.promo?.discountType ?? 'percent';
  late var _isActive = widget.promo?.isActive ?? true;
  var _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final promo = widget.promo;
    _codeController = TextEditingController(text: promo?.code ?? '');
    _descriptionController =
        TextEditingController(text: promo?.description ?? '');
    _discountController = TextEditingController(
      text: promo == null ? '' : promo.discountValue.toStringAsFixed(2),
    );
    _minimumController = TextEditingController(
      text: promo == null ? '0' : promo.minOrderAmount.toStringAsFixed(2),
    );
    _maxRedemptionsController = TextEditingController(
      text: promo?.maxRedemptions?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _descriptionController.dispose();
    _discountController.dispose();
    _minimumController.dispose();
    _maxRedemptionsController.dispose();
    super.dispose();
  }

  String? _codeValidator(String? value) {
    if ((value ?? '').trim().length < 3) {
      return 'Use at least 3 characters';
    }
    return null;
  }

  String? _discountValidator(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || number <= 0) {
      return 'Enter a discount';
    }
    if (_discountType == 'percent' && number > 100) {
      return 'Use 100 or less';
    }
    return null;
  }

  String? _maxRedemptionsValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final number = int.tryParse(text);
    if (number == null || number <= 0) {
      return 'Enter a whole number';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final promo = widget.promo;
    try {
      final maxRedemptions = _maxRedemptionsController.text.trim().isEmpty
          ? null
          : int.parse(_maxRedemptionsController.text.trim());
      if (promo == null) {
        await widget.repository.createStorePromoCode(
          storeId: widget.storeId,
          code: _codeController.text.trim(),
          discountType: _discountType,
          discountValue: double.parse(_discountController.text.trim()),
          description: _descriptionController.text.trim(),
          minOrderAmount: double.parse(_minimumController.text.trim()),
          maxRedemptions: maxRedemptions,
          isActive: _isActive,
        );
      } else {
        await widget.repository.updateStorePromoCode(
          promoId: promo.id,
          code: _codeController.text.trim(),
          discountType: _discountType,
          discountValue: double.parse(_discountController.text.trim()),
          description: _descriptionController.text.trim(),
          minOrderAmount: double.parse(_minimumController.text.trim()),
          maxRedemptions: maxRedemptions,
          isActive: _isActive,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
      messenger.showSnackBar(
        SnackBar(
            content: Text(promo == null ? 'Promo created' : 'Promo saved')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Promo save failed: ${_friendlyError(error)}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.promo == null ? 'Create promo code' : 'Edit promo'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _codeController,
                  enabled: !_isSubmitting,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    border: OutlineInputBorder(),
                  ),
                  validator: _codeValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'percent', label: Text('Percent')),
                    ButtonSegment(value: 'fixed', label: Text('Fixed')),
                  ],
                  selected: {_discountType},
                  onSelectionChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _discountType = value.single),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _discountController,
                        enabled: !_isSubmitting,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Discount',
                          border: OutlineInputBorder(),
                        ),
                        validator: _discountValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _minimumController,
                        enabled: !_isSubmitting,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minimum order',
                          border: OutlineInputBorder(),
                        ),
                        validator: _positiveNumber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxRedemptionsController,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max redemptions',
                    hintText: 'Unlimited',
                    border: OutlineInputBorder(),
                  ),
                  validator: _maxRedemptionsValidator,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _isActive,
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _isActive = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          icon: _isSubmitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSubmitting ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({
    required this.repository,
    required this.audience,
    required this.onPressed,
  });

  final PlatformRepository repository;
  final String audience;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: repository.watchUnreadNotificationCount(audience: audience),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        return IconButton(
          tooltip: 'Notifications',
          onPressed: onPressed,
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}

class _NotificationsPage extends StatefulWidget {
  const _NotificationsPage({
    required this.repository,
    required this.audience,
  });

  final PlatformRepository repository;
  final String audience;

  @override
  State<_NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<_NotificationsPage> {
  final Set<String> _readRequests = <String>{};

  void _markVisibleRead(List<UserNotification> notifications) {
    final unread = notifications.where((item) => !item.isRead);
    for (final notification in unread) {
      if (_readRequests.add(notification.id)) {
        scheduleMicrotask(
          () => widget.repository.markNotificationRead(notification.id),
        );
      }
    }
  }

  Future<void> _showNotificationActions(UserNotification notification) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.mark_email_read_outlined),
              title: const Text('Mark as read'),
              enabled: !notification.isRead,
              onTap: () => Navigator.of(context).pop('read'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      if (action == 'read') {
        await widget.repository.markNotificationRead(notification.id);
      } else if (action == 'delete') {
        await widget.repository.deleteNotification(notification.id);
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Notification update failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<UserNotification>>(
        stream: widget.repository.watchMyNotifications(
          audience: widget.audience,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _InlineState(
              title: 'Notifications failed to load',
              message: '${snapshot.error}',
            );
          }

          final notifications = snapshot.data ?? const <UserNotification>[];
          _markVisibleRead(notifications);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Notifications',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: notifications.any((item) => !item.isRead)
                          ? widget.repository.markAllNotificationsRead
                          : null,
                      icon: const Icon(Icons.done_all),
                      label: const Text('Read all'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: notifications.isEmpty
                    ? const Center(child: Text('No notifications yet'))
                    : ListView.separated(
                        itemCount: notifications.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final notification = notifications[index];
                          return ListTile(
                            leading: Icon(
                              notification.isRead
                                  ? Icons.notifications_none
                                  : Icons.notifications_active_outlined,
                            ),
                            title: Text(notification.title),
                            subtitle: Text(
                              [
                                if (notification.body.isNotEmpty)
                                  notification.body,
                                _formatDateTime(notification.createdAt),
                              ].join('\n'),
                            ),
                            isThreeLine: notification.body.isNotEmpty,
                            trailing: notification.isRead
                                ? null
                                : IconButton(
                                    tooltip: 'Mark read',
                                    icon: const Icon(
                                      Icons.mark_email_read_outlined,
                                    ),
                                    onPressed: () =>
                                        widget.repository.markNotificationRead(
                                      notification.id,
                                    ),
                                  ),
                            onLongPress: () =>
                                unawaited(_showNotificationActions(
                              notification,
                            )),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StoreTodayMetrics extends StatelessWidget {
  const _StoreTodayMetrics({required this.orders});

  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayOrders = orders
        .where((order) => _isSameLocalDay(order.createdAt, today))
        .toList();
    final payoutToday = todayOrders
        .where((order) => order.paymentStatus == 'paid')
        .fold<double>(0, (total, order) => total + order.storePayoutAmount);
    final paidOrders =
        todayOrders.where((order) => order.paymentStatus == 'paid').length;
    final activeOrders = orders.where(_isActiveStoreOrder).length;
    final readyOrders =
        orders.where((order) => order.status == 'ready_for_pickup').length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _OperationsStat(
          icon: Icons.payments_outlined,
          label: 'Payout today',
          value: _formatNaira(payoutToday),
        ),
        _OperationsStat(
          icon: Icons.receipt_long_outlined,
          label: 'Paid today',
          value: '$paidOrders',
        ),
        _OperationsStat(
          icon: Icons.local_fire_department_outlined,
          label: 'Active',
          value: '$activeOrders',
        ),
        _OperationsStat(
          icon: Icons.inventory_2_outlined,
          label: 'Ready',
          value: '$readyOrders',
        ),
      ],
    );
  }
}

class _OperationsStat extends StatelessWidget {
  const _OperationsStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreOrderCard extends StatelessWidget {
  const _StoreOrderCard({
    required this.repository,
    required this.order,
    required this.onStatusChanged,
    required this.onPreparationTimeChanged,
    required this.onModifyOrderItem,
    required this.onCancelOrder,
  });

  final PlatformRepository repository;
  final OrderSummary order;
  final void Function(OrderSummary order, String status) onStatusChanged;
  final void Function(OrderSummary order, int preparationMinutes)
      onPreparationTimeChanged;
  final void Function({
    required OrderSummary order,
    required OrderLineItem item,
    required String action,
    String? replacementProductId,
  }) onModifyOrderItem;
  final ValueChanged<OrderSummary> onCancelOrder;

  @override
  Widget build(BuildContext context) {
    final statusColor = _orderStatusColor(order.status);
    return StreamBuilder<List<OrderLineItem>>(
      stream: repository.watchOrderItems(order.id),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <OrderLineItem>[];
        final itemCount = _orderItemCount(items);
        final itemSummary = _storeOrderItemSummary(items, itemCount);
        final amount =
            order.itemsSubtotal > 0 ? order.itemsSubtotal : order.totalAmount;
        final customerName = order.customerName?.trim();
        final customerLabel = customerName == null || customerName.isEmpty
            ? 'Customer #${_shortId(order.customerId)}'
            : customerName;
        final orderMode =
            order.fulfillmentType == 'pickup' ? 'Pickup' : 'Delivery';
        final destination = order.fulfillmentType == 'pickup'
            ? 'Pickup order'
            : order.deliveryAddress.trim().isEmpty
                ? 'Delivery address pending'
                : order.deliveryAddress.trim();
        final orderMeta =
            '$orderMode - ${_formatDateTime(order.createdAt)} - #${_shortId(order.id)}';

        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => _StoreOrderDetailPage(
                  repository: repository,
                  initialOrder: order,
                  onStatusChanged: onStatusChanged,
                  onPreparationTimeChanged: onPreparationTimeChanged,
                  onModifyOrderItem: onModifyOrderItem,
                  onCancelOrder: onCancelOrder,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StoreOrderPreviewIcon(
                        color: statusColor,
                        status: order.status,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _StoreOrderStatusPill(
                              label: _statusSectionLabel(order.status),
                              color: statusColor,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              customerLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  order.fulfillmentType == 'pickup'
                                      ? Icons.shopping_bag_outlined
                                      : Icons.location_on_outlined,
                                  size: 16,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    orderMeta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              itemSummary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              destination,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatNaira(amount),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_storeOrderActionFor(order) != null) ...[
                    const SizedBox(height: 12),
                    _StoreOrderQuickAction(
                      order: order,
                      onStatusChanged: onStatusChanged,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StoreOrderPreviewIcon extends StatelessWidget {
  const _StoreOrderPreviewIcon({
    required this.color,
    required this.status,
  });

  final Color color;
  final String status;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      'paid' => Icons.receipt_long_outlined,
      'accepted' => Icons.task_alt_outlined,
      'preparing' => Icons.restaurant_outlined,
      'ready_for_pickup' => Icons.inventory_2_outlined,
      'out_for_delivery' => Icons.delivery_dining_outlined,
      'delivered' => Icons.done_all,
      'cancelled' => Icons.cancel_outlined,
      _ => Icons.shopping_bag_outlined,
    };

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }
}

class _StoreOrderStatusPill extends StatelessWidget {
  const _StoreOrderStatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    );
  }
}

class _StoreOrderQuickAction extends StatelessWidget {
  const _StoreOrderQuickAction({
    required this.order,
    required this.onStatusChanged,
  });

  final OrderSummary order;
  final void Function(OrderSummary order, String status) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final action = _storeOrderActionFor(order);
    if (action == null) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        onPressed: () => onStatusChanged(order, action.status),
        icon: Icon(action.icon, size: 18),
        label: Text(action.label),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _StoreOrderLifecyclePanel extends StatelessWidget {
  const _StoreOrderLifecyclePanel({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    final steps = _storeLifecycleSteps(order);
    final activeIndex = steps.indexWhere((step) => step.status == order.status);
    final currentIndex = activeIndex == -1
        ? _storeOrderStatusRankValue(order.status)
            .clamp(0, steps.length - 1)
            .toInt()
        : activeIndex;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfff8fafc),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: currentIndex.toDouble()),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        builder: (context, animatedIndex, _) {
          return Row(
            children: [
              for (var index = 0; index < steps.length; index++) ...[
                Expanded(
                  child: _LifecycleStepTile(
                    step: steps[index],
                    isComplete: animatedIndex >= index,
                    isCurrent: index == currentIndex,
                  ),
                ),
                if (index != steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 3,
                      color: animatedIndex > index
                          ? const Color(0xff16a34a)
                          : const Color(0xffe5e7eb),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LifecycleStepTile extends StatelessWidget {
  const _LifecycleStepTile({
    required this.step,
    required this.isComplete,
    required this.isCurrent,
  });

  final _StoreLifecycleStep step;
  final bool isComplete;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final color =
        isComplete ? const Color(0xff16a34a) : const Color(0xff9ca3af);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: isCurrent ? 38 : 32,
          height: isCurrent ? 38 : 32,
          decoration: BoxDecoration(
            color: isComplete ? color : Colors.white,
            border: Border.all(color: color, width: isCurrent ? 2 : 1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            step.icon,
            size: isCurrent ? 20 : 17,
            color: isComplete ? Colors.white : color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isCurrent ? const Color(0xff111827) : color,
                fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _StoreLifecycleStep {
  const _StoreLifecycleStep({
    required this.status,
    required this.label,
    required this.icon,
  });

  final String status;
  final String label;
  final IconData icon;
}

class _StoreOrderAction {
  const _StoreOrderAction({
    required this.status,
    required this.label,
    required this.icon,
  });

  final String status;
  final String label;
  final IconData icon;
}

class _StoreOrderDetailPage extends StatelessWidget {
  const _StoreOrderDetailPage({
    required this.repository,
    required this.initialOrder,
    required this.onStatusChanged,
    required this.onPreparationTimeChanged,
    required this.onModifyOrderItem,
    required this.onCancelOrder,
  });

  final PlatformRepository repository;
  final OrderSummary initialOrder;
  final void Function(OrderSummary order, String status) onStatusChanged;
  final void Function(OrderSummary order, int preparationMinutes)
      onPreparationTimeChanged;
  final void Function({
    required OrderSummary order,
    required OrderLineItem item,
    required String action,
    String? replacementProductId,
  }) onModifyOrderItem;
  final ValueChanged<OrderSummary> onCancelOrder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderSummary>>(
      stream: repository.watchStoreOrders(initialOrder.storeId),
      builder: (context, orderSnapshot) {
        final order = _currentOrderFromSnapshot(
          orderSnapshot.data,
          initialOrder,
        );
        return StreamBuilder<List<OrderLineItem>>(
          stream: repository.watchOrderItems(order.id),
          builder: (context, itemSnapshot) {
            final items = itemSnapshot.data ?? const <OrderLineItem>[];
            final itemCount = _orderItemCount(items);
            final canCancel = order.paymentStatus == 'paid' &&
                order.riderId == null &&
                (order.status == 'paid' ||
                    order.status == 'accepted' ||
                    order.status == 'preparing' ||
                    order.status == 'ready_for_pickup');
            final isFinished = _isFinishedStoreOrder(order);
            return Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                title: Text('Order #${_shortId(order.id)}'),
                actions: [
                  IconButton(
                    tooltip: 'Reprint ticket',
                    onPressed: () => _openTicketDialog(context, order),
                    icon: const Icon(Icons.print_outlined),
                  ),
                  IconButton(
                    tooltip: 'Decline order',
                    color: const Color(0xffdc2626),
                    onPressed: canCancel ? () => onCancelOrder(order) : null,
                    icon: const Icon(Icons.cancel_outlined),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
                children: [
                  _OrderDetailHeader(order: order, itemCount: itemCount),
                  const SizedBox(height: 14),
                  _StoreOrderLifecyclePanel(order: order),
                  if (!isFinished) ...[
                    const SizedBox(height: 14),
                    _PickupEstimatePanel(repository: repository, order: order),
                  ],
                  const SizedBox(height: 14),
                  _OrderTotalsPanel(order: order, itemCount: itemCount),
                  const SizedBox(height: 14),
                  _OrderItemsSummary(items: items),
                  if (_showsCustomerDetails(order)) ...[
                    const SizedBox(height: 14),
                    _CustomerDetailPanel(order: order),
                  ],
                  if (!isFinished) ...[
                    const SizedBox(height: 14),
                    _PrepTimePanel(
                      order: order,
                      onChanged: (minutes) =>
                          onPreparationTimeChanged(order, minutes),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _DeliveryEventsList(
                      repository: repository, orderId: order.id),
                  if (!isFinished && order.riderId != null) ...[
                    const SizedBox(height: 14),
                    _RiderLocationList(
                      repository: repository,
                      orderId: order.id,
                    ),
                  ],
                ],
              ),
              bottomNavigationBar: _StoreOrderActionBar(
                order: order,
                itemCount: itemCount,
                onAccept: () => onStatusChanged(order, 'accepted'),
                onPrepare: () => onStatusChanged(order, 'preparing'),
                onReady: () => onStatusChanged(order, 'ready_for_pickup'),
              ),
              floatingActionButton: _showsCustomerDetails(order)
                  ? FloatingActionButton.small(
                      tooltip: 'Modify order',
                      onPressed: () => _openModifyDialog(context, order),
                      child: const Icon(Icons.edit_note),
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  Future<void> _openModifyDialog(
    BuildContext context,
    OrderSummary order,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ModifyOrderDialog(
        repository: repository,
        order: order,
        onModifyOrderItem: onModifyOrderItem,
        onDecline: () => onCancelOrder(order),
      ),
    );
  }

  Future<void> _openTicketDialog(
    BuildContext context,
    OrderSummary order,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _OrderTicketDialog(
        repository: repository,
        order: order,
      ),
    );
  }
}

class _OrderContactLine extends StatelessWidget {
  const _OrderContactLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Expanded(child: Text('$label: $value')),
      ],
    );
  }
}

class _NewOrderDialog extends StatelessWidget {
  const _NewOrderDialog({
    required this.repository,
    required this.order,
    required this.onAccept,
  });

  final PlatformRepository repository;
  final OrderSummary order;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New order received'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Order ${_shortId(order.id)} | ${_formatNaira(order.totalAmount)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _OrderContactLine(
              icon: Icons.person_outline,
              label: 'Customer',
              value: _contactText(
                name: order.customerName,
                phone: order.customerPhone,
                fallback: 'Customer ${_shortId(order.customerId)}',
              ),
            ),
            const SizedBox(height: 8),
            _OrderItemsList(repository: repository, orderId: order.id),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            onAccept();
          },
          icon: const Icon(Icons.task_alt_outlined),
          label: const Text('Accept Order'),
        ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xffdcfce7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Color(0xff166534),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _OrderDetailHeader extends StatelessWidget {
  const _OrderDetailHeader({
    required this.order,
    required this.itemCount,
  });

  final OrderSummary order;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Order #${_shortId(order.id)}',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _IntentChip(
              label: _humanStatus(order.status),
              color: _orderStatusColor(order.status),
            ),
            _IntentChip(
              label: '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
              color: const Color(0xff111827),
            ),
            _IntentChip(
              label: _humanStatus(order.fulfillmentType),
              color: const Color(0xff2563eb),
            ),
          ],
        ),
      ],
    );
  }
}

class _PickupEstimatePanel extends StatelessWidget {
  const _PickupEstimatePanel({
    required this.repository,
    required this.order,
  });

  final PlatformRepository repository;
  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    final localEstimate = order.etaMinutes;
    return FutureBuilder<RiderPickupEstimate?>(
      future: repository.fetchNearestRiderPickupEstimate(order.storeId),
      builder: (context, snapshot) {
        final estimate = snapshot.data;
        final minutes =
            order.status == 'ready_for_pickup' && localEstimate != null
                ? localEstimate
                : estimate?.etaMinutes;
        final distance = estimate?.distanceKm;
        final text = minutes == null || minutes <= 0
            ? 'Pickup estimate unavailable'
            : 'Pickup in approximately ${minutes}m';
        return _InfoPanel(
          icon: Icons.delivery_dining_outlined,
          title: text,
          subtitle: distance == null
              ? 'No online rider location found yet.'
              : 'Nearest online rider is ${distance.toStringAsFixed(2)} km from this store.',
          accentColor: const Color(0xff16a34a),
        );
      },
    );
  }
}

class _OrderTotalsPanel extends StatelessWidget {
  const _OrderTotalsPanel({
    required this.order,
    required this.itemCount,
  });

  final OrderSummary order;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final storeTotal = order.itemsSubtotal > 0
        ? (order.itemsSubtotal - order.discountAmount).clamp(0, double.infinity)
        : order.totalAmount;
    return _SectionPanel(
      title: 'Order summary',
      children: [
        _AmountRow(label: 'Items', value: '$itemCount'),
        _AmountRow(label: 'Subtotal', value: _formatNaira(order.itemsSubtotal)),
        if (order.discountAmount > 0)
          _AmountRow(
            label: 'Discount',
            value: '-${_formatNaira(order.discountAmount)}',
            valueColor: const Color(0xff16a34a),
          ),
        const Divider(),
        _AmountRow(
          label: 'Store total',
          value: _formatNaira(storeTotal.toDouble()),
          emphasized: true,
        ),
      ],
    );
  }
}

class _OrderItemsSummary extends StatelessWidget {
  const _OrderItemsSummary({required this.items});

  final List<OrderLineItem> items;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: 'Items',
      children: [
        if (items.isEmpty)
          const Text('Order items will appear here.')
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xffdcfce7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        '${item.quantity}x',
                        style: const TextStyle(
                          color: Color(0xff166534),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.productName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(_formatNaira(item.lineTotal)),
                ],
              ),
            ),
      ],
    );
  }
}

class _CustomerDetailPanel extends StatelessWidget {
  const _CustomerDetailPanel({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: 'Customer',
      children: [
        _OrderContactLine(
          icon: Icons.person_outline,
          label: 'Name and phone',
          value: _contactText(
            name: order.customerName,
            phone: order.customerPhone,
            fallback: 'Customer ${_shortId(order.customerId)}',
          ),
        ),
        const SizedBox(height: 10),
        _OrderContactLine(
          icon: order.fulfillmentType == 'pickup'
              ? Icons.storefront_outlined
              : Icons.place_outlined,
          label: order.fulfillmentType == 'pickup' ? 'Pickup' : 'Address',
          value: order.fulfillmentType == 'pickup'
              ? 'Customer will pick up at the store.'
              : (order.deliveryAddress.isEmpty
                  ? 'No delivery address saved'
                  : order.deliveryAddress),
        ),
        if (order.riderId != null) ...[
          const SizedBox(height: 10),
          _OrderContactLine(
            icon: Icons.delivery_dining_outlined,
            label: 'Rider',
            value: _contactText(
              name: order.riderName,
              phone: order.riderPhone,
              fallback: 'Rider ${_shortId(order.riderId!)}',
            ),
          ),
        ],
      ],
    );
  }
}

class _PrepTimePanel extends StatelessWidget {
  const _PrepTimePanel({
    required this.order,
    required this.onChanged,
  });

  final OrderSummary order;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final minutes = order.preparationMinutes ?? order.etaMinutes ?? 20;
    return _SectionPanel(
      title: 'Preparation time',
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Set kitchen packing time before rider pickup.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final updated = await showDialog<int>(
                  context: context,
                  builder: (context) =>
                      _PreparationTimeDialog(initialMinutes: minutes),
                );
                if (updated != null) {
                  onChanged(updated);
                }
              },
              icon: const Icon(Icons.schedule),
              label: Text('$minutes min'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StoreOrderActionBar extends StatelessWidget {
  const _StoreOrderActionBar({
    required this.order,
    required this.itemCount,
    required this.onAccept,
    required this.onPrepare,
    required this.onReady,
  });

  final OrderSummary order;
  final int itemCount;
  final VoidCallback onAccept;
  final VoidCallback onPrepare;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    final canAccept = order.paymentStatus == 'paid' && order.status == 'paid';
    final canPrepare =
        order.paymentStatus == 'paid' && order.status == 'accepted';
    final canReady =
        order.paymentStatus == 'paid' && order.status == 'preparing';
    final itemLabel = '$itemCount ${itemCount == 1 ? 'item' : 'items'}';

    if (!canAccept && !canPrepare && !canReady) {
      return const SizedBox.shrink();
    }

    final actionColor = canAccept
        ? const Color(0xff16a34a)
        : canPrepare
            ? const Color(0xfff97316)
            : const Color(0xff2563eb);
    final actionIcon = canAccept
        ? Icons.task_alt_outlined
        : canPrepare
            ? Icons.restaurant_outlined
            : Icons.inventory_2_outlined;
    final actionLabel = canAccept
        ? 'Accept order ($itemLabel)'
        : canPrepare
            ? 'Start preparing ($itemLabel)'
            : '${order.fulfillmentType == 'pickup' ? 'Ready for pickup' : 'Ready for delivery'} ($itemLabel)';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: canAccept
                ? onAccept
                : canPrepare
                    ? onPrepare
                    : onReady,
            style: FilledButton.styleFrom(
              backgroundColor: actionColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: Icon(actionIcon),
            label: Text(
              actionLabel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        border: Border.all(color: accentColor.withValues(alpha: 0.26)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            )
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            value,
            style: style?.copyWith(
              color: valueColor,
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntentChip extends StatelessWidget {
  const _IntentChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _PreparationTimeDialog extends StatefulWidget {
  const _PreparationTimeDialog({required this.initialMinutes});

  final int initialMinutes;

  @override
  State<_PreparationTimeDialog> createState() => _PreparationTimeDialogState();
}

class _PreparationTimeDialogState extends State<_PreparationTimeDialog> {
  late int _minutes = widget.initialMinutes.clamp(1, 240);
  late final TextEditingController _controller =
      TextEditingController(text: '$_minutes');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setMinutes(int value) {
    final updated = value.clamp(1, 240);
    setState(() {
      _minutes = updated;
      _controller.text = '$_minutes';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final presets = [10, 15, 20, 25, 30, 45, 60];
    return AlertDialog(
      title: const Text('Estimated pickup time'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Rider pickup in $_minutes minutes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Custom time',
              suffixText: 'min',
              helperText: 'Enter any whole minute from 1 to 240.',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null) {
                setState(() => _minutes = parsed.clamp(1, 240));
              }
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in presets)
                ChoiceChip(
                  label: Text('$preset min'),
                  selected: _minutes == preset,
                  onSelected: (_) => _setMinutes(preset),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Remove 1 minute',
                onPressed:
                    _minutes <= 1 ? null : () => _setMinutes(_minutes - 1),
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Slider(
                  value: _minutes.clamp(1, 240).toDouble(),
                  min: 1,
                  max: 240,
                  divisions: 239,
                  label: '$_minutes min',
                  onChanged: (value) => _setMinutes(value.round()),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Add 1 minute',
                onPressed:
                    _minutes >= 240 ? null : () => _setMinutes(_minutes + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_minutes),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

class _ModifyOrderDialog extends StatefulWidget {
  const _ModifyOrderDialog({
    required this.repository,
    required this.order,
    required this.onModifyOrderItem,
    required this.onDecline,
  });

  final PlatformRepository repository;
  final OrderSummary order;
  final void Function({
    required OrderSummary order,
    required OrderLineItem item,
    required String action,
    String? replacementProductId,
  }) onModifyOrderItem;
  final VoidCallback onDecline;

  @override
  State<_ModifyOrderDialog> createState() => _ModifyOrderDialogState();
}

class _ModifyOrderDialogState extends State<_ModifyOrderDialog> {
  OrderLineItem? _selectedItem;
  StoreInventoryItem? _replacement;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modify order'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Call ${_contactText(name: widget.order.customerName, phone: widget.order.customerPhone, fallback: 'the customer')} before changing the order.',
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<OrderLineItem>>(
              stream: widget.repository.watchOrderItems(widget.order.id),
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <OrderLineItem>[];
                if (items.isEmpty) {
                  return const Text('No order items found.');
                }
                _selectedItem ??= items.first;
                return DropdownButtonFormField<OrderLineItem>(
                  initialValue: _selectedItem,
                  decoration: const InputDecoration(
                    labelText: 'Unavailable item',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final item in items)
                      DropdownMenuItem(
                        value: item,
                        child: Text('${item.productName} x${item.quantity}'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _selectedItem = value),
                );
              },
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<StoreInventoryItem>>(
              stream:
                  widget.repository.watchStoreInventory(widget.order.storeId),
              builder: (context, snapshot) {
                final products = (snapshot.data ?? const <StoreInventoryItem>[])
                    .where((product) => product.storeMarkedAvailable)
                    .toList();
                return DropdownButtonFormField<StoreInventoryItem>(
                  initialValue: _replacement,
                  decoration: const InputDecoration(
                    labelText: 'Replacement product',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final product in products)
                      DropdownMenuItem(
                        value: product,
                        child: Text(product.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _replacement = value),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onDecline();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xffdc2626),
            side: const BorderSide(color: Color(0xfffecaca)),
          ),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Decline order'),
        ),
        OutlinedButton.icon(
          onPressed: _selectedItem == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onModifyOrderItem(
                    order: widget.order,
                    item: _selectedItem!,
                    action: 'remove',
                  );
                },
          icon: const Icon(Icons.remove_shopping_cart_outlined),
          label: const Text('Continue without replacement'),
        ),
        FilledButton.icon(
          onPressed: _selectedItem == null || _replacement == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onModifyOrderItem(
                    order: widget.order,
                    item: _selectedItem!,
                    action: 'replace',
                    replacementProductId: _replacement!.productId,
                  );
                },
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Replace item'),
        ),
      ],
    );
  }
}

class _OrderTicketDialog extends StatelessWidget {
  const _OrderTicketDialog({
    required this.repository,
    required this.order,
  });

  final PlatformRepository repository;
  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Ticket #${_shortId(order.id)}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(order.storeName,
                style: Theme.of(context).textTheme.titleMedium),
            Text(
                'Customer: ${_contactText(name: order.customerName, phone: order.customerPhone, fallback: _shortId(order.customerId))}'),
            Text('Address: ${order.deliveryAddress}'),
            const Divider(),
            _OrderItemsList(repository: repository, orderId: order.id),
            const Divider(),
            Text('Total paid: ${_formatNaira(order.totalAmount)}'),
            if (order.cancellationReason != null &&
                order.cancellationReason!.isNotEmpty)
              Text('Cancellation: ${order.cancellationReason}'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () {
            SystemSound.play(SystemSoundType.click);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ticket ready for printer')),
            );
          },
          icon: const Icon(Icons.print_outlined),
          label: const Text('Reprint'),
        ),
      ],
    );
  }
}

class _RiderLocationList extends StatelessWidget {
  const _RiderLocationList({
    required this.repository,
    required this.orderId,
  });

  final PlatformRepository repository;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RiderLocationUpdate>>(
      stream: repository.watchRiderLocations(orderId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text('Rider location failed: ${snapshot.error}'),
          );
        }

        final locations = snapshot.data ?? const <RiderLocationUpdate>[];
        final latest = locations.isEmpty ? null : locations.first;
        if (latest == null) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Text('Rider live location will appear after pickup.'),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rider live location',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.my_location, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${latest.riderName ?? 'Rider'} at '
                    '${latest.latitude.toStringAsFixed(6)}, '
                    '${latest.longitude.toStringAsFixed(6)}\n'
                    'Updated ${_formatDateTime(latest.createdAt)}'
                    '${latest.accuracyMeters == null ? '' : ' | accuracy ${latest.accuracyMeters!.toStringAsFixed(0)}m'}',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DeliveryEventsList extends StatelessWidget {
  const _DeliveryEventsList({
    required this.repository,
    required this.orderId,
  });

  final PlatformRepository repository;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeliveryEvent>>(
      stream: repository.watchDeliveryEvents(orderId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text('Timeline failed: ${snapshot.error}'),
          );
        }

        final events = snapshot.data ?? const <DeliveryEvent>[];
        if (events.isEmpty) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Text('No delivery events yet.'),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Timeline', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final event in events) _DeliveryEventRow(event: event),
          ],
        );
      },
    );
  }
}

class _DeliveryEventRow extends StatelessWidget {
  const _DeliveryEventRow({required this.event});

  final DeliveryEvent event;

  @override
  Widget build(BuildContext context) {
    final note = event.note;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.radio_button_checked, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_humanStatus(event.status)}'
                  '${event.etaMinutes == null ? '' : ' | ETA ${event.etaMinutes}m'}',
                ),
                if (note != null && note.isNotEmpty)
                  Text(note, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  _formatDateTime(event.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
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
    this.action,
  });

  final String title;
  final String message;
  final bool isLoading;
  final Widget? action;

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
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

String? _requiredText(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }
  return null;
}

String? _positiveNumber(String? value) {
  final number = double.tryParse(value?.trim() ?? '');
  if (number == null || number < 0) {
    return 'Enter a valid number';
  }
  return null;
}

String? _positiveInteger(String? value) {
  final number = int.tryParse(value?.trim() ?? '');
  if (number == null || number < 0) {
    return 'Enter a valid whole number';
  }
  return null;
}

List<String> _imageUrlsFromController(TextEditingController controller) {
  return controller.text
      .split(RegExp(r'[\n,]'))
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

Future<List<_PickedProductImage>> _pickProductImages() async {
  final result = await FilePicker.pickFiles(type: FileType.image);
  final files = result?.files ?? const <PlatformFile>[];
  final images = <_PickedProductImage>[];

  for (final file in files) {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      continue;
    }
    images.add(_PickedProductImage(name: file.name, bytes: bytes));
  }

  return images;
}

class _PickedProductImage {
  const _PickedProductImage({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

String? _primaryImageUrl(List<String> imageUrls) {
  return imageUrls.isEmpty ? null : imageUrls.first;
}

String _humanStatus(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

List<String> _inventoryCategories(List<StoreInventoryItem> products) {
  final categories = products
      .map(
        (product) =>
            product.category.trim().isEmpty ? 'general' : product.category,
      )
      .toSet()
      .toList()
    ..sort();
  return categories;
}

bool _matchesInventorySearch(StoreInventoryItem product, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }

  return product.name.toLowerCase().contains(normalized) ||
      product.description.toLowerCase().contains(normalized) ||
      product.category.toLowerCase().contains(normalized) ||
      (product.sku ?? '').toLowerCase().contains(normalized);
}

StoreInventoryItem _currentInventoryItemFromSnapshot(
  List<StoreInventoryItem>? products,
  StoreInventoryItem fallback,
) {
  if (products == null) {
    return fallback;
  }

  for (final product in products) {
    if (product.productId == fallback.productId) {
      return product;
    }
  }

  return fallback;
}

bool _matchesStoreOrderSearch(OrderSummary order, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }

  return order.id.toLowerCase().contains(normalized) ||
      order.storeName.toLowerCase().contains(normalized) ||
      (order.customerName ?? '').toLowerCase().contains(normalized) ||
      (order.customerPhone ?? '').toLowerCase().contains(normalized) ||
      order.status.toLowerCase().contains(normalized) ||
      _humanStatus(order.status).toLowerCase().contains(normalized) ||
      order.paymentStatus.toLowerCase().contains(normalized) ||
      _humanStatus(order.paymentStatus).toLowerCase().contains(normalized) ||
      order.deliveryAddress.toLowerCase().contains(normalized) ||
      _formatNaira(order.totalAmount).toLowerCase().contains(normalized);
}

List<OrderSummary> _sortedStoreOrders(List<OrderSummary> orders) {
  final sorted = [...orders];
  sorted.sort((a, b) {
    final statusRank =
        _storeOrderStatusRank(a).compareTo(_storeOrderStatusRank(b));
    if (statusRank != 0) {
      return statusRank;
    }
    return b.createdAt.compareTo(a.createdAt);
  });
  return sorted;
}

int _storeOrderStatusRank(OrderSummary order) {
  return _storeOrderStatusRankValue(order.status);
}

int _storeOrderStatusRankValue(String status) {
  return switch (status) {
    'paid' => 0,
    'accepted' => 1,
    'preparing' => 2,
    'ready_for_pickup' => 3,
    'out_for_delivery' => 4,
    'delivered' => 5,
    'cancelled' => 6,
    _ => 7,
  };
}

_StoreOrderAction? _storeOrderActionFor(OrderSummary order) {
  if (order.paymentStatus != 'paid') {
    return null;
  }
  return switch (order.status) {
    'paid' => const _StoreOrderAction(
        status: 'accepted',
        label: 'Accept',
        icon: Icons.task_alt_outlined,
      ),
    'accepted' => const _StoreOrderAction(
        status: 'preparing',
        label: 'Start preparing',
        icon: Icons.restaurant_outlined,
      ),
    'preparing' => const _StoreOrderAction(
        status: 'ready_for_pickup',
        label: 'Mark ready',
        icon: Icons.inventory_2_outlined,
      ),
    _ => null,
  };
}

List<_StoreLifecycleStep> _storeLifecycleSteps(OrderSummary order) {
  return [
    const _StoreLifecycleStep(
      status: 'paid',
      label: 'New',
      icon: Icons.receipt_long_outlined,
    ),
    const _StoreLifecycleStep(
      status: 'accepted',
      label: 'Accepted',
      icon: Icons.task_alt_outlined,
    ),
    const _StoreLifecycleStep(
      status: 'preparing',
      label: 'Preparing',
      icon: Icons.restaurant_outlined,
    ),
    _StoreLifecycleStep(
      status: 'ready_for_pickup',
      label: order.fulfillmentType == 'pickup' ? 'Ready' : 'Pickup',
      icon: Icons.inventory_2_outlined,
    ),
    if (order.fulfillmentType == 'pickup')
      const _StoreLifecycleStep(
        status: 'delivered',
        label: 'Collected',
        icon: Icons.shopping_bag_outlined,
      )
    else ...[
      const _StoreLifecycleStep(
        status: 'out_for_delivery',
        label: 'Rider',
        icon: Icons.delivery_dining_outlined,
      ),
      const _StoreLifecycleStep(
        status: 'delivered',
        label: 'Delivered',
        icon: Icons.done_all,
      ),
    ],
  ];
}

List<_OrderDateGroup> _groupOrdersByLocalDate(List<OrderSummary> orders) {
  final byDay = <DateTime, List<OrderSummary>>{};
  for (final order in orders) {
    final local = order.createdAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    byDay.putIfAbsent(day, () => []).add(order);
  }

  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days)
      _OrderDateGroup(
        label: _orderDateGroupLabel(day),
        orders: _sortedStoreOrders(byDay[day]!),
      ),
  ];
}

List<_OrderStatusGroup> _groupOrdersByStoreStatus(List<OrderSummary> orders) {
  final byStatus = <String, List<OrderSummary>>{};
  for (final order in orders) {
    byStatus.putIfAbsent(order.status, () => []).add(order);
  }

  final statuses = byStatus.keys.toList()
    ..sort((a, b) {
      final rank = _storeOrderStatusRankValue(a).compareTo(
        _storeOrderStatusRankValue(b),
      );
      if (rank != 0) {
        return rank;
      }
      return a.compareTo(b);
    });

  return [
    for (final status in statuses)
      _OrderStatusGroup(
        label: _statusSectionLabel(status),
        orders: _sortOrdersByUpdatedAt(byStatus[status]!),
      ),
  ];
}

List<OrderSummary> _sortOrdersByUpdatedAt(List<OrderSummary> orders) {
  final sorted = [...orders];
  sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return sorted;
}

String _statusSectionLabel(String status) {
  if (status == 'delivered') {
    return 'Fulfilled';
  }
  return _humanStatus(status);
}

String _storeOrderItemSummary(List<OrderLineItem> items, int itemCount) {
  if (items.isEmpty) {
    return itemCount == 0 ? 'Items loading' : '$itemCount items';
  }

  final first = items.first;
  final firstLine = '${first.quantity} x ${first.productName}';
  if (items.length == 1) {
    return firstLine;
  }

  final remaining = itemCount - first.quantity;
  if (remaining <= 0) {
    return '$firstLine + more items';
  }
  return '$firstLine + $remaining more';
}

String _orderDateGroupLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == today) {
    return 'Today';
  }
  if (day == yesterday) {
    return 'Yesterday';
  }
  return '${day.day}${_daySuffix(day.day)} ${_monthName(day.month)}';
}

String _daySuffix(int day) {
  if (day >= 11 && day <= 13) {
    return 'th';
  }
  return switch (day % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th',
  };
}

String _monthName(int month) {
  return switch (month) {
    1 => 'January',
    2 => 'February',
    3 => 'March',
    4 => 'April',
    5 => 'May',
    6 => 'June',
    7 => 'July',
    8 => 'August',
    9 => 'September',
    10 => 'October',
    11 => 'November',
    12 => 'December',
    _ => 'Month $month',
  };
}

String _filterLabel(String value) {
  switch (value) {
    case 'new':
      return 'New';
    case 'accepted':
      return 'Accepted';
    case 'preparing':
      return 'Preparing';
    case 'ready':
      return 'Ready';
    case 'out_for_delivery':
      return 'With rider';
    case 'fulfilled':
      return 'Fulfilled';
    case 'cancelled':
      return 'Cancelled';
    case 'expired':
      return 'Expired';
    case 'failed':
      return 'Failed payment';
    case 'refunded':
      return 'Refunded';
    case 'all':
      return 'All';
    default:
      return 'Orders';
  }
}

bool _isActiveStoreOrder(OrderSummary order) {
  if (order.paymentStatus != 'paid') {
    return false;
  }

  return !_isFinishedStoreOrder(order);
}

bool _isFinishedStoreOrder(OrderSummary order) {
  return order.status == 'delivered' ||
      order.status == 'cancelled' ||
      order.status == 'expired' ||
      order.paymentStatus == 'expired' ||
      order.paymentStatus == 'failed' ||
      order.paymentStatus == 'refunded';
}

bool _isSameLocalDay(DateTime value, DateTime day) {
  final local = value.toLocal();
  return local.year == day.year &&
      local.month == day.month &&
      local.day == day.day;
}

String _formatNaira(double value) {
  return 'NGN ${value.toStringAsFixed(0)}';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

String _stars(int rating) {
  final safeRating = rating.clamp(0, 5);
  return '$safeRating/5';
}

String _contentTypeForFile(String fileName) {
  final lowerName = fileName.toLowerCase();
  if (lowerName.endsWith('.png')) {
    return 'image/png';
  }
  if (lowerName.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lowerName.endsWith('.gif')) {
    return 'image/gif';
  }
  return 'image/jpeg';
}

String _shortId(String value) {
  return value.length <= 8 ? value : value.substring(0, 8);
}

String _friendlyError(Object error) {
  return error.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '');
}

String _contactText({
  required String? name,
  required String? phone,
  required String fallback,
}) {
  final parts = [
    if (name != null && name.trim().isNotEmpty) name.trim(),
    if (phone != null && phone.trim().isNotEmpty) phone.trim(),
  ];
  return parts.isEmpty ? fallback : parts.join(' | ');
}

OrderSummary _currentOrderFromSnapshot(
  List<OrderSummary>? orders,
  OrderSummary fallback,
) {
  if (orders == null) {
    return fallback;
  }
  for (final order in orders) {
    if (order.id == fallback.id) {
      return order;
    }
  }
  return fallback;
}

int _orderItemCount(List<OrderLineItem> items) {
  return items.fold<int>(0, (total, item) => total + item.quantity);
}

bool _showsCustomerDetails(OrderSummary order) {
  return order.status != 'paid' && order.paymentStatus == 'paid';
}

Color _orderStatusColor(String status) {
  switch (status) {
    case 'paid':
      return const Color(0xff16a34a);
    case 'accepted':
    case 'preparing':
      return const Color(0xff2563eb);
    case 'ready_for_pickup':
    case 'out_for_delivery':
      return const Color(0xff0891b2);
    case 'delivered':
      return const Color(0xff15803d);
    case 'cancelled':
      return const Color(0xffdc2626);
    default:
      return const Color(0xff64748b);
  }
}

String _storeStatusLabel(StoreSummary store) {
  final now = DateTime.now();
  final busyUntil = store.busyUntil?.toLocal();
  if (busyUntil != null && busyUntil.isAfter(now)) {
    return 'Busy until ${_formatTimeOnly(busyUntil)}';
  }
  final closedUntil = store.closedUntil?.toLocal();
  if (!store.isOpen || (closedUntil != null && closedUntil.isAfter(now))) {
    return 'Closed today';
  }
  return 'Open';
}

IconData _storeStatusIcon(StoreSummary store) {
  final now = DateTime.now();
  final busyUntil = store.busyUntil?.toLocal();
  if (busyUntil != null && busyUntil.isAfter(now)) {
    return Icons.timelapse;
  }
  final closedUntil = store.closedUntil?.toLocal();
  if (!store.isOpen || (closedUntil != null && closedUntil.isAfter(now))) {
    return Icons.storefront_outlined;
  }
  return Icons.storefront;
}

String _formatTimeOnly(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

TimeOfDay? _parseTimeOfDay(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final parts = value.split(':');
  if (parts.length < 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  return TimeOfDay(hour: hour, minute: minute);
}

String _formatTimeOfDayForDb(TimeOfDay value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _dayName(int dayOfWeek) {
  return switch (dayOfWeek) {
    0 => 'Sunday',
    1 => 'Monday',
    2 => 'Tuesday',
    3 => 'Wednesday',
    4 => 'Thursday',
    5 => 'Friday',
    6 => 'Saturday',
    _ => 'Day $dayOfWeek',
  };
}

StoreOpeningHour? _openingHourForDay(
  List<StoreOpeningHour> hours,
  int dayOfWeek,
) {
  for (final hour in hours) {
    if (hour.dayOfWeek == dayOfWeek) {
      return hour;
    }
  }
  return null;
}
