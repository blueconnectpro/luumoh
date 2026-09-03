import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:luumoh_core/luumoh_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'src/admin_dashboard.dart';
part 'src/rider_admin_dashboard.dart';
part 'src/store_admin_dashboard.dart';

const _adminListPageSize = 20;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AdminDashboardApp(environment: AppEnvironment.fromDartDefines()));
}

class AdminDashboardApp extends StatelessWidget {
  const AdminDashboardApp({required this.environment, super.key});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Luumoh Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff374151)),
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
            title: 'Starting Luumoh Admin',
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

        return _AdminAuthGate(environment: widget.environment);
      },
    );
  }
}

class _AdminAuthGate extends StatelessWidget {
  const _AdminAuthGate({required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session == null) {
          return const _AdminSignInPage();
        }

        return AdminDashboardPage(
          userEmail: session.user.email ?? 'Admin',
          mapboxAccessToken: environment.mapboxAccessToken,
        );
      },
    );
  }
}

class _AdminSignInPage extends StatefulWidget {
  const _AdminSignInPage();

  @override
  State<_AdminSignInPage> createState() => _AdminSignInPageState();
}

class _AdminSignInPageState extends State<_AdminSignInPage> {
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
                      'Admin sign in',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use a Luumoh staff, rider admin, or store manager account.',
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

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({
    required this.userEmail,
    required this.mapboxAccessToken,
    super.key,
  });

  final String userEmail;
  final String mapboxAccessToken;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late final PlatformRepository _repository;
  late final MapboxLocationService _mapboxLocation;
  late final Future<UserProfile?> _profileFuture;
  final _storeFormKey = GlobalKey<FormState>();
  final _productFormKey = GlobalKey<FormState>();
  final _userFormKey = GlobalKey<FormState>();
  final _storeNameController = TextEditingController();
  final _storeCategoryController = TextEditingController(text: 'restaurant');
  final _storeAddressController = TextEditingController();
  MapboxPoint? _storeAddressPoint;
  final _productNameController = TextEditingController();
  final _productDescriptionController = TextEditingController();
  final _productCategoryController = TextEditingController(text: 'general');
  final _productPriceController = TextEditingController();
  final _productStockController = TextEditingController(text: '10');
  final _productSkuController = TextEditingController();
  final _productImageUrlController = TextEditingController();
  final _productReorderController = TextEditingController(text: '5');
  final _userEmailController = TextEditingController();
  final _userPasswordController = TextEditingController();
  final _userFullNameController = TextEditingController();
  final _userPhoneController = TextEditingController();
  String? _selectedStoreId;
  String? _newUserStoreId;
  String _newUserRole = 'rider';
  String? _selectedUserId;
  String _selectedRole = 'customer';
  bool _canManageInventory = true;
  bool _canManageOrders = true;
  bool _isCreatingStore = false;
  bool _isCreatingProduct = false;
  bool _isCreatingUser = false;
  bool _isUploadingProductImage = false;
  bool _isUpdatingAccess = false;
  bool _isUpdatingStore = false;
  bool _isResolvingStoreAddress = false;
  int _selectedAdminPage = 0;
  int _selectedRiderAdminPage = 0;

  @override
  void initState() {
    super.initState();
    _repository = PlatformRepository(Supabase.instance.client);
    _mapboxLocation = MapboxLocationService(widget.mapboxAccessToken);
    _profileFuture = _repository.fetchMyProfile();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _storeCategoryController.dispose();
    _storeAddressController.dispose();
    _productNameController.dispose();
    _productDescriptionController.dispose();
    _productCategoryController.dispose();
    _productPriceController.dispose();
    _productStockController.dispose();
    _productSkuController.dispose();
    _productImageUrlController.dispose();
    _productReorderController.dispose();
    _userEmailController.dispose();
    _userPasswordController.dispose();
    _userFullNameController.dispose();
    _userPhoneController.dispose();
    super.dispose();
  }

  Future<void> _createStore() async {
    if (!_storeFormKey.currentState!.validate()) {
      return;
    }

    setState(() => _isCreatingStore = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final address = _storeAddressController.text.trim();
      final location =
          _storeAddressPoint ?? await _resolveStoreAddressWithMapbox(address);
      final storeId = await _repository.createStore(
        name: _storeNameController.text.trim(),
        category: _storeCategoryController.text.trim(),
        address: _storeAddressController.text.trim(),
      );
      if (location != null) {
        await _repository.updateStoreLocation(
          storeId: storeId,
          address: _storeAddressController.text.trim(),
          latitude: location.latitude,
          longitude: location.longitude,
        );
      }
      setState(() => _selectedStoreId = storeId);
      _storeNameController.clear();
      _storeAddressPoint = null;
      _storeAddressController.clear();
      messenger.showSnackBar(
        SnackBar(content: Text('Created store $storeId')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Store creation failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreatingStore = false);
      }
    }
  }

  Future<MapboxPoint?> _resolveStoreAddressWithMapbox(String address) async {
    final normalized = address.trim();
    if (normalized.length < 3 || !_mapboxLocation.isConfigured) {
      return null;
    }
    final results = await _mapboxLocation.searchAddresses(
      normalized,
      country: 'ng',
      limit: 1,
    );
    final result = results.isEmpty ? null : results.first;
    if (result == null) {
      return null;
    }
    _storeAddressController.text = result.address;
    return result.point;
  }

  Future<void> _useCurrentLocationForStore() async {
    setState(() => _isResolvingStoreAddress = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final point = await _mapboxLocation.currentPoint();
      MapboxAddressResult? resolved;
      if (_mapboxLocation.isConfigured) {
        resolved = await _mapboxLocation.reverseGeocode(point);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _storeAddressPoint = resolved?.point ?? point;
        _storeAddressController.text = resolved?.address ??
            '${point.latitude.toStringAsFixed(5)}, '
                '${point.longitude.toStringAsFixed(5)}';
      });
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Current location failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isResolvingStoreAddress = false);
      }
    }
  }

  Future<void> _findStoreAddress() async {
    final query = _storeAddressController.text.trim();
    if (query.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least 3 characters')),
      );
      return;
    }
    if (!_mapboxLocation.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MAPBOX_ACCESS_TOKEN is not configured')),
      );
      return;
    }

    setState(() => _isResolvingStoreAddress = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final results = await _mapboxLocation.searchAddresses(
        query,
        country: 'ng',
      );
      if (!mounted) {
        return;
      }
      final selected = await showModalBottomSheet<MapboxAddressResult>(
        context: context,
        showDragHandle: true,
        builder: (context) => _AdminAddressResultsSheet(results: results),
      );
      if (selected != null && mounted) {
        setState(() {
          _storeAddressController.text = selected.address;
          _storeAddressPoint = selected.point;
        });
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Address lookup failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isResolvingStoreAddress = false);
      }
    }
  }

  Future<void> _createProduct() async {
    if (!_productFormKey.currentState!.validate()) {
      return;
    }

    final storeId = _selectedStoreId;
    if (storeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a store first')),
      );
      return;
    }

    setState(() => _isCreatingProduct = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final productId = await _repository.createProduct(
        storeId: storeId,
        name: _productNameController.text.trim(),
        description: _productDescriptionController.text.trim(),
        category: _productCategoryController.text.trim().isEmpty
            ? 'general'
            : _productCategoryController.text.trim(),
        price: double.parse(_productPriceController.text.trim()),
        initialStock: int.parse(_productStockController.text.trim()),
        reorderLevel: int.parse(_productReorderController.text.trim()),
        sku: _productSkuController.text.trim().isEmpty
            ? null
            : _productSkuController.text.trim(),
        imageUrl: _productImageUrlController.text.trim().isEmpty
            ? null
            : _productImageUrlController.text.trim(),
      );
      _productNameController.clear();
      _productDescriptionController.clear();
      _productCategoryController.text = 'general';
      _productPriceController.clear();
      _productStockController.text = '10';
      _productSkuController.clear();
      _productImageUrlController.clear();
      _productReorderController.text = '5';
      messenger.showSnackBar(
        SnackBar(content: Text('Created product $productId')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Product creation failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreatingProduct = false);
      }
    }
  }

  Future<void> _uploadProductImage() async {
    final selectedStoreId = _selectedStoreId;
    if (selectedStoreId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a store first')),
      );
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.image,
    );
    final file = result?.files.single;
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();

    if (!mounted) {
      return;
    }

    setState(() => _isUploadingProductImage = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final imageUrl = await _repository.uploadProductImage(
        storeId: selectedStoreId,
        fileName: file.name,
        bytes: bytes,
        contentType: _contentTypeForFile(file.name),
      );
      _productImageUrlController.text = imageUrl;
      messenger.showSnackBar(
        const SnackBar(content: Text('Product image uploaded')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Image upload failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingProductImage = false);
      }
    }
  }

  Future<void> _setRole() async {
    final userId = _selectedUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a user first')),
      );
      return;
    }

    setState(() => _isUpdatingAccess = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.setProfileRole(userId: userId, role: _selectedRole);
      messenger.showSnackBar(
        SnackBar(content: Text('Updated role to $_selectedRole')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Role update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAccess = false);
      }
    }
  }

  Future<void> _removeRider(UserProfile rider) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove rider access?'),
        content: Text(
          '${rider.displayName} will no longer appear as a rider or receive delivery work.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Remove rider'),
          ),
        ],
      ),
    );

    if (shouldRemove != true || !mounted) {
      return;
    }

    setState(() => _isUpdatingAccess = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.setProfileRole(userId: rider.id, role: 'customer');
      messenger.showSnackBar(
        SnackBar(content: Text('${rider.displayName} removed from riders')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Remove rider failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAccess = false);
      }
    }
  }

  Future<void> _deleteUser(UserProfile profile) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (profile.id == currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot delete your own account.')),
      );
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account permanently?'),
        content: Text(
          '${profile.displayName} will be removed from Supabase Auth and their profile data will be deleted. Historical orders will remain for reporting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete account'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() => _isUpdatingAccess = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.adminDeleteUser(userId: profile.id);
      if (!mounted) {
        return;
      }
      setState(() {
        if (_selectedUserId == profile.id) {
          _selectedUserId = null;
          _selectedRole = 'customer';
        }
      });
      messenger.showSnackBar(
        SnackBar(content: Text('${profile.displayName} deleted')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Delete account failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAccess = false);
      }
    }
  }

  Future<void> _createOperationalUser() async {
    if (!_userFormKey.currentState!.validate()) {
      return;
    }

    final role = _newUserRole;
    final storeId = role == 'store_admin' ? _newUserStoreId : null;
    if (role == 'store_admin' && storeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a store for store staff')),
      );
      return;
    }

    setState(() => _isCreatingUser = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final userId = await _repository.adminUpsertUser(
        email: _userEmailController.text.trim(),
        password: _userPasswordController.text,
        role: role,
        fullName: _userFullNameController.text.trim(),
        phone: _userPhoneController.text.trim().isEmpty
            ? null
            : _userPhoneController.text.trim(),
        storeId: storeId,
        canManageInventory: _canManageInventory,
        canManageOrders: _canManageOrders,
      );
      if (!mounted) {
        return;
      }
      _userEmailController.clear();
      _userPasswordController.clear();
      _userFullNameController.clear();
      _userPhoneController.clear();
      setState(() => _selectedUserId = userId);
      messenger.showSnackBar(
        SnackBar(content: Text('User ready: ${_shortId(userId)}')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('User setup failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreatingUser = false);
      }
    }
  }

  Future<void> _editSelectedProfileContact(UserProfile profile) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _AdminProfileContactDialog(
        repository: _repository,
        profile: profile,
      ),
    );
  }

  Future<void> _addStoreMember() async {
    final userId = _selectedUserId;
    final selectedStoreId = _selectedStoreId;
    if (userId == null || selectedStoreId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a user and store first')),
      );
      return;
    }

    setState(() => _isUpdatingAccess = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.addStoreMember(
        storeId: selectedStoreId,
        userId: userId,
        canManageInventory: _canManageInventory,
        canManageOrders: _canManageOrders,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Added store member')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Store membership failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAccess = false);
      }
    }
  }

  Future<void> _updateStoreStatus(
    StoreSummary store, {
    bool? isOpen,
    bool? isActive,
  }) async {
    setState(() => _isUpdatingStore = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.updateStoreStatus(
        storeId: store.id,
        isOpen: isOpen,
        isActive: isActive,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Updated ${store.name}')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Store update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStore = false);
      }
    }
  }

  Future<void> _updateStoreMember(
    StoreMember member, {
    bool? canManageInventory,
    bool? canManageOrders,
  }) async {
    setState(() => _isUpdatingAccess = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.addStoreMember(
        storeId: member.storeId,
        userId: member.userId,
        canManageInventory: canManageInventory ?? member.canManageInventory,
        canManageOrders: canManageOrders ?? member.canManageOrders,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Updated store member')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Membership update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAccess = false);
      }
    }
  }

  Future<void> _removeStoreMember(StoreMember member) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove store member?'),
        content: const Text(
          'This user will lose access to this store immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Remove'),
          ),
        ],
      ),
    );

    if (shouldRemove != true || !mounted) {
      return;
    }

    setState(() => _isUpdatingAccess = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.removeStoreMember(
        storeId: member.storeId,
        userId: member.userId,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Removed store member')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Remove member failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAccess = false);
      }
    }
  }

  Future<void> _openNotifications([String audience = 'admin']) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _NotificationsPage(
          repository: _repository,
          audience: audience,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<UserProfile?>(
          future: _profileFuture,
          builder: (context, snapshot) {
            final role = snapshot.data?.role;
            return Text(
              role == null ? 'Luumoh Operations' : _adminDashboardTitle(role),
            );
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: Text(widget.userEmail)),
          ),
          FutureBuilder<UserProfile?>(
            future: _profileFuture,
            builder: (context, snapshot) {
              final audience = _notificationAudienceForAdminRole(
                snapshot.data?.role,
              );
              return _NotificationIcon(
                repository: _repository,
                audience: audience,
                onPressed: () => _openNotifications(audience),
              );
            },
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder<UserProfile?>(
        future: _profileFuture,
        builder: (context, profileSnapshot) {
          if (profileSnapshot.hasError) {
            return _InlineState(
              title: 'Profile failed to load',
              message: profileSnapshot.error.toString(),
            );
          }

          if (profileSnapshot.connectionState == ConnectionState.waiting) {
            return const _InlineState(
              title: 'Loading dashboard',
              message: 'Checking your access...',
              isLoading: true,
            );
          }

          final myProfile = profileSnapshot.data;
          if (myProfile != null && _isStoreAdminRole(myProfile.role)) {
            return _StoreOwnerDashboard(
              repository: _repository,
              userEmail: widget.userEmail,
              profile: myProfile,
            );
          }

          if (myProfile != null && _isRiderAdminRole(myProfile.role)) {
            return _RiderAdminDashboard(
              repository: _repository,
              userEmail: widget.userEmail,
              selectedIndex: _selectedRiderAdminPage,
              userFormKey: _userFormKey,
              isCreatingUser: _isCreatingUser,
              isUpdatingAccess: _isUpdatingAccess,
              userEmailController: _userEmailController,
              userPasswordController: _userPasswordController,
              userFullNameController: _userFullNameController,
              userPhoneController: _userPhoneController,
              onSectionChanged: (index) => setState(
                () => _selectedRiderAdminPage = index,
              ),
              onNewUserRoleChanged: (role) => setState(() {
                _newUserRole = role;
                if (role != 'store_admin') {
                  _newUserStoreId = null;
                }
              }),
              onCreateUser: _createOperationalUser,
              onRemoveRider: _removeRider,
            );
          }

          if (myProfile == null || !_isSuperAdminRole(myProfile.role)) {
            return const _InlineState(
              title: 'Admin access required',
              message:
                  'This dashboard is available to Luumoh staff, rider admins, and store admins.',
            );
          }

          return StreamBuilder<List<StoreSummary>>(
            stream: _repository.watchStores(activeOnly: false),
            initialData: const <StoreSummary>[],
            builder: (context, storesSnapshot) {
              if (storesSnapshot.hasError) {
                return _InlineState(
                  title: 'Stores failed to load',
                  message: storesSnapshot.error.toString(),
                );
              }

              if (storesSnapshot.connectionState == ConnectionState.waiting &&
                  !storesSnapshot.hasData) {
                return const _InlineState(
                  title: 'Loading stores',
                  message: 'Fetching platform stores...',
                  isLoading: true,
                );
              }

              final stores = storesSnapshot.data ?? const <StoreSummary>[];
              if (_selectedStoreId == null && stores.isNotEmpty) {
                _selectedStoreId = stores.first.id;
              }

              return StreamBuilder<List<CatalogItem>>(
                stream: _repository.watchCatalog(),
                initialData: const <CatalogItem>[],
                builder: (context, catalogSnapshot) {
                  if (catalogSnapshot.hasError) {
                    return _InlineState(
                      title: 'Catalog failed to load',
                      message: catalogSnapshot.error.toString(),
                    );
                  }

                  if (catalogSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !catalogSnapshot.hasData) {
                    return const _InlineState(
                      title: 'Loading catalog',
                      message: 'Fetching products and stock...',
                      isLoading: true,
                    );
                  }

                  final catalog = catalogSnapshot.data ?? const <CatalogItem>[];

                  return StreamBuilder<List<UserProfile>>(
                    stream: _repository.watchProfiles(),
                    initialData: const <UserProfile>[],
                    builder: (context, profilesSnapshot) {
                      if (profilesSnapshot.hasError) {
                        return _InlineState(
                          title: 'Profiles failed to load',
                          message: profilesSnapshot.error.toString(),
                        );
                      }

                      if (profilesSnapshot.connectionState ==
                              ConnectionState.waiting &&
                          !profilesSnapshot.hasData) {
                        return const _InlineState(
                          title: 'Loading profiles',
                          message: 'Fetching user accounts...',
                          isLoading: true,
                        );
                      }

                      final profiles =
                          profilesSnapshot.data ?? const <UserProfile>[];
                      if (_selectedUserId == null && profiles.isNotEmpty) {
                        final firstProfile = profiles.first;
                        _selectedUserId = firstProfile.id;
                        _selectedRole = firstProfile.role;
                      }

                      return StreamBuilder<List<StoreMember>>(
                        stream: _repository.watchStoreMembers(),
                        initialData: const <StoreMember>[],
                        builder: (context, membersSnapshot) {
                          if (membersSnapshot.hasError) {
                            return _InlineState(
                              title: 'Store memberships failed to load',
                              message: membersSnapshot.error.toString(),
                            );
                          }

                          if (membersSnapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !membersSnapshot.hasData) {
                            return const _InlineState(
                              title: 'Loading memberships',
                              message: 'Fetching store staff access...',
                              isLoading: true,
                            );
                          }

                          final members =
                              membersSnapshot.data ?? const <StoreMember>[];

                          return StreamBuilder<List<OrderSummary>>(
                            stream: _repository.watchAllOrders(),
                            initialData: const <OrderSummary>[],
                            builder: (context, ordersSnapshot) {
                              if (ordersSnapshot.hasError) {
                                return _InlineState(
                                  title: 'Orders failed to load',
                                  message: ordersSnapshot.error.toString(),
                                );
                              }

                              if (ordersSnapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  !ordersSnapshot.hasData) {
                                return const _InlineState(
                                  title: 'Loading orders',
                                  message: 'Fetching platform operations...',
                                  isLoading: true,
                                );
                              }

                              final orders =
                                  ordersSnapshot.data ?? const <OrderSummary>[];
                              final paidRevenue = orders
                                  .where(
                                      (order) => order.paymentStatus == 'paid')
                                  .fold<double>(
                                    0,
                                    (total, order) => total + order.totalAmount,
                                  );
                              final platformFees = orders
                                  .where(
                                      (order) => order.paymentStatus == 'paid')
                                  .fold<double>(
                                    0,
                                    (total, order) =>
                                        total + order.platformFeeAmount,
                                  );
                              final storePayouts = orders
                                  .where(
                                      (order) => order.paymentStatus == 'paid')
                                  .fold<double>(
                                    0,
                                    (total, order) =>
                                        total + order.storePayoutAmount,
                                  );
                              final riderPayouts = orders
                                  .where(
                                      (order) => order.paymentStatus == 'paid')
                                  .fold<double>(
                                    0,
                                    (total, order) =>
                                        total + order.riderPayoutAmount,
                                  );

                              final sections = [
                                _AdminDashboardSection(
                                  label: 'Overview',
                                  icon: Icons.dashboard_outlined,
                                  selectedIcon: Icons.dashboard,
                                  page: _AdminOverviewPage(
                                    stores: stores,
                                    catalog: catalog,
                                    profiles: profiles,
                                    members: members,
                                    orders: orders,
                                    paidRevenue: paidRevenue,
                                    platformFees: platformFees,
                                    storePayouts: storePayouts,
                                    riderPayouts: riderPayouts,
                                    onOpenSection: (index) => setState(
                                      () => _selectedAdminPage = index,
                                    ),
                                  ),
                                ),
                                _AdminDashboardSection(
                                  label: 'Orders',
                                  icon: Icons.receipt_long_outlined,
                                  selectedIcon: Icons.receipt_long,
                                  page: _AdminSectionPage(
                                    title: 'Orders',
                                    description:
                                        'Track live order flow, rider assignment, refunds, cancellations, and customer contact details.',
                                    children: [
                                      _AdminOrdersPanel(
                                        repository: _repository,
                                        orders: orders,
                                        profiles: profiles,
                                      ),
                                    ],
                                  ),
                                ),
                                _AdminDashboardSection(
                                  label: 'Revenue',
                                  icon: Icons.payments_outlined,
                                  selectedIcon: Icons.payments,
                                  page: _AdminPaymentsPage(
                                    repository: _repository,
                                    orders: orders,
                                    paidRevenue: paidRevenue,
                                    platformFees: platformFees,
                                  ),
                                ),
                                _AdminDashboardSection(
                                  label: 'Splits',
                                  icon: Icons.account_balance_wallet_outlined,
                                  selectedIcon: Icons.account_balance_wallet,
                                  page: _AdminSectionPage(
                                    title: 'Payment split routing',
                                    description:
                                        'Monitor Monnify split routing. Store and rider payouts are routed directly to their accounts at checkout.',
                                    children: [
                                      _SplitPaymentRoutingPanel(orders: orders),
                                    ],
                                  ),
                                ),
                                _AdminDashboardSection(
                                  label: 'Stores',
                                  icon: Icons.storefront_outlined,
                                  selectedIcon: Icons.storefront,
                                  page: _AdminStoresInventoryPage(
                                    repository: _repository,
                                    stores: stores,
                                    catalog: catalog,
                                    members: members,
                                    selectedStoreId: _selectedStoreId,
                                    isCreatingStore: _isCreatingStore,
                                    isCreatingProduct: _isCreatingProduct,
                                    isUploadingProductImage:
                                        _isUploadingProductImage,
                                    isUpdatingStore: _isUpdatingStore,
                                    storeFormKey: _storeFormKey,
                                    productFormKey: _productFormKey,
                                    storeNameController: _storeNameController,
                                    storeCategoryController:
                                        _storeCategoryController,
                                    storeAddressController:
                                        _storeAddressController,
                                    isResolvingStoreAddress:
                                        _isResolvingStoreAddress,
                                    productNameController:
                                        _productNameController,
                                    productDescriptionController:
                                        _productDescriptionController,
                                    productCategoryController:
                                        _productCategoryController,
                                    productPriceController:
                                        _productPriceController,
                                    productStockController:
                                        _productStockController,
                                    productSkuController: _productSkuController,
                                    productImageUrlController:
                                        _productImageUrlController,
                                    productReorderController:
                                        _productReorderController,
                                    onCreateStore: _createStore,
                                    onCreateProduct: _createProduct,
                                    onUploadProductImage: _uploadProductImage,
                                    onUseCurrentLocation:
                                        _useCurrentLocationForStore,
                                    onFindAddress: _findStoreAddress,
                                    onAddressChanged: () => setState(
                                      () => _storeAddressPoint = null,
                                    ),
                                    onStoreChanged: (value) => setState(
                                      () => _selectedStoreId = value,
                                    ),
                                    onStoreSelected: (value) => setState(
                                      () => _selectedStoreId = value,
                                    ),
                                    onStoreOpenChanged: (store, value) =>
                                        _updateStoreStatus(
                                      store,
                                      isOpen: value,
                                    ),
                                    onStoreActiveChanged: (store, value) =>
                                        _updateStoreStatus(
                                      store,
                                      isActive: value,
                                    ),
                                  ),
                                ),
                                _AdminDashboardSection(
                                  label: 'Users',
                                  icon: Icons.groups_outlined,
                                  selectedIcon: Icons.groups,
                                  page: _AdminUsersAccessPage(
                                    stores: stores,
                                    profiles: profiles,
                                    members: members,
                                    userFormKey: _userFormKey,
                                    newUserRole: _newUserRole,
                                    newUserStoreId: _newUserStoreId,
                                    canManageInventory: _canManageInventory,
                                    canManageOrders: _canManageOrders,
                                    isCreatingUser: _isCreatingUser,
                                    userEmailController: _userEmailController,
                                    userPasswordController:
                                        _userPasswordController,
                                    userFullNameController:
                                        _userFullNameController,
                                    userPhoneController: _userPhoneController,
                                    onCreateUser: _createOperationalUser,
                                    onNewUserRoleChanged: (role) =>
                                        setState(() {
                                      _newUserRole = role;
                                      if (role != 'store_admin') {
                                        _newUserStoreId = null;
                                      }
                                    }),
                                    onNewUserStoreChanged: (value) => setState(
                                      () => _newUserStoreId = value,
                                    ),
                                    onInventoryPermissionChanged: (value) =>
                                        setState(
                                      () => _canManageInventory = value,
                                    ),
                                    onOrdersPermissionChanged: (value) =>
                                        setState(
                                      () => _canManageOrders = value,
                                    ),
                                  ),
                                ),
                                _AdminDashboardSection(
                                  label: 'Access',
                                  icon: Icons.manage_accounts_outlined,
                                  selectedIcon: Icons.manage_accounts,
                                  page: _AdminAccessManagementPage(
                                    stores: stores,
                                    profiles: profiles,
                                    orders: orders,
                                    members: members,
                                    selectedUserId: _selectedUserId,
                                    selectedRole: _selectedRole,
                                    selectedStoreId: _selectedStoreId,
                                    canManageInventory: _canManageInventory,
                                    canManageOrders: _canManageOrders,
                                    isUpdatingAccess: _isUpdatingAccess,
                                    onUserChanged: (profile) => setState(() {
                                      _selectedUserId = profile?.id;
                                      if (profile != null) {
                                        _selectedRole = profile.role;
                                      }
                                    }),
                                    onRoleChanged: (role) =>
                                        setState(() => _selectedRole = role),
                                    onStoreChanged: (value) => setState(
                                      () => _selectedStoreId = value,
                                    ),
                                    onInventoryPermissionChanged: (value) =>
                                        setState(
                                      () => _canManageInventory = value,
                                    ),
                                    onOrdersPermissionChanged: (value) =>
                                        setState(
                                      () => _canManageOrders = value,
                                    ),
                                    onSetRole: _setRole,
                                    onEditProfile: _editSelectedProfileContact,
                                    onAddStoreMember: _addStoreMember,
                                    onUpdateMemberInventory: (member, value) =>
                                        _updateStoreMember(
                                      member,
                                      canManageInventory: value,
                                    ),
                                    onUpdateMemberOrders: (member, value) =>
                                        _updateStoreMember(
                                      member,
                                      canManageOrders: value,
                                    ),
                                    onRemoveMember: _removeStoreMember,
                                    onRemoveRider: _removeRider,
                                    onDeleteUser: _deleteUser,
                                  ),
                                ),
                                _AdminDashboardSection(
                                  label: 'Riders',
                                  icon: Icons.delivery_dining_outlined,
                                  selectedIcon: Icons.delivery_dining,
                                  page: _AdminRidersPage(
                                    repository: _repository,
                                    profiles: profiles,
                                    orders: orders,
                                    onRemoveRider: _removeRider,
                                  ),
                                ),
                                _AdminDashboardSection(
                                  label: 'Support',
                                  icon: Icons.support_agent_outlined,
                                  selectedIcon: Icons.support_agent,
                                  page: _AdminSectionPage(
                                    title: 'Support and reviews',
                                    description:
                                        'Handle customer issues, review feedback, and watch support quality signals.',
                                    children: [
                                      _AdminIssuesPanel(
                                        repository: _repository,
                                      ),
                                      const SizedBox(height: 16),
                                      _AdminReviewsPanel(
                                        repository: _repository,
                                      ),
                                    ],
                                  ),
                                ),
                              ];

                              if (_selectedAdminPage >= sections.length) {
                                _selectedAdminPage = 0;
                              }

                              return _AdminDashboardShell(
                                title: 'Luumoh staff',
                                userEmail: widget.userEmail,
                                sections: sections,
                                selectedIndex: _selectedAdminPage,
                                onSectionChanged: (index) => setState(
                                  () => _selectedAdminPage = index,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AdminDashboardSection {
  const _AdminDashboardSection({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class _AdminDashboardShell extends StatelessWidget {
  const _AdminDashboardShell({
    required this.title,
    required this.userEmail,
    required this.sections,
    required this.selectedIndex,
    required this.onSectionChanged,
  });

  final String title;
  final String userEmail;
  final List<_AdminDashboardSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isExtended = constraints.maxWidth >= 1180;
        final sidebarWidth = isExtended ? 264.0 : 88.0;

        return Row(
          children: [
            SizedBox(
              width: sidebarWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.42),
                  border: Border(
                    right: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: SafeArea(
                  right: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    child: Column(
                      crossAxisAlignment: isExtended
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        if (isExtended) ...[
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userEmail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ] else
                          Tooltip(
                            message: title,
                            child: const Icon(
                              Icons.admin_panel_settings_outlined,
                            ),
                          ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: ListView.separated(
                            itemCount: sections.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final section = sections[index];
                              return _AdminSidebarTile(
                                label: section.label,
                                icon: section.icon,
                                selectedIcon: section.selectedIcon,
                                isSelected: index == selectedIndex,
                                isExtended: isExtended,
                                onTap: () => onSectionChanged(index),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: colorScheme.surface,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(
                    key: ValueKey(sections[selectedIndex].label),
                    child: sections[selectedIndex].page,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AdminSidebarTile extends StatelessWidget {
  const _AdminSidebarTile({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.isSelected,
    required this.isExtended,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool isSelected;
  final bool isExtended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurface;
    final background =
        isSelected ? colorScheme.secondaryContainer : Colors.transparent;

    final content = Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isExtended ? 12 : 0,
            vertical: 12,
          ),
          child: Row(
            mainAxisAlignment:
                isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(isSelected ? selectedIcon : icon, color: foreground),
              if (isExtended) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (isExtended) {
      return content;
    }

    return Tooltip(
      message: label,
      child: content,
    );
  }
}

class _AdminSectionPage extends StatelessWidget {
  const _AdminSectionPage({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: PageStorageKey<String>('admin-section-$title'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        _AdminPageHeader(title: title, description: description),
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }
}

class _AdminPageHeader extends StatelessWidget {
  const _AdminPageHeader({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _AdminMetricGrid extends StatelessWidget {
  const _AdminMetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1280
            ? 5
            : width >= 980
                ? 4
                : width >= 680
                    ? 3
                    : 2;

        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: width >= 980 ? 1.7 : 1.35,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _AdminResponsivePair extends StatelessWidget {
  const _AdminResponsivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 940) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: 12),
              second,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _AdminStoresListPanel extends StatefulWidget {
  const _AdminStoresListPanel({
    required this.stores,
    required this.members,
    required this.selectedStoreId,
    required this.isUpdatingStore,
    required this.onStoreSelected,
    required this.onStoreOpenChanged,
    required this.onStoreActiveChanged,
  });

  final List<StoreSummary> stores;
  final List<StoreMember> members;
  final String? selectedStoreId;
  final bool isUpdatingStore;
  final ValueChanged<String> onStoreSelected;
  final void Function(StoreSummary store, bool value) onStoreOpenChanged;
  final void Function(StoreSummary store, bool value) onStoreActiveChanged;

  @override
  State<_AdminStoresListPanel> createState() => _AdminStoresListPanelState();
}

class _AdminStoresListPanelState extends State<_AdminStoresListPanel> {
  var _page = 0;

  @override
  Widget build(BuildContext context) {
    final safePage = _coerceListPage(_page, widget.stores.length);
    if (safePage != _page) {
      _page = safePage;
    }
    final pagedStores = widget.stores
        .skip(safePage * _adminListPageSize)
        .take(_adminListPageSize)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Stores', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (widget.stores.isEmpty)
              const Text('No stores yet')
            else ...[
              _PagedListControls(
                page: safePage,
                totalItems: widget.stores.length,
                onPageChanged: (page) => setState(() => _page = page),
              ),
              const SizedBox(height: 8),
              for (final store in pagedStores)
                _AdminStoreTile(
                  store: store,
                  staffCount: _membersForStore(widget.members, store.id).length,
                  isSelected: store.id == widget.selectedStoreId,
                  isSubmitting: widget.isUpdatingStore,
                  onSelected: () => widget.onStoreSelected(store.id),
                  onOpenChanged: (value) =>
                      widget.onStoreOpenChanged(store, value),
                  onActiveChanged: (value) =>
                      widget.onStoreActiveChanged(store, value),
                ),
              const SizedBox(height: 8),
              _PagedListControls(
                page: safePage,
                totalItems: widget.stores.length,
                onPageChanged: (page) => setState(() => _page = page),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentAdminOrdersPanel extends StatelessWidget {
  const _RecentAdminOrdersPanel({required this.orders});

  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context) {
    final recent = orders.take(8).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent orders',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('${orders.length} total')),
              ],
            ),
            const SizedBox(height: 8),
            if (recent.isEmpty)
              const Text('No orders yet.')
            else
              for (final order in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Icon(
                      order.paymentStatus == 'paid'
                          ? Icons.check
                          : Icons.hourglass_bottom,
                    ),
                  ),
                  title: Text(
                    '${order.storeName} | Order #${_shortId(order.id)}',
                  ),
                  subtitle: Text(
                    '${order.status} | ${order.paymentStatus} | '
                    '${_contactText(
                      name: order.customerName,
                      phone: order.customerPhone,
                      fallback: 'Customer',
                    )}',
                  ),
                  trailing: Text(_formatNaira(order.totalAmount)),
                ),
          ],
        ),
      ),
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

class _AdminRevenueChart extends StatelessWidget {
  const _AdminRevenueChart({
    required this.title,
    required this.orders,
    required this.valueForOrder,
  });

  final String title;
  final List<OrderSummary> orders;
  final double Function(OrderSummary order) valueForOrder;

  @override
  Widget build(BuildContext context) {
    final buckets = _lastSevenDayTotals(orders, valueForOrder);
    final maxValue = buckets.fold<double>(
      0,
      (max, bucket) => bucket.value > max ? bucket.value : max,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final bucket in buckets) ...[
                    Expanded(
                      child: _RevenueBar(
                        label: bucket.label,
                        amount: bucket.value,
                        maxAmount: maxValue,
                      ),
                    ),
                    if (bucket != buckets.last) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueBar extends StatelessWidget {
  const _RevenueBar({
    required this.label,
    required this.amount,
    required this.maxAmount,
  });

  final String label;
  final double amount;
  final double maxAmount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final factor = maxAmount <= 0
        ? 0.04
        : (amount / maxAmount).clamp(0.04, 1.0).toDouble();

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          amount <= 0 ? '-' : _compactRevenue(amount),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: factor),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return FractionallySizedBox(
                  heightFactor: value,
                  widthFactor: 1,
                  alignment: Alignment.bottomCenter,
                  child: child,
                );
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _OrderStatusSummaryPanel extends StatelessWidget {
  const _OrderStatusSummaryPanel({required this.orders});

  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context) {
    final statuses = <String, int>{
      'paid': orders.where((order) => order.status == 'paid').length,
      'accepted': orders.where((order) => order.status == 'accepted').length,
      'preparing': orders.where((order) => order.status == 'preparing').length,
      'ready_for_pickup':
          orders.where((order) => order.status == 'ready_for_pickup').length,
      'out_for_delivery':
          orders.where((order) => order.status == 'out_for_delivery').length,
      'delivered': orders.where((order) => order.status == 'delivered').length,
      'cancelled': orders.where((order) => order.status == 'cancelled').length,
    };
    final rawTotal = statuses.values.fold<int>(0, (sum, value) => sum + value);
    final total = rawTotal <= 0 ? 1 : rawTotal;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order lifecycle',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('${orders.length} orders')),
              ],
            ),
            const SizedBox(height: 12),
            for (final entry in statuses.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AnimatedStatusRow(
                  label: _humanStatus(entry.key),
                  count: entry.value,
                  total: total,
                  color: _statusColor(entry.key, colorScheme),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedStatusRow extends StatelessWidget {
  const _AnimatedStatusRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : count / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              count.toString(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: ColoredBox(
            color: color.withValues(alpha: 0.12),
            child: SizedBox(
              height: 8,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: child,
                  );
                },
                child: ColoredBox(color: color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _showStoreHourDialog(
  BuildContext context, {
  required PlatformRepository repository,
  required String storeId,
  required int dayOfWeek,
  StoreOpeningHour? hour,
}) async {
  final opensController =
      TextEditingController(text: _timeText(hour?.opensAt, fallback: '09:00'));
  final closesController =
      TextEditingController(text: _timeText(hour?.closesAt, fallback: '18:00'));
  var isClosed = hour?.isClosed ?? false;
  var isSubmitting = false;

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('${_weekdayName(dayOfWeek)} hours'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Closed all day'),
                      value: isClosed,
                      onChanged: isSubmitting
                          ? null
                          : (value) => setDialogState(() => isClosed = value),
                    ),
                    TextField(
                      controller: opensController,
                      enabled: !isClosed && !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Opens at',
                        hintText: '09:00',
                      ),
                    ),
                    TextField(
                      controller: closesController,
                      enabled: !isClosed && !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Closes at',
                        hintText: '18:00',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          try {
                            await repository.upsertStoreOpeningHour(
                              storeId: storeId,
                              dayOfWeek: dayOfWeek,
                              opensAt: opensController.text.trim().isEmpty
                                  ? '09:00'
                                  : opensController.text.trim(),
                              closesAt: closesController.text.trim().isEmpty
                                  ? '18:00'
                                  : closesController.text.trim(),
                              isClosed: isClosed,
                            );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          } on Object catch (error) {
                            setDialogState(() => isSubmitting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Hours update failed: $error'),
                                ),
                              );
                            }
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    opensController.dispose();
    closesController.dispose();
  }
}

class _AdminOperationsAlertsPanel extends StatelessWidget {
  const _AdminOperationsAlertsPanel({
    required this.orders,
    required this.catalog,
  });

  final List<OrderSummary> orders;
  final List<CatalogItem> catalog;

  @override
  Widget build(BuildContext context) {
    final unassignedReady = orders
        .where(
          (order) =>
              order.paymentStatus == 'paid' &&
              order.status == 'ready_for_pickup' &&
              order.riderId == null,
        )
        .toList();
    final lateDeliveries = orders.where(_isOrderEtaLate).toList();
    final pendingPayments = orders
        .where(
          (order) =>
              order.status == 'pending_payment' &&
              order.paymentStatus == 'pending',
        )
        .toList();
    final outOfStockListed = catalog
        .where((item) => item.isAvailable && item.quantityAvailable <= 0)
        .toList();
    final lowStockListed = catalog
        .where(
          (item) =>
              item.isAvailable &&
              item.quantityAvailable > 0 &&
              item.quantityAvailable <= 5,
        )
        .toList();
    final hasAlerts = unassignedReady.isNotEmpty ||
        lateDeliveries.isNotEmpty ||
        pendingPayments.isNotEmpty ||
        outOfStockListed.isNotEmpty ||
        lowStockListed.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Operations alerts',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(
                  avatar: Icon(
                    hasAlerts
                        ? Icons.priority_high_outlined
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(hasAlerts ? 'Attention needed' : 'Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!hasAlerts)
              const Text('No urgent dispatch, payment, or catalog issues.')
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AlertChip(
                    icon: Icons.assignment_ind_outlined,
                    label: '${unassignedReady.length} unassigned pickups',
                    isActive: unassignedReady.isNotEmpty,
                  ),
                  _AlertChip(
                    icon: Icons.schedule,
                    label: '${lateDeliveries.length} late ETAs',
                    isActive: lateDeliveries.isNotEmpty,
                  ),
                  _AlertChip(
                    icon: Icons.payment_outlined,
                    label: '${pendingPayments.length} pending payments',
                    isActive: pendingPayments.isNotEmpty,
                  ),
                  _AlertChip(
                    icon: Icons.remove_shopping_cart_outlined,
                    label: '${outOfStockListed.length} listed out of stock',
                    isActive: outOfStockListed.isNotEmpty,
                  ),
                  _AlertChip(
                    icon: Icons.inventory_outlined,
                    label: '${lowStockListed.length} low stock',
                    isActive: lowStockListed.isNotEmpty,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final order in unassignedReady.take(3))
                _AlertLine(
                  icon: Icons.local_shipping_outlined,
                  text:
                      'Assign rider for ${order.storeName} #${_shortId(order.id)}',
                ),
              for (final order in lateDeliveries.take(3))
                _AlertLine(
                  icon: Icons.timer_off_outlined,
                  text: 'Late ETA: ${order.storeName} #${_shortId(order.id)}',
                ),
              for (final item in outOfStockListed.take(3))
                _AlertLine(
                  icon: Icons.inventory_2_outlined,
                  text: '${item.storeName}: ${item.name} is listed but empty',
                ),
              for (final item in lowStockListed.take(3))
                _AlertLine(
                  icon: Icons.inventory_outlined,
                  text:
                      '${item.storeName}: ${item.name} has ${item.quantityAvailable} left',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlertChip extends StatelessWidget {
  const _AlertChip({
    required this.icon,
    required this.label,
    required this.isActive,
  });

  final IconData icon;
  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      backgroundColor:
          isActive ? Theme.of(context).colorScheme.errorContainer : null,
    );
  }
}

class _AlertLine extends StatelessWidget {
  const _AlertLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CreateStorePanel extends StatelessWidget {
  const _CreateStorePanel({
    required this.formKey,
    required this.nameController,
    required this.categoryController,
    required this.addressController,
    required this.isSubmitting,
    required this.isResolvingAddress,
    required this.onUseCurrentLocation,
    required this.onFindAddress,
    required this.onAddressChanged,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController categoryController;
  final TextEditingController addressController;
  final bool isSubmitting;
  final bool isResolvingAddress;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onFindAddress;
  final VoidCallback onAddressChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Create store',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Store name',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: categoryController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: addressController,
                textInputAction: TextInputAction.done,
                onChanged: (_) => onAddressChanged(),
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: isResolvingAddress ? null : onUseCurrentLocation,
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      isResolvingAddress ? 'Resolving...' : 'Use current',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: isResolvingAddress ? null : onFindAddress,
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Find address'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: isSubmitting ? null : onSubmit,
                icon: const Icon(Icons.add_business),
                label: Text(isSubmitting ? 'Creating...' : 'Create store'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminAddressResultsSheet extends StatelessWidget {
  const _AdminAddressResultsSheet({required this.results});

  final List<MapboxAddressResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No addresses matched that search.'),
        ),
      );
    }

    return SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: results.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final result = results[index];
          return ListTile(
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

class _CatalogThumbnail extends StatelessWidget {
  const _CatalogThumbnail({
    required this.imageUrl,
    required this.icon,
  });

  final String? imageUrl;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: 48,
        child: url == null || url.isEmpty
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
      ),
    );
  }
}

class _CreateProductPanel extends StatelessWidget {
  const _CreateProductPanel({
    required this.formKey,
    required this.stores,
    required this.selectedStoreId,
    required this.onStoreChanged,
    required this.nameController,
    required this.descriptionController,
    required this.categoryController,
    required this.priceController,
    required this.stockController,
    required this.skuController,
    required this.imageUrlController,
    required this.reorderController,
    required this.isUploadingImage,
    required this.isSubmitting,
    required this.onUploadImage,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final List<StoreSummary> stores;
  final String? selectedStoreId;
  final ValueChanged<String?> onStoreChanged;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController categoryController;
  final TextEditingController priceController;
  final TextEditingController stockController;
  final TextEditingController skuController;
  final TextEditingController imageUrlController;
  final TextEditingController reorderController;
  final bool isUploadingImage;
  final bool isSubmitting;
  final VoidCallback onUploadImage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create product',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: stores.any((store) => store.id == selectedStoreId)
                    ? selectedStoreId
                    : null,
                items: [
                  for (final store in stores)
                    DropdownMenuItem(
                      value: store.id,
                      child: Text(store.name),
                    ),
                ],
                onChanged: isSubmitting ? null : onStoreChanged,
                decoration: const InputDecoration(
                  labelText: 'Store',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null ? 'Select a store' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Product name',
                  border: OutlineInputBorder(),
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descriptionController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: categoryController,
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
                      controller: priceController,
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
                      controller: stockController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Initial stock',
                        border: OutlineInputBorder(),
                      ),
                      validator: _wholeNumber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: skuController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'SKU',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: reorderController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Reorder level',
                        border: OutlineInputBorder(),
                      ),
                      validator: _wholeNumber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: imageUrlController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Image URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    isSubmitting || isUploadingImage ? null : onUploadImage,
                icon: const Icon(Icons.upload_file),
                label: Text(
                  isUploadingImage ? 'Uploading...' : 'Upload image',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: isSubmitting ? null : onSubmit,
                icon: const Icon(Icons.add_box),
                label: Text(isSubmitting ? 'Creating...' : 'Create product'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateOperationalUserPanel extends StatelessWidget {
  const _CreateOperationalUserPanel({
    required this.formKey,
    required this.stores,
    required this.selectedRole,
    required this.selectedStoreId,
    required this.emailController,
    required this.passwordController,
    required this.fullNameController,
    required this.phoneController,
    required this.canManageInventory,
    required this.canManageOrders,
    required this.isSubmitting,
    required this.onRoleChanged,
    required this.onStoreChanged,
    required this.onInventoryPermissionChanged,
    required this.onOrdersPermissionChanged,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final List<StoreSummary> stores;
  final String selectedRole;
  final String? selectedStoreId;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController fullNameController;
  final TextEditingController phoneController;
  final bool canManageInventory;
  final bool canManageOrders;
  final bool isSubmitting;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String?> onStoreChanged;
  final ValueChanged<bool> onInventoryPermissionChanged;
  final ValueChanged<bool> onOrdersPermissionChanged;
  final VoidCallback onSubmit;

  static const _roles = [
    'rider',
    'store_admin',
    'rider_admin',
    'admin',
    'super_admin',
    'customer',
  ];

  @override
  Widget build(BuildContext context) {
    final isStoreStaff = selectedRole == 'store_admin';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create operational user',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final roleField = DropdownButtonFormField<String>(
                    initialValue: _roles.contains(selectedRole)
                        ? selectedRole
                        : _roles.first,
                    items: [
                      for (final role in _roles)
                        DropdownMenuItem(
                          value: role,
                          child: Text(_humanStatus(role)),
                        ),
                    ],
                    onChanged:
                        isSubmitting ? null : (value) => onRoleChanged(value!),
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                  );

                  final storeField = DropdownButtonFormField<String>(
                    initialValue:
                        stores.any((store) => store.id == selectedStoreId)
                            ? selectedStoreId
                            : null,
                    items: [
                      for (final store in stores)
                        DropdownMenuItem(
                          value: store.id,
                          child: Text(store.name),
                        ),
                    ],
                    onChanged: isSubmitting ? null : onStoreChanged,
                    decoration: const InputDecoration(
                      labelText: 'Store',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        isStoreStaff && value == null ? 'Select a store' : null,
                  );

                  final emailField = TextFormField(
                    controller: emailController,
                    enabled: !isSubmitting,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: _emailText,
                  );

                  final passwordField = TextFormField(
                    controller: passwordController,
                    enabled: !isSubmitting,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Temporary password',
                      border: OutlineInputBorder(),
                    ),
                    validator: _passwordText,
                  );

                  final fields = [
                    roleField,
                    if (isStoreStaff) storeField,
                    emailField,
                    passwordField,
                  ];

                  if (constraints.maxWidth < 900) {
                    return Column(
                      children: [
                        for (final field in fields) ...[
                          field,
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  }

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final field in fields)
                        SizedBox(
                          width: isStoreStaff
                              ? (constraints.maxWidth - 36) / 4
                              : (constraints.maxWidth - 24) / 3,
                          child: field,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: fullNameController,
                      enabled: !isSubmitting,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredText,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: phoneController,
                      enabled: !isSubmitting,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              if (isStoreStaff) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  children: [
                    FilterChip(
                      label: const Text('Inventory access'),
                      selected: canManageInventory,
                      onSelected:
                          isSubmitting ? null : onInventoryPermissionChanged,
                    ),
                    FilterChip(
                      label: const Text('Order access'),
                      selected: canManageOrders,
                      onSelected:
                          isSubmitting ? null : onOrdersPermissionChanged,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: isSubmitting ? null : onSubmit,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(isSubmitting ? 'Creating...' : 'Create user'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminCatalogPanel extends StatefulWidget {
  const _AdminCatalogPanel({required this.catalog});

  final List<CatalogItem> catalog;

  @override
  State<_AdminCatalogPanel> createState() => _AdminCatalogPanelState();
}

class _AdminCatalogPanelState extends State<_AdminCatalogPanel> {
  final _searchController = TextEditingController();
  var _selectedCategory = 'all';
  var _availabilityFilter = 'all';
  var _page = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _catalogCategories(widget.catalog);
    if (_selectedCategory != 'all' && !categories.contains(_selectedCategory)) {
      _selectedCategory = 'all';
    }

    final visibleItems = widget.catalog.where((item) {
      final matchesCategory =
          _selectedCategory == 'all' || item.category == _selectedCategory;
      final matchesAvailability = _availabilityFilter == 'all' ||
          (_availabilityFilter == 'available' && item.isAvailable) ||
          (_availabilityFilter == 'unavailable' && !item.isAvailable);
      final matchesSearch = _matchesCatalogSearch(
        item,
        _searchController.text,
      );
      return matchesCategory && matchesAvailability && matchesSearch;
    }).toList();
    final safePage = _coerceListPage(_page, visibleItems.length);
    if (safePage != _page) {
      _page = safePage;
    }
    final pagedItems = visibleItems
        .skip(safePage * _adminListPageSize)
        .take(_adminListPageSize)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Customer catalog',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('${visibleItems.length} total')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() => _page = 0),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _page = 0;
                        }),
                        icon: const Icon(Icons.close),
                      ),
                labelText: 'Search catalog',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All categories'),
                  selected: _selectedCategory == 'all',
                  onSelected: (_) => setState(() {
                    _selectedCategory = 'all';
                    _page = 0;
                  }),
                ),
                for (final category in categories)
                  ChoiceChip(
                    label: Text(_humanStatus(category)),
                    selected: _selectedCategory == category,
                    onSelected: (_) => setState(() {
                      _selectedCategory = category;
                      _page = 0;
                    }),
                  ),
                FilterChip(
                  label: const Text('Available'),
                  selected: _availabilityFilter == 'available',
                  onSelected: (value) => setState(
                    () {
                      _availabilityFilter = value ? 'available' : 'all';
                      _page = 0;
                    },
                  ),
                ),
                FilterChip(
                  label: const Text('Unavailable'),
                  selected: _availabilityFilter == 'unavailable',
                  onSelected: (value) => setState(
                    () {
                      _availabilityFilter = value ? 'unavailable' : 'all';
                      _page = 0;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.catalog.isEmpty)
              const Text('No products yet')
            else if (visibleItems.isEmpty)
              const Text('No catalog items match these filters')
            else ...[
              _PagedListControls(
                page: safePage,
                totalItems: visibleItems.length,
                onPageChanged: (page) => setState(() => _page = page),
              ),
              const SizedBox(height: 8),
              for (final item in pagedItems)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    leading: _CatalogThumbnail(
                      imageUrl: item.imageUrl,
                      icon: Icons.fastfood_outlined,
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.storeName} | ${_humanStatus(item.category)} | NGN ${item.price.toStringAsFixed(2)} '
                      '| Stock ${item.quantityAvailable}',
                    ),
                    trailing: Text(
                      item.isAvailable ? 'Available' : 'Unavailable',
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              _PagedListControls(
                page: safePage,
                totalItems: visibleItems.length,
                onPageChanged: (page) => setState(() => _page = page),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminOrdersPanel extends StatefulWidget {
  const _AdminOrdersPanel({
    required this.repository,
    required this.orders,
    required this.profiles,
  });

  final PlatformRepository repository;
  final List<OrderSummary> orders;
  final List<UserProfile> profiles;

  @override
  State<_AdminOrdersPanel> createState() => _AdminOrdersPanelState();
}

class _AdminOrdersPanelState extends State<_AdminOrdersPanel> {
  final _searchController = TextEditingController();
  var _filter = 'active';
  var _page = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleOrders = widget.orders.where((order) {
      final matchesFilter = switch (_filter) {
        'pending_payment' => order.paymentStatus == 'pending',
        'paid' => order.paymentStatus == 'paid',
        'delivered' => order.status == 'delivered',
        'all' => true,
        _ => order.status != 'delivered' && order.status != 'cancelled',
      };
      final matchesSearch = _matchesOrderSearch(order, _searchController.text);
      return matchesFilter && matchesSearch;
    }).toList();
    final safePage = _coerceListPage(_page, visibleOrders.length);
    if (safePage != _page) {
      _page = safePage;
    }
    final pagedOrders = visibleOrders
        .skip(safePage * _adminListPageSize)
        .take(_adminListPageSize)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Platform orders',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('${visibleOrders.length} total')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() => _page = 0),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _page = 0;
                        }),
                        icon: const Icon(Icons.close),
                      ),
                labelText: 'Search orders, stores, or addresses',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Active'),
                  selected: _filter == 'active',
                  onSelected: (_) => setState(() {
                    _filter = 'active';
                    _page = 0;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Pending payment'),
                  selected: _filter == 'pending_payment',
                  onSelected: (_) => setState(() {
                    _filter = 'pending_payment';
                    _page = 0;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Paid'),
                  selected: _filter == 'paid',
                  onSelected: (_) => setState(() {
                    _filter = 'paid';
                    _page = 0;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Delivered'),
                  selected: _filter == 'delivered',
                  onSelected: (_) => setState(() {
                    _filter = 'delivered';
                    _page = 0;
                  }),
                ),
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() {
                    _filter = 'all';
                    _page = 0;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.orders.isEmpty)
              const Text('No orders yet')
            else if (visibleOrders.isEmpty)
              const Text('No orders match these filters')
            else ...[
              _PagedListControls(
                page: safePage,
                totalItems: visibleOrders.length,
                onPageChanged: (page) => setState(() => _page = page),
              ),
              const SizedBox(height: 8),
              for (final order in pagedOrders)
                _AdminOrderCard(
                  repository: widget.repository,
                  order: order,
                  profiles: widget.profiles,
                ),
              const SizedBox(height: 8),
              _PagedListControls(
                page: safePage,
                totalItems: visibleOrders.length,
                onPageChanged: (page) => setState(() => _page = page),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.repository,
    required this.order,
    required this.profiles,
  });

  final PlatformRepository repository;
  final OrderSummary order;
  final List<UserProfile> profiles;

  @override
  Widget build(BuildContext context) {
    final assignedRider = _findProfileById(profiles, order.riderId);
    final canAssignRider = order.paymentStatus == 'paid' &&
        (order.status == 'ready_for_pickup' ||
            order.status == 'out_for_delivery');
    final canCancelOrder =
        order.status != 'cancelled' && order.status != 'delivered';
    final canMarkRefunded = order.paymentStatus == 'paid';

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text('${order.storeName} #${_shortId(order.id)}'),
        subtitle: Text(
          '${_humanStatus(order.status)} | '
          '${_humanStatus(order.paymentStatus)} | '
          '${_humanStatus(order.fulfillmentType)}',
        ),
        trailing: Text('NGN ${order.totalAmount.toStringAsFixed(2)}'),
        children: [
          _OrderItemsList(repository: repository, orderId: order.id),
          const SizedBox(height: 8),
          _AdminOrderRevenueBreakdown(order: order),
          if (order.fulfillmentType == 'pickup') ...[
            const SizedBox(height: 12),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.storefront_outlined, size: 18),
                SizedBox(width: 6),
                Expanded(child: Text('Pickup order')),
              ],
            ),
          ] else if (order.deliveryAddress.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(order.deliveryAddress)),
              ],
            ),
          ],
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
          _OrderContactLine(
            icon: Icons.delivery_dining_outlined,
            label: 'Rider',
            value: order.riderId == null
                ? 'No rider assigned'
                : _contactText(
                    name: order.riderName ?? assignedRider?.displayName,
                    phone: order.riderPhone,
                    fallback: 'Rider ${_shortId(order.riderId!)}',
                  ),
          ),
          const SizedBox(height: 12),
          _RiderLocationList(repository: repository, orderId: order.id),
          const SizedBox(height: 12),
          _DeliveryEventsList(repository: repository, orderId: order.id),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Updated ${_formatDateTime(order.updatedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: canAssignRider
                      ? () => _showAssignRiderDialog(
                            context: context,
                            repository: repository,
                            order: order,
                            profiles: profiles,
                          )
                      : null,
                  icon: const Icon(Icons.assignment_ind_outlined),
                  label: Text(
                    order.riderId == null ? 'Assign rider' : 'Reassign rider',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: canCancelOrder
                      ? () => _showAdminOrderResolutionDialog(
                            context: context,
                            repository: repository,
                            order: order,
                            action: _AdminOrderAction.cancel,
                          )
                      : null,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
                OutlinedButton.icon(
                  onPressed: canMarkRefunded
                      ? () => _showAdminOrderResolutionDialog(
                            context: context,
                            repository: repository,
                            order: order,
                            action: _AdminOrderAction.refund,
                          )
                      : null,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Refunded'),
                ),
              ],
            ),
          ),
        ],
      ),
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

enum _AdminOrderAction { cancel, refund }

Future<void> _showAdminOrderResolutionDialog({
  required BuildContext context,
  required PlatformRepository repository,
  required OrderSummary order,
  required _AdminOrderAction action,
}) async {
  final noteController = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  final isRefund = action == _AdminOrderAction.refund;
  final canRestock = order.status != 'delivered';
  var restock = canRestock;
  var isSubmitting = false;

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              setDialogState(() => isSubmitting = true);
              try {
                final note = noteController.text.trim();
                if (isRefund) {
                  await repository.markOrderRefundedAsAdmin(
                    orderId: order.id,
                    note: note.isEmpty ? null : note,
                    restock: restock,
                  );
                } else {
                  await repository.cancelOrderAsAdmin(
                    orderId: order.id,
                    note: note.isEmpty ? null : note,
                    restock: restock,
                  );
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      isRefund ? 'Order marked refunded' : 'Order cancelled',
                    ),
                  ),
                );
              } on Object catch (error) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Order update failed: $error')),
                );
              } finally {
                if (context.mounted) {
                  setDialogState(() => isSubmitting = false);
                }
              }
            }

            return AlertDialog(
              title: Text(
                isRefund
                    ? 'Mark order refunded?'
                    : 'Cancel order #${_shortId(order.id)}?',
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isRefund
                          ? 'This records the payment as refunded and cancels the order unless it was already delivered.'
                          : 'This cancels the order and records the intervention in the delivery timeline.',
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: restock,
                      onChanged: !canRestock || isSubmitting
                          ? null
                          : (value) => setDialogState(
                                () => restock = value ?? true,
                              ),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Return items to inventory'),
                      subtitle: canRestock
                          ? null
                          : const Text('Delivered orders are not restocked'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteController,
                      enabled: !isSubmitting,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Timeline note',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isSubmitting ? null : submit,
                  icon: isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isRefund
                              ? Icons.payments_outlined
                              : Icons.cancel_outlined,
                        ),
                  label: Text(isRefund ? 'Mark refunded' : 'Cancel order'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    noteController.dispose();
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

Future<void> _showAssignRiderDialog({
  required BuildContext context,
  required PlatformRepository repository,
  required OrderSummary order,
  required List<UserProfile> profiles,
}) async {
  final etaController = TextEditingController(
    text: order.etaMinutes?.toString() ?? '30',
  );
  final noteController = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  var selectedRiderId = order.riderId;
  var isSubmitting = false;

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return StreamBuilder<List<RiderAvailability>>(
              stream: repository.watchRiderAvailability(),
              builder: (context, snapshot) {
                final availabilityByRiderId = {
                  for (final availability
                      in snapshot.data ?? const <RiderAvailability>[])
                    availability.riderId: availability,
                };
                final onlineRiders = profiles
                    .where(
                      (profile) =>
                          profile.role == 'rider' &&
                          (availabilityByRiderId[profile.id]?.isOnline ??
                              false),
                    )
                    .toList()
                  ..sort((a, b) => a.displayName.compareTo(b.displayName));
                final onlineRiderIds =
                    onlineRiders.map((rider) => rider.id).toSet();
                final selectedValue = onlineRiderIds.contains(selectedRiderId)
                    ? selectedRiderId
                    : null;

                Future<void> submit() async {
                  final riderId = selectedValue;
                  if (riderId == null) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Select an online rider')),
                    );
                    return;
                  }

                  final etaText = etaController.text.trim();
                  final etaMinutes = etaText.isEmpty
                      ? null
                      : int.tryParse(etaController.text.trim());
                  if (etaText.isNotEmpty && etaMinutes == null) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Enter a valid ETA')),
                    );
                    return;
                  }

                  setDialogState(() => isSubmitting = true);
                  try {
                    await repository.assignOrderRider(
                      orderId: order.id,
                      riderId: riderId,
                      etaMinutes: etaMinutes,
                      note: noteController.text.trim().isEmpty
                          ? null
                          : noteController.text.trim(),
                    );
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Rider assigned')),
                    );
                  } on Object catch (error) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Assignment failed: $error')),
                    );
                  } finally {
                    if (context.mounted) {
                      setDialogState(() => isSubmitting = false);
                    }
                  }
                }

                return AlertDialog(
                  title: Text('Assign rider #${_shortId(order.id)}'),
                  content: SizedBox(
                    width: 520,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (snapshot.hasError)
                          Text('Riders failed to load: ${snapshot.error}')
                        else if (snapshot.connectionState ==
                            ConnectionState.waiting)
                          const LinearProgressIndicator()
                        else if (onlineRiders.isEmpty)
                          const Text('No riders are online right now.')
                        else
                          DropdownButtonFormField<String>(
                            initialValue: selectedValue,
                            items: [
                              for (final rider in onlineRiders)
                                DropdownMenuItem(
                                  value: rider.id,
                                  child: Text(
                                    rider.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: isSubmitting
                                ? null
                                : (value) => setDialogState(
                                      () => selectedRiderId = value,
                                    ),
                            decoration: const InputDecoration(
                              labelText: 'Online rider',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: etaController,
                          enabled: !isSubmitting,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ETA minutes',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: noteController,
                          enabled: !isSubmitting,
                          minLines: 2,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Dispatch note',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: isSubmitting
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          isSubmitting || onlineRiders.isEmpty ? null : submit,
                      icon: isSubmitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.assignment_ind_outlined),
                      label: const Text('Assign'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  } finally {
    etaController.dispose();
    noteController.dispose();
  }
}

class _AdminPaymentsPanel extends StatefulWidget {
  const _AdminPaymentsPanel({required this.repository});

  final PlatformRepository repository;

  @override
  State<_AdminPaymentsPanel> createState() => _AdminPaymentsPanelState();
}

class _AdminPaymentsPanelState extends State<_AdminPaymentsPanel> {
  var _statusFilter = 'all';
  var _page = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PaymentSummary>>(
      stream: widget.repository.watchPaymentSummaries(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Payments failed to load: ${snapshot.error}'),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          );
        }

        final payments = snapshot.data ?? const <PaymentSummary>[];
        final visiblePayments = _statusFilter == 'all'
            ? payments
            : payments
                .where((payment) => payment.status == _statusFilter)
                .toList();
        final safePage = _coerceListPage(_page, visiblePayments.length);
        if (safePage != _page) {
          _page = safePage;
        }
        final pagedPayments = visiblePayments
            .skip(safePage * _adminListPageSize)
            .take(_adminListPageSize)
            .toList();
        final paidTotal = payments
            .where((payment) => payment.status == 'paid')
            .fold<double>(0, (total, payment) => total + payment.amount);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Payments',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Chip(label: Text('Paid ${_formatNaira(paidTotal)}')),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in const [
                      'all',
                      'pending',
                      'paid',
                      'failed',
                      'expired',
                      'refunded',
                    ])
                      ChoiceChip(
                        label: Text(_humanStatus(status)),
                        selected: _statusFilter == status,
                        onSelected: (_) => setState(() {
                          _statusFilter = status;
                          _page = 0;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (payments.isEmpty)
                  const Text('No payments yet')
                else if (visiblePayments.isEmpty)
                  const Text('No payments match this status')
                else ...[
                  _PagedListControls(
                    page: safePage,
                    totalItems: visiblePayments.length,
                    onPageChanged: (page) => setState(() => _page = page),
                  ),
                  const SizedBox(height: 8),
                  for (final payment in pagedPayments)
                    Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: ListTile(
                        leading: Icon(_paymentStatusIcon(payment.status)),
                        title: Text(
                          '${payment.storeName} | NGN ${payment.amount.toStringAsFixed(2)}',
                        ),
                        subtitle: Text(
                          '${_humanStatus(payment.status)} | ${payment.paymentReference}\n'
                          'Order ${_shortId(payment.orderId)} | '
                          'Fees ${_formatNaira(payment.platformFeeAmount)} | '
                          'Store ${_formatNaira(payment.storePayoutAmount)} | '
                          '${_formatDateTime(payment.updatedAt)}',
                        ),
                        isThreeLine: true,
                        trailing: payment.providerTransactionReference == null
                            ? null
                            : Tooltip(
                                message: payment.providerTransactionReference!,
                                child: const Icon(Icons.receipt_long_outlined),
                              ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _PagedListControls(
                    page: safePage,
                    totalItems: visiblePayments.length,
                    onPageChanged: (page) => setState(() => _page = page),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SplitPaymentRoutingPanel extends StatelessWidget {
  const _SplitPaymentRoutingPanel({required this.orders});

  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context) {
    final paidOrders =
        orders.where((order) => order.paymentStatus == 'paid').toList();
    final grossMerchandiseValue = paidOrders.fold<double>(
      0,
      (total, order) => total + order.totalAmount,
    );
    final storeSplit = paidOrders.fold<double>(
      0,
      (total, order) => total + order.storePayoutAmount,
    );
    final riderSplit = paidOrders.fold<double>(
      0,
      (total, order) => total + order.riderPayoutAmount,
    );
    final platformSplit = paidOrders.fold<double>(
      0,
      (total, order) => total + order.platformFeeAmount,
    );
    final totalRouted = storeSplit + riderSplit + platformSplit;
    final missingSplitOrders = paidOrders
        .where((order) =>
            order.storePayoutAmount <= 0 &&
            order.riderPayoutAmount <= 0 &&
            order.platformFeeAmount <= 0)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Monnify split routing',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('${paidOrders.length} paid orders')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Customer payments are split directly to store, rider, and platform accounts during checkout. There is no manual settlement queue for staff to clear.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _AdminMetricGrid(
              children: [
                _MetricCard(
                  label: 'Gross merchandise value',
                  value: _formatNaira(grossMerchandiseValue),
                  icon: Icons.shopping_bag_outlined,
                ),
                _MetricCard(
                  label: 'Store split',
                  value: _formatNaira(storeSplit),
                  icon: Icons.storefront_outlined,
                ),
                _MetricCard(
                  label: 'Rider split',
                  value: _formatNaira(riderSplit),
                  icon: Icons.delivery_dining,
                ),
                _MetricCard(
                  label: 'Platform split',
                  value: _formatNaira(platformSplit),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SplitRouteBar(
              storeSplit: storeSplit,
              riderSplit: riderSplit,
              platformSplit: platformSplit,
              totalRouted: totalRouted,
            ),
            if (missingSplitOrders > 0) ...[
              const SizedBox(height: 12),
              _InlineState(
                title: 'Split data needs review',
                message:
                    '$missingSplitOrders paid order(s) have no split amounts recorded. Check Monnify split setup and order revenue fields.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SplitRouteBar extends StatelessWidget {
  const _SplitRouteBar({
    required this.storeSplit,
    required this.riderSplit,
    required this.platformSplit,
    required this.totalRouted,
  });

  final double storeSplit;
  final double riderSplit;
  final double platformSplit;
  final double totalRouted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = totalRouted <= 0 ? 1.0 : totalRouted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 18,
            child: Row(
              children: [
                _SplitRouteSegment(
                  value: storeSplit / total,
                  color: colorScheme.primary,
                ),
                _SplitRouteSegment(
                  value: riderSplit / total,
                  color: colorScheme.secondary,
                ),
                _SplitRouteSegment(
                  value: platformSplit / total,
                  color: colorScheme.tertiary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _LegendChip(
              color: colorScheme.primary,
              label: 'Stores ${_formatNaira(storeSplit)}',
            ),
            _LegendChip(
              color: colorScheme.secondary,
              label: 'Riders ${_formatNaira(riderSplit)}',
            ),
            _LegendChip(
              color: colorScheme.tertiary,
              label: 'Platform ${_formatNaira(platformSplit)}',
            ),
          ],
        ),
      ],
    );
  }
}

class _SplitRouteSegment extends StatelessWidget {
  const _SplitRouteSegment({
    required this.value,
    required this.color,
  });

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (value * 1000).round().clamp(1, 1000).toInt(),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, animatedValue, child) {
          return ColoredBox(
            color: color.withValues(
              alpha: animatedValue <= 0 ? 0.12 : 1,
            ),
          );
        },
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text(label),
    );
  }
}

class _AdminRevenueSettingsPanel extends StatefulWidget {
  const _AdminRevenueSettingsPanel({required this.repository});

  final PlatformRepository repository;

  @override
  State<_AdminRevenueSettingsPanel> createState() =>
      _AdminRevenueSettingsPanelState();
}

class _AdminRevenueSettingsPanelState
    extends State<_AdminRevenueSettingsPanel> {
  final _formKey = GlobalKey<FormState>();
  final _deliveryFeeController = TextEditingController();
  final _servicePercentController = TextEditingController();
  final _serviceFixedController = TextEditingController();
  final _riderPayoutController = TextEditingController();
  final _deliveryBaseKmController = TextEditingController();
  final _deliveryPerKmController = TextEditingController();
  final _minimumDeliveryFeeController = TextEditingController();
  var _isActive = true;
  var _isSaving = false;
  var _hasLoadedInitialValues = false;

  @override
  void dispose() {
    _deliveryFeeController.dispose();
    _servicePercentController.dispose();
    _serviceFixedController.dispose();
    _riderPayoutController.dispose();
    _deliveryBaseKmController.dispose();
    _deliveryPerKmController.dispose();
    _minimumDeliveryFeeController.dispose();
    super.dispose();
  }

  void _loadSettings(PlatformFeeSettings settings) {
    if (_hasLoadedInitialValues) {
      return;
    }

    _deliveryFeeController.text = settings.deliveryFee.toStringAsFixed(0);
    _servicePercentController.text =
        settings.serviceFeePercent.toStringAsFixed(2);
    _serviceFixedController.text = settings.serviceFeeFixed.toStringAsFixed(0);
    _riderPayoutController.text =
        settings.riderDeliveryPayout.toStringAsFixed(0);
    _deliveryBaseKmController.text = settings.deliveryBaseKm.toStringAsFixed(1);
    _deliveryPerKmController.text =
        settings.deliveryFeePerKm.toStringAsFixed(0);
    _minimumDeliveryFeeController.text =
        settings.minimumDeliveryFee.toStringAsFixed(0);
    _isActive = settings.isActive;
    _hasLoadedInitialValues = true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.updatePlatformFeeSettings(
        deliveryFee: double.parse(_deliveryFeeController.text.trim()),
        serviceFeePercent: double.parse(_servicePercentController.text.trim()),
        serviceFeeFixed: double.parse(_serviceFixedController.text.trim()),
        riderDeliveryPayout: double.parse(_riderPayoutController.text.trim()),
        deliveryBaseKm: double.parse(_deliveryBaseKmController.text.trim()),
        deliveryFeePerKm: double.parse(_deliveryPerKmController.text.trim()),
        minimumDeliveryFee:
            double.parse(_minimumDeliveryFeeController.text.trim()),
        isActive: _isActive,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Revenue settings updated')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Revenue settings failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlatformFeeSettings?>(
      stream: widget.repository.watchPlatformFeeSettings(),
      builder: (context, snapshot) {
        final settings = snapshot.data;
        if (settings != null) {
          _loadSettings(settings);
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Revenue settings failed: ${snapshot.error}'),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Revenue settings',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'These values are used by checkout quotes and order creation, including delivery fee, service fee, rider payout, and Monnify split amounts.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fields = [
                        TextFormField(
                          controller: _deliveryFeeController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Delivery fee',
                            prefixText: 'NGN ',
                            border: OutlineInputBorder(),
                          ),
                          validator: _nonNegativeNumber,
                        ),
                        TextFormField(
                          controller: _servicePercentController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Service fee percent',
                            suffixText: '%',
                            border: OutlineInputBorder(),
                          ),
                          validator: _nonNegativeNumber,
                        ),
                        TextFormField(
                          controller: _serviceFixedController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Fixed service fee',
                            prefixText: 'NGN ',
                            border: OutlineInputBorder(),
                          ),
                          validator: _nonNegativeNumber,
                        ),
                        TextFormField(
                          controller: _riderPayoutController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Rider delivery payout',
                            prefixText: 'NGN ',
                            border: OutlineInputBorder(),
                          ),
                          validator: _nonNegativeNumber,
                        ),
                        TextFormField(
                          controller: _deliveryBaseKmController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Base distance',
                            suffixText: 'km',
                            border: OutlineInputBorder(),
                          ),
                          validator: _nonNegativeNumber,
                        ),
                        TextFormField(
                          controller: _deliveryPerKmController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Extra distance fee',
                            prefixText: 'NGN ',
                            suffixText: '/ km',
                            border: OutlineInputBorder(),
                          ),
                          validator: _nonNegativeNumber,
                        ),
                        TextFormField(
                          controller: _minimumDeliveryFeeController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minimum delivery fee',
                            prefixText: 'NGN ',
                            border: OutlineInputBorder(),
                          ),
                          validator: _nonNegativeNumber,
                        ),
                      ];

                      if (constraints.maxWidth < 900) {
                        return Column(
                          children: [
                            for (final field in fields) ...[
                              field,
                              const SizedBox(height: 12),
                            ],
                          ],
                        );
                      }

                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final field in fields)
                            SizedBox(
                              width: (constraints.maxWidth - 24) / 3,
                              child: field,
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Active'),
                        avatar: const Icon(Icons.tune),
                        selected: _isActive,
                        onSelected: _isSaving
                            ? null
                            : (value) => setState(() => _isActive = value),
                      ),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'Saving...' : 'Save settings'),
                      ),
                      if (settings != null)
                        Text(
                          'Updated ${_formatDateTime(settings.updatedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdminIssuesPanel extends StatefulWidget {
  const _AdminIssuesPanel({required this.repository});

  final PlatformRepository repository;

  @override
  State<_AdminIssuesPanel> createState() => _AdminIssuesPanelState();
}

class _AdminIssuesPanelState extends State<_AdminIssuesPanel> {
  var _statusFilter = 'open';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderIssueSummary>>(
      stream: widget.repository.watchOrderIssues(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Issues failed to load: ${snapshot.error}'),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          );
        }

        final issues = snapshot.data ?? const <OrderIssueSummary>[];
        final visibleIssues = _statusFilter == 'all'
            ? issues
            : issues.where((issue) => issue.status == _statusFilter).toList();
        final openCount =
            issues.where((issue) => issue.status == 'open').length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        selected: _statusFilter == status,
                        onSelected: (_) =>
                            setState(() => _statusFilter = status),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (issues.isEmpty)
                  const Text('No support issues yet')
                else if (visibleIssues.isEmpty)
                  const Text('No issues match this status')
                else
                  for (final issue in visibleIssues.take(12))
                    _AdminIssueCard(
                      repository: widget.repository,
                      issue: issue,
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminIssueCard extends StatelessWidget {
  const _AdminIssueCard({
    required this.repository,
    required this.issue,
  });

  final PlatformRepository repository;
  final OrderIssueSummary issue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_humanStatus(issue.category)} | ${issue.storeName}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(_humanStatus(issue.status))),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Order ${_shortId(issue.orderId)} | '
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in const [
                  'in_review',
                  'resolved',
                  'closed',
                ])
                  OutlinedButton(
                    onPressed: issue.status == status
                        ? null
                        : () => _showIssueUpdateDialog(
                              context: context,
                              repository: repository,
                              issue: issue,
                              status: status,
                            ),
                    child: Text(_humanStatus(status)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminReviewsPanel extends StatefulWidget {
  const _AdminReviewsPanel({required this.repository});

  final PlatformRepository repository;

  @override
  State<_AdminReviewsPanel> createState() => _AdminReviewsPanelState();
}

class _AdminReviewsPanelState extends State<_AdminReviewsPanel> {
  var _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderReviewSummary>>(
      stream: widget.repository.watchOrderReviews(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Reviews failed to load: ${snapshot.error}'),
            ),
          );
        }

        final reviews = snapshot.data ?? const <OrderReviewSummary>[];
        final visibleReviews = reviews.where((review) {
          return switch (_filter) {
            'low' => review.rating <= 2,
            'mid' => review.rating == 3,
            'high' => review.rating >= 4,
            _ => true,
          };
        }).toList();
        final average = reviews.isEmpty
            ? 0.0
            : reviews.fold<int>(0, (total, review) => total + review.rating) /
                reviews.length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Customer reviews',
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in const [
                      ('all', 'All'),
                      ('low', '1-2'),
                      ('mid', '3'),
                      ('high', '4-5'),
                    ])
                      ChoiceChip(
                        label: Text(option.$2),
                        selected: _filter == option.$1,
                        onSelected: (_) => setState(() => _filter = option.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (reviews.isEmpty)
                  const Text('No customer reviews yet')
                else if (visibleReviews.isEmpty)
                  const Text('No reviews match this filter')
                else
                  for (final review in visibleReviews.take(12))
                    _AdminReviewCard(review: review),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminReviewCard extends StatelessWidget {
  const _AdminReviewCard({required this.review});

  final OrderReviewSummary review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
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
                  '${review.storeName} | Order ${_shortId(review.orderId)}',
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
          Text(
            '${_humanStatus(review.orderStatus)} | '
            '${_humanStatus(review.paymentStatus)} | '
            'NGN ${review.totalAmount.toStringAsFixed(2)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
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

class _AdminPromosPanel extends StatelessWidget {
  const _AdminPromosPanel({
    required this.repository,
    required this.stores,
  });

  final PlatformRepository repository;
  final List<StoreSummary> stores;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PromoCodeSummary>>(
      stream: repository.watchPromoCodes(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Promos failed to load: ${snapshot.error}'),
            ),
          );
        }

        final promos = snapshot.data ?? const <PromoCodeSummary>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => _PromoCodeDialog(
                          repository: repository,
                          stores: stores,
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Create'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (promos.isEmpty)
                  const Text('No promo codes yet')
                else
                  for (final promo in promos.take(12))
                    _PromoCodeTile(promo: promo),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PromoCodeTile extends StatelessWidget {
  const _PromoCodeTile({required this.promo});

  final PromoCodeSummary promo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = promo.storeName ?? 'All stores';
    final discount = promo.discountType == 'percent'
        ? '${promo.discountValue.toStringAsFixed(0)}%'
        : 'NGN ${promo.discountValue.toStringAsFixed(2)}';

    return Container(
      margin: const EdgeInsets.only(top: 8),
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
                  '$scope | $discount off | Min NGN ${promo.minOrderAmount.toStringAsFixed(2)}',
                ),
                Text(
                  '${promo.redemptionCount}/${promo.maxRedemptions?.toString() ?? 'unlimited'} used',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Chip(label: Text(promo.isActive ? 'Active' : 'Inactive')),
        ],
      ),
    );
  }
}

class _PromoCodeDialog extends StatefulWidget {
  const _PromoCodeDialog({
    required this.repository,
    required this.stores,
  });

  final PlatformRepository repository;
  final List<StoreSummary> stores;

  @override
  State<_PromoCodeDialog> createState() => _PromoCodeDialogState();
}

class _PromoCodeDialogState extends State<_PromoCodeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _discountController = TextEditingController();
  final _minimumController = TextEditingController(text: '0');
  final _maxRedemptionsController = TextEditingController();
  String? _storeId;
  var _discountType = 'percent';
  var _isSubmitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    _descriptionController.dispose();
    _discountController.dispose();
    _minimumController.dispose();
    _maxRedemptionsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.createPromoCode(
        code: _codeController.text.trim(),
        discountType: _discountType,
        discountValue: double.parse(_discountController.text.trim()),
        storeId: _storeId,
        description: _descriptionController.text.trim(),
        minOrderAmount: double.parse(_minimumController.text.trim()),
        maxRedemptions: _maxRedemptionsController.text.trim().isEmpty
            ? null
            : int.parse(_maxRedemptionsController.text.trim()),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
      messenger.showSnackBar(const SnackBar(content: Text('Promo created')));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Promo creation failed: $error')),
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
      title: const Text('Create promo code'),
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
                  validator: (value) {
                    if ((value ?? '').trim().length < 3) {
                      return 'Use at least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _storeId,
                  decoration: const InputDecoration(
                    labelText: 'Scope',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All stores'),
                    ),
                    for (final store in widget.stores)
                      DropdownMenuItem<String?>(
                        value: store.id,
                        child: Text(store.name),
                      ),
                  ],
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _storeId = value),
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
                        validator: _positiveNumber,
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
                        validator: _nonNegativeNumber,
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
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return null;
                    }
                    final number = int.tryParse(text);
                    if (number == null || number <= 0) {
                      return 'Enter a whole number';
                    }
                    return null;
                  },
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
          label: const Text('Create'),
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

Future<void> _showIssueUpdateDialog({
  required BuildContext context,
  required PlatformRepository repository,
  required OrderIssueSummary issue,
  required String status,
}) async {
  final noteController = TextEditingController(text: issue.adminNote);
  final messenger = ScaffoldMessenger.of(context);
  var isSubmitting = false;

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              setDialogState(() => isSubmitting = true);
              try {
                final note = noteController.text.trim();
                await repository.updateOrderIssue(
                  issueId: issue.id,
                  status: status,
                  adminNote: note.isEmpty ? null : note,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Issue marked ${_humanStatus(status)}'),
                  ),
                );
              } on Object catch (error) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Issue update failed: $error')),
                );
              } finally {
                if (context.mounted) {
                  setDialogState(() => isSubmitting = false);
                }
              }
            }

            return AlertDialog(
              title: Text('Mark ${_humanStatus(status)}?'),
              content: SizedBox(
                width: 460,
                child: TextField(
                  controller: noteController,
                  enabled: !isSubmitting,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Admin note',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isSubmitting ? null : submit,
                  icon: isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    noteController.dispose();
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

class _StoreRosterPanel extends StatefulWidget {
  const _StoreRosterPanel({
    required this.stores,
    required this.profiles,
    required this.members,
    required this.selectedStoreId,
    required this.isSubmitting,
    required this.onStoreSelected,
    required this.onInventoryPermissionChanged,
    required this.onOrdersPermissionChanged,
    required this.onRemoveMember,
  });

  final List<StoreSummary> stores;
  final List<UserProfile> profiles;
  final List<StoreMember> members;
  final String? selectedStoreId;
  final bool isSubmitting;
  final ValueChanged<String?> onStoreSelected;
  final void Function(StoreMember member, bool value)
      onInventoryPermissionChanged;
  final void Function(StoreMember member, bool value) onOrdersPermissionChanged;
  final ValueChanged<StoreMember> onRemoveMember;

  @override
  State<_StoreRosterPanel> createState() => _StoreRosterPanelState();
}

class _StoreRosterPanelState extends State<_StoreRosterPanel> {
  var _page = 0;
  String? _lastStoreId;

  @override
  Widget build(BuildContext context) {
    if (_lastStoreId != widget.selectedStoreId) {
      _lastStoreId = widget.selectedStoreId;
      _page = 0;
    }
    final selectedStore = _findStoreById(widget.stores, widget.selectedStoreId);
    final selectedMembers = selectedStore == null
        ? const <StoreMember>[]
        : _membersForStore(widget.members, selectedStore.id);
    final safePage = _coerceListPage(_page, selectedMembers.length);
    if (safePage != _page) {
      _page = safePage;
    }
    final pagedMembers = selectedMembers
        .skip(safePage * _adminListPageSize)
        .take(_adminListPageSize)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Store roster',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('${selectedMembers.length} staff')),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedStore?.id,
              items: [
                for (final store in widget.stores)
                  DropdownMenuItem(
                    value: store.id,
                    child: Text(
                      store.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                setState(() => _page = 0);
                widget.onStoreSelected(value);
              },
              decoration: const InputDecoration(
                labelText: 'Store',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.stores.isEmpty)
              const Text('Create a store before assigning staff.')
            else if (selectedStore == null)
              const Text('Select a store to review staff access.')
            else if (selectedMembers.isEmpty)
              const Text('No staff assigned to this store yet.')
            else ...[
              _PagedListControls(
                page: safePage,
                totalItems: selectedMembers.length,
                onPageChanged: (page) => setState(() => _page = page),
              ),
              const SizedBox(height: 8),
              for (final member in pagedMembers)
                _StoreRosterMemberTile(
                  member: member,
                  profile: _findProfileById(widget.profiles, member.userId),
                  isSubmitting: widget.isSubmitting,
                  onInventoryPermissionChanged: (value) =>
                      widget.onInventoryPermissionChanged(member, value),
                  onOrdersPermissionChanged: (value) =>
                      widget.onOrdersPermissionChanged(member, value),
                  onRemove: () => widget.onRemoveMember(member),
                ),
              const SizedBox(height: 8),
              _PagedListControls(
                page: safePage,
                totalItems: selectedMembers.length,
                onPageChanged: (page) => setState(() => _page = page),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoreRosterMemberTile extends StatelessWidget {
  const _StoreRosterMemberTile({
    required this.member,
    required this.profile,
    required this.isSubmitting,
    required this.onInventoryPermissionChanged,
    required this.onOrdersPermissionChanged,
    required this.onRemove,
  });

  final StoreMember member;
  final UserProfile? profile;
  final bool isSubmitting;
  final ValueChanged<bool> onInventoryPermissionChanged;
  final ValueChanged<bool> onOrdersPermissionChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final displayName = profile?.displayName ?? member.userId;
    final role = profile?.role ?? 'unknown';

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(child: Icon(Icons.person_outline)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(label: Text(_humanStatus(role))),
                      Text('Added ${_formatDateTime(member.createdAt)}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Inventory'),
                        avatar: const Icon(Icons.inventory_2_outlined),
                        selected: member.canManageInventory,
                        onSelected:
                            isSubmitting ? null : onInventoryPermissionChanged,
                      ),
                      FilterChip(
                        label: const Text('Orders'),
                        avatar: const Icon(Icons.receipt_long_outlined),
                        selected: member.canManageOrders,
                        onSelected:
                            isSubmitting ? null : onOrdersPermissionChanged,
                      ),
                      OutlinedButton.icon(
                        onPressed: isSubmitting ? null : onRemove,
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('Remove'),
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

class _AdminStoreTile extends StatelessWidget {
  const _AdminStoreTile({
    required this.store,
    required this.staffCount,
    required this.isSelected,
    required this.isSubmitting,
    required this.onSelected,
    required this.onOpenChanged,
    required this.onActiveChanged,
  });

  final StoreSummary store;
  final int staffCount;
  final bool isSelected;
  final bool isSubmitting;
  final VoidCallback onSelected;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: isSelected
          ? colorScheme.secondaryContainer.withValues(alpha: 0.35)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: store.isOpen
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    child: Icon(
                      store.isOpen
                          ? Icons.storefront
                          : Icons.storefront_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.name,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            _humanStatus(store.category),
                            if (store.address.isNotEmpty) store.address,
                          ].join(' | '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    avatar: const Icon(Icons.group_outlined, size: 18),
                    label: Text('$staffCount staff'),
                  ),
                  FilterChip(
                    label: const Text('Open'),
                    avatar: const Icon(Icons.storefront),
                    selected: store.isOpen,
                    onSelected: isSubmitting ? null : onOpenChanged,
                  ),
                  FilterChip(
                    label: const Text('Active'),
                    avatar: const Icon(Icons.verified_outlined),
                    selected: store.isActive,
                    onSelected: isSubmitting ? null : onActiveChanged,
                  ),
                  if (isSelected)
                    const Chip(
                      avatar: Icon(Icons.check_circle_outline, size: 18),
                      label: Text('Selected'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminOrderRevenueBreakdown extends StatelessWidget {
  const _AdminOrderRevenueBreakdown({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(label: Text('Items ${_formatNaira(order.itemsSubtotal)}')),
        if (order.discountAmount > 0)
          Chip(label: Text('Discount ${_formatNaira(order.discountAmount)}')),
        Chip(label: Text('Delivery ${_formatNaira(order.deliveryFee)}')),
        Chip(label: Text('Service ${_formatNaira(order.serviceFee)}')),
        Chip(label: Text('Store ${_formatNaira(order.storePayoutAmount)}')),
        Chip(label: Text('Rider ${_formatNaira(order.riderPayoutAmount)}')),
        Chip(label: Text('Platform ${_formatNaira(order.platformFeeAmount)}')),
      ],
    );
  }
}

class _AdminProfileContactDialog extends StatefulWidget {
  const _AdminProfileContactDialog({
    required this.repository,
    required this.profile,
  });

  final PlatformRepository repository;
  final UserProfile profile;

  @override
  State<_AdminProfileContactDialog> createState() =>
      _AdminProfileContactDialogState();
}

class _AdminProfileContactDialogState
    extends State<_AdminProfileContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.fullName);
    _phoneController = TextEditingController(text: widget.profile.phone);
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
      await widget.repository.updateProfileContact(
        userId: widget.profile.id,
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Profile contact updated')),
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
      title: Text('Edit ${widget.profile.displayName}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    return 'Enter a full name';
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
              const SizedBox(height: 8),
              Text(
                'User ID: ${widget.profile.id}',
                style: Theme.of(context).textTheme.bodySmall,
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: theme.colorScheme.outline,
                ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.headlineMedium,
            ),
          ),
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              child: content,
            ),
    );
  }
}

int _pageCount(int totalItems) {
  if (totalItems <= 0) {
    return 1;
  }
  return ((totalItems - 1) ~/ _adminListPageSize) + 1;
}

int _coerceListPage(int page, int totalItems) {
  final lastPage = _pageCount(totalItems) - 1;
  if (page < 0) {
    return 0;
  }
  if (page > lastPage) {
    return lastPage;
  }
  return page;
}

class _PagedListControls extends StatelessWidget {
  const _PagedListControls({
    required this.page,
    required this.totalItems,
    required this.onPageChanged,
  });

  final int page;
  final int totalItems;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final pageCount = _pageCount(totalItems);
    final start = totalItems == 0 ? 0 : (page * _adminListPageSize) + 1;
    final end = totalItems == 0
        ? 0
        : (start + _adminListPageSize - 1).clamp(0, totalItems).toInt();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Chip(
          avatar: const Icon(Icons.view_list_outlined, size: 18),
          label: Text('Showing $start-$end of $totalItems'),
        ),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment<int>(
              value: page - 1,
              enabled: page > 0,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Prev'),
            ),
            ButtonSegment<int>(
              value: page,
              enabled: false,
              label: Text('Page ${page + 1} of $pageCount'),
            ),
            ButtonSegment<int>(
              value: page + 1,
              enabled: page < pageCount - 1,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next'),
            ),
          ],
          selected: {page},
          onSelectionChanged: (selection) {
            final next = selection.first;
            if (next != page) {
              onPageChanged(next);
            }
          },
        ),
      ],
    );
  }
}

String? _requiredText(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }
  return null;
}

String? _emailText(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Required';
  }
  if (!trimmed.contains('@') || !trimmed.contains('.')) {
    return 'Enter a valid email';
  }
  return null;
}

String? _passwordText(String? value) {
  if ((value ?? '').length < 6) {
    return 'Use at least 6 characters';
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

String? _nonNegativeNumber(String? value) {
  final number = double.tryParse(value?.trim() ?? '');
  if (number == null || number < 0) {
    return 'Enter zero or more';
  }
  return null;
}

String? _wholeNumber(String? value) {
  final number = int.tryParse(value?.trim() ?? '');
  if (number == null || number < 0) {
    return 'Enter a whole number';
  }
  return null;
}

List<OrderSummary> _ordersForProfile(
  UserProfile profile,
  List<OrderSummary> orders,
  List<StoreMember> members,
) {
  if (profile.role == 'customer') {
    return orders.where((order) => order.customerId == profile.id).toList();
  }
  if (profile.role == 'rider') {
    return orders.where((order) => order.riderId == profile.id).toList();
  }
  if (profile.role == 'store_admin') {
    final storeIds = members
        .where((member) => member.userId == profile.id)
        .map((member) => member.storeId)
        .toSet();
    return orders.where((order) => storeIds.contains(order.storeId)).toList();
  }
  if (profile.role == 'rider_admin') {
    return orders.where((order) => order.riderId != null).toList();
  }
  if (_isSuperAdminRole(profile.role)) {
    return orders;
  }
  return const <OrderSummary>[];
}

double _revenueForProfile(UserProfile profile, OrderSummary order) {
  if (profile.role == 'rider') {
    return order.riderPayoutAmount > 0
        ? order.riderPayoutAmount
        : order.deliveryFee;
  }
  if (profile.role == 'store_admin') {
    return order.storePayoutAmount > 0
        ? order.storePayoutAmount
        : order.itemsSubtotal;
  }
  if (profile.role == 'rider_admin') {
    return order.riderPayoutAmount > 0
        ? order.riderPayoutAmount
        : order.deliveryFee;
  }
  if (_isSuperAdminRole(profile.role)) {
    return order.totalAmount;
  }
  return order.totalAmount;
}

UserProfile? _findProfileById(List<UserProfile> profiles, String? id) {
  if (id == null) {
    return null;
  }

  for (final profile in profiles) {
    if (profile.id == id) {
      return profile;
    }
  }

  return null;
}

StoreSummary? _findStoreById(List<StoreSummary> stores, String? id) {
  if (id == null) {
    return null;
  }

  for (final store in stores) {
    if (store.id == id) {
      return store;
    }
  }

  return null;
}

List<StoreMember> _membersForStore(
  List<StoreMember> members,
  String storeId,
) {
  return members.where((member) => member.storeId == storeId).toList();
}

List<UserProfile> _filterProfiles(List<UserProfile> profiles, String query) {
  final normalized = query.trim().toLowerCase();
  final filtered = normalized.isEmpty
      ? profiles
      : profiles.where((profile) {
          final phone = profile.phone?.toLowerCase() ?? '';
          return profile.displayName.toLowerCase().contains(normalized) ||
              profile.fullName.toLowerCase().contains(normalized) ||
              profile.role.toLowerCase().contains(normalized) ||
              phone.contains(normalized);
        }).toList();
  return filtered..sort((a, b) => a.displayName.compareTo(b.displayName));
}

List<StoreSummary> _filterStores(
  List<StoreSummary> stores,
  List<StoreMember> members,
  List<UserProfile> profiles,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  final filtered = normalized.isEmpty
      ? stores
      : stores.where((store) {
          final storeMembers = _membersForStore(members, store.id);
          final memberNames = storeMembers
              .map((member) => _findProfileById(profiles, member.userId))
              .whereType<UserProfile>()
              .map((profile) => profile.displayName.toLowerCase())
              .join(' ');
          return store.name.toLowerCase().contains(normalized) ||
              store.category.toLowerCase().contains(normalized) ||
              store.address.toLowerCase().contains(normalized) ||
              memberNames.contains(normalized);
        }).toList();
  return filtered..sort((a, b) => a.name.compareTo(b.name));
}

String _initialsFor(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) {
    return '?';
  }
  return parts.map((part) => part.substring(0, 1).toUpperCase()).join();
}

List<String> _catalogCategories(List<CatalogItem> items) {
  final categories = items
      .map((item) => item.category.trim().isEmpty ? 'general' : item.category)
      .toSet()
      .toList()
    ..sort();
  return categories;
}

bool _matchesCatalogSearch(CatalogItem item, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }

  return item.name.toLowerCase().contains(normalized) ||
      item.description.toLowerCase().contains(normalized) ||
      item.storeName.toLowerCase().contains(normalized) ||
      item.category.toLowerCase().contains(normalized);
}

bool _matchesOrderSearch(OrderSummary order, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }

  return order.id.toLowerCase().contains(normalized) ||
      order.storeName.toLowerCase().contains(normalized) ||
      order.status.toLowerCase().contains(normalized) ||
      order.paymentStatus.toLowerCase().contains(normalized) ||
      order.deliveryAddress.toLowerCase().contains(normalized);
}

class _DailyTotal {
  const _DailyTotal({required this.label, required this.value});

  final String label;
  final double value;
}

List<_DailyTotal> _lastSevenDayTotals(
  List<OrderSummary> orders,
  double Function(OrderSummary order) valueForOrder,
) {
  final now = DateTime.now();
  final firstDay =
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
  final totals = <DateTime, double>{
    for (var index = 0; index < 7; index += 1)
      firstDay.add(Duration(days: index)): 0,
  };

  for (final order in orders) {
    final local = order.createdAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (totals.containsKey(day)) {
      totals[day] = totals[day]! + valueForOrder(order);
    }
  }

  return [
    for (final entry in totals.entries)
      _DailyTotal(
        label: '${entry.key.day}/${entry.key.month}',
        value: entry.value,
      ),
  ];
}

String _compactRevenue(double value) {
  if (value >= 1000000) {
    return 'NGN ${(value / 1000000).toStringAsFixed(1)}m';
  }
  if (value >= 1000) {
    return 'NGN ${(value / 1000).toStringAsFixed(0)}k';
  }
  return _formatNaira(value);
}

IconData _activityIcon(String entityType) {
  switch (entityType) {
    case 'order':
      return Icons.receipt_long_outlined;
    case 'product':
    case 'inventory':
      return Icons.inventory_2_outlined;
    case 'store_hours':
      return Icons.schedule_outlined;
    default:
      return Icons.history;
  }
}

bool _isSuperAdminRole(String role) {
  return role == 'admin' || role == 'super_admin';
}

bool _isRiderAdminRole(String role) {
  return role == 'rider_admin';
}

bool _isStoreAdminRole(String role) {
  return role == 'store_admin';
}

String _adminDashboardTitle(String role) {
  if (_isSuperAdminRole(role)) {
    return 'Luumoh Staff Operations';
  }
  if (_isRiderAdminRole(role)) {
    return 'Rider Admin';
  }
  if (_isStoreAdminRole(role)) {
    return 'Store Manager';
  }
  return 'Luumoh Operations';
}

String _notificationAudienceForAdminRole(String? role) {
  if (role == null || _isSuperAdminRole(role)) {
    return 'admin';
  }
  if (_isRiderAdminRole(role)) {
    return 'rider';
  }
  if (_isStoreAdminRole(role)) {
    return 'store';
  }
  return 'admin';
}

String _humanStatus(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _weekdayName(int dayOfWeek) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  if (dayOfWeek < 0 || dayOfWeek >= names.length) {
    return 'Day ${dayOfWeek + 1}';
  }
  return names[dayOfWeek];
}

String _timeText(String? value, {String fallback = '09:00'}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return fallback;
  }
  return trimmed.length >= 5 ? trimmed.substring(0, 5) : trimmed;
}

String _shortId(String value) {
  return value.length <= 8 ? value : value.substring(0, 8);
}

String _formatNaira(double value) {
  return 'NGN ${value.toStringAsFixed(0)}';
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

IconData _paymentStatusIcon(String status) {
  switch (status) {
    case 'paid':
      return Icons.verified_outlined;
    case 'failed':
      return Icons.error_outline;
    case 'expired':
      return Icons.timer_off_outlined;
    case 'refunded':
      return Icons.replay_outlined;
    case 'pending':
    default:
      return Icons.pending_actions_outlined;
  }
}

IconData _orderStatusIcon(String status) {
  switch (status) {
    case 'delivered':
      return Icons.verified_outlined;
    case 'cancelled':
      return Icons.cancel_outlined;
    case 'out_for_delivery':
      return Icons.delivery_dining_outlined;
    case 'ready_for_pickup':
      return Icons.shopping_bag_outlined;
    case 'preparing':
      return Icons.restaurant_menu_outlined;
    case 'accepted':
      return Icons.task_alt_outlined;
    default:
      return Icons.receipt_long_outlined;
  }
}

Color _statusColor(String status, ColorScheme colorScheme) {
  switch (status) {
    case 'delivered':
      return Colors.green;
    case 'cancelled':
      return colorScheme.error;
    case 'out_for_delivery':
      return Colors.indigo;
    case 'ready_for_pickup':
      return Colors.teal;
    case 'preparing':
      return Colors.orange;
    case 'accepted':
      return Colors.blue;
    default:
      return colorScheme.primary;
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
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

StoreSummary? _storeById(List<StoreSummary> stores, String id) {
  for (final store in stores) {
    if (store.id == id) {
      return store;
    }
  }
  return stores.isEmpty ? null : stores.first;
}

bool _isActiveStoreOrder(OrderSummary order) {
  if (order.paymentStatus != 'paid') {
    return false;
  }
  return order.status != 'delivered' && order.status != 'cancelled';
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
