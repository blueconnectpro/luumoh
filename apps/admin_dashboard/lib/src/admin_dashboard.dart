part of '../main.dart';

class _AdminOverviewPage extends StatelessWidget {
  const _AdminOverviewPage({
    required this.stores,
    required this.catalog,
    required this.profiles,
    required this.members,
    required this.orders,
    required this.paidRevenue,
    required this.platformFees,
    required this.storePayouts,
    required this.riderPayouts,
    required this.onOpenSection,
  });

  final List<StoreSummary> stores;
  final List<CatalogItem> catalog;
  final List<UserProfile> profiles;
  final List<StoreMember> members;
  final List<OrderSummary> orders;
  final double paidRevenue;
  final double platformFees;
  final double storePayouts;
  final double riderPayouts;
  final ValueChanged<int> onOpenSection;

  @override
  Widget build(BuildContext context) {
    final activeOrders = orders.where(_isActiveStoreOrder).length;
    final pendingPayments =
        orders.where((order) => order.paymentStatus != 'paid').length;
    final lowStock = catalog
        .where((item) => item.quantityAvailable <= item.reorderLevel)
        .length;

    return _AdminSectionPage(
      title: 'Overview',
      description:
          'A real-time command center for platform health, revenue, operations, and risk signals.',
      children: [
        _AdminMetricGrid(
          children: [
            _MetricCard(
              label: 'Stores',
              value: stores.length.toString(),
              icon: Icons.storefront_outlined,
              onTap: () => onOpenSection(4),
            ),
            _MetricCard(
              label: 'Open stores',
              value: stores.where((store) => store.isOpen).length.toString(),
              icon: Icons.door_front_door_outlined,
              onTap: () => onOpenSection(4),
            ),
            _MetricCard(
              label: 'Products',
              value: catalog.length.toString(),
              icon: Icons.inventory_2_outlined,
              onTap: () => onOpenSection(4),
            ),
            _MetricCard(
              label: 'Users',
              value: profiles.length.toString(),
              icon: Icons.groups_outlined,
              onTap: () => onOpenSection(5),
            ),
            _MetricCard(
              label: 'Members',
              value: members.length.toString(),
              icon: Icons.badge_outlined,
              onTap: () => onOpenSection(6),
            ),
            _MetricCard(
              label: 'Orders',
              value: orders.length.toString(),
              icon: Icons.receipt_long_outlined,
              onTap: () => onOpenSection(1),
            ),
            _MetricCard(
              label: 'Active orders',
              value: activeOrders.toString(),
              icon: Icons.local_shipping_outlined,
              onTap: () => onOpenSection(1),
            ),
            _MetricCard(
              label: 'Pending payments',
              value: pendingPayments.toString(),
              icon: Icons.pending_actions_outlined,
              onTap: () => onOpenSection(2),
            ),
            _MetricCard(
              label: 'Low stock',
              value: lowStock.toString(),
              icon: Icons.warning_amber_outlined,
              onTap: () => onOpenSection(4),
            ),
            _MetricCard(
              label: 'Paid gross merchandise value',
              value: _formatNaira(paidRevenue),
              icon: Icons.trending_up,
              onTap: () => onOpenSection(2),
            ),
            _MetricCard(
              label: 'Platform fees',
              value: _formatNaira(platformFees),
              icon: Icons.account_balance_wallet_outlined,
              onTap: () => onOpenSection(2),
            ),
            _MetricCard(
              label: 'Store split amount',
              value: _formatNaira(storePayouts),
              icon: Icons.store_mall_directory_outlined,
              onTap: () => onOpenSection(3),
            ),
            _MetricCard(
              label: 'Rider split amount',
              value: _formatNaira(riderPayouts),
              icon: Icons.delivery_dining,
              onTap: () => onOpenSection(3),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AdminResponsivePair(
          first: _AdminRevenueChart(
            title: 'Gross merchandise value trend',
            orders: orders,
            valueForOrder: (order) =>
                order.paymentStatus == 'paid' ? order.totalAmount : 0,
          ),
          second: _OrderStatusSummaryPanel(orders: orders),
        ),
        const SizedBox(height: 16),
        _AdminOperationsAlertsPanel(orders: orders, catalog: catalog),
        const SizedBox(height: 16),
        _RecentAdminOrdersPanel(orders: orders),
      ],
    );
  }
}

class _AdminPaymentsPage extends StatelessWidget {
  const _AdminPaymentsPage({
    required this.repository,
    required this.orders,
    required this.paidRevenue,
    required this.platformFees,
  });

  final PlatformRepository repository;
  final List<OrderSummary> orders;
  final double paidRevenue;
  final double platformFees;

  @override
  Widget build(BuildContext context) {
    final failedPayments =
        orders.where((order) => order.paymentStatus == 'failed').length;
    final pendingPayments =
        orders.where((order) => order.paymentStatus == 'pending').length;

    return _AdminSectionPage(
      title: 'Platform revenue',
      description:
          'Monitor payment status, Monnify webhook delivery, service fees, and platform revenue configuration.',
      children: [
        _AdminMetricGrid(
          children: [
            _MetricCard(
              label: 'Paid gross merchandise value',
              value: _formatNaira(paidRevenue),
              icon: Icons.trending_up,
            ),
            _MetricCard(
              label: 'Platform fees',
              value: _formatNaira(platformFees),
            ),
            _MetricCard(
              label: 'Pending payments',
              value: pendingPayments.toString(),
            ),
            _MetricCard(
              label: 'Failed payments',
              value: failedPayments.toString(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AdminResponsivePair(
          first: _AdminRevenueChart(
            title: 'Paid gross merchandise value',
            orders: orders,
            valueForOrder: (order) =>
                order.paymentStatus == 'paid' ? order.totalAmount : 0,
          ),
          second: _OrderStatusSummaryPanel(orders: orders),
        ),
        const SizedBox(height: 16),
        _AdminPaymentsPanel(repository: repository),
        const SizedBox(height: 16),
        _AdminRevenueSettingsPanel(repository: repository),
      ],
    );
  }
}

class _AdminStoresInventoryPage extends StatelessWidget {
  const _AdminStoresInventoryPage({
    required this.repository,
    required this.stores,
    required this.catalog,
    required this.members,
    required this.selectedStoreId,
    required this.isCreatingStore,
    required this.isCreatingProduct,
    required this.isUploadingProductImage,
    required this.isUpdatingStore,
    required this.isResolvingStoreAddress,
    required this.storeFormKey,
    required this.productFormKey,
    required this.storeNameController,
    required this.storeCategoryController,
    required this.storeAddressController,
    required this.productNameController,
    required this.productDescriptionController,
    required this.productCategoryController,
    required this.productPriceController,
    required this.productStockController,
    required this.productSkuController,
    required this.productImageUrlController,
    required this.productReorderController,
    required this.onCreateStore,
    required this.onCreateProduct,
    required this.onUploadProductImage,
    required this.onUseCurrentLocation,
    required this.onFindAddress,
    required this.onAddressChanged,
    required this.onStoreChanged,
    required this.onStoreSelected,
    required this.onStoreOpenChanged,
    required this.onStoreActiveChanged,
  });

  final PlatformRepository repository;
  final List<StoreSummary> stores;
  final List<CatalogItem> catalog;
  final List<StoreMember> members;
  final String? selectedStoreId;
  final bool isCreatingStore;
  final bool isCreatingProduct;
  final bool isUploadingProductImage;
  final bool isUpdatingStore;
  final bool isResolvingStoreAddress;
  final GlobalKey<FormState> storeFormKey;
  final GlobalKey<FormState> productFormKey;
  final TextEditingController storeNameController;
  final TextEditingController storeCategoryController;
  final TextEditingController storeAddressController;
  final TextEditingController productNameController;
  final TextEditingController productDescriptionController;
  final TextEditingController productCategoryController;
  final TextEditingController productPriceController;
  final TextEditingController productStockController;
  final TextEditingController productSkuController;
  final TextEditingController productImageUrlController;
  final TextEditingController productReorderController;
  final VoidCallback onCreateStore;
  final VoidCallback onCreateProduct;
  final Future<void> Function() onUploadProductImage;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onFindAddress;
  final VoidCallback onAddressChanged;
  final ValueChanged<String?> onStoreChanged;
  final ValueChanged<String> onStoreSelected;
  final void Function(StoreSummary store, bool value) onStoreOpenChanged;
  final void Function(StoreSummary store, bool value) onStoreActiveChanged;

  @override
  Widget build(BuildContext context) {
    final openStores = stores.where((store) => store.isOpen).length;
    final unavailableProducts =
        catalog.where((item) => !item.isAvailable).length;
    final lowStock = catalog
        .where((item) => item.quantityAvailable <= item.reorderLevel)
        .length;

    return _AdminSectionPage(
      title: 'Stores and restaurants',
      description:
          'Create stores, manage product inventory, review availability, and keep customer catalog data aligned.',
      children: [
        _AdminMetricGrid(
          children: [
            _MetricCard(label: 'Stores', value: stores.length.toString()),
            _MetricCard(label: 'Open now', value: openStores.toString()),
            _MetricCard(label: 'Products', value: catalog.length.toString()),
            _MetricCard(
              label: 'Unavailable',
              value: unavailableProducts.toString(),
            ),
            _MetricCard(label: 'Low stock', value: lowStock.toString()),
          ],
        ),
        const SizedBox(height: 16),
        _AdminResponsivePair(
          first: _CreateStorePanel(
            formKey: storeFormKey,
            nameController: storeNameController,
            categoryController: storeCategoryController,
            addressController: storeAddressController,
            isSubmitting: isCreatingStore,
            isResolvingAddress: isResolvingStoreAddress,
            onUseCurrentLocation: onUseCurrentLocation,
            onFindAddress: onFindAddress,
            onAddressChanged: onAddressChanged,
            onSubmit: onCreateStore,
          ),
          second: _CreateProductPanel(
            formKey: productFormKey,
            stores: stores,
            selectedStoreId: selectedStoreId,
            onStoreChanged: onStoreChanged,
            nameController: productNameController,
            descriptionController: productDescriptionController,
            categoryController: productCategoryController,
            priceController: productPriceController,
            stockController: productStockController,
            skuController: productSkuController,
            imageUrlController: productImageUrlController,
            isUploadingImage: isUploadingProductImage,
            reorderController: productReorderController,
            isSubmitting: isCreatingProduct,
            onUploadImage: onUploadProductImage,
            onSubmit: onCreateProduct,
          ),
        ),
        const SizedBox(height: 16),
        _AdminStoresListPanel(
          stores: stores,
          members: members,
          selectedStoreId: selectedStoreId,
          isUpdatingStore: isUpdatingStore,
          onStoreSelected: onStoreSelected,
          onStoreOpenChanged: onStoreOpenChanged,
          onStoreActiveChanged: onStoreActiveChanged,
        ),
        const SizedBox(height: 16),
        _AdminPromosPanel(repository: repository, stores: stores),
        const SizedBox(height: 16),
        _AdminCatalogPanel(catalog: catalog),
      ],
    );
  }
}

class _AdminUsersAccessPage extends StatelessWidget {
  const _AdminUsersAccessPage({
    required this.stores,
    required this.profiles,
    required this.members,
    required this.userFormKey,
    required this.newUserRole,
    required this.newUserStoreId,
    required this.canManageInventory,
    required this.canManageOrders,
    required this.isCreatingUser,
    required this.userEmailController,
    required this.userPasswordController,
    required this.userFullNameController,
    required this.userPhoneController,
    required this.onCreateUser,
    required this.onNewUserRoleChanged,
    required this.onNewUserStoreChanged,
    required this.onInventoryPermissionChanged,
    required this.onOrdersPermissionChanged,
  });

  final List<StoreSummary> stores;
  final List<UserProfile> profiles;
  final List<StoreMember> members;
  final GlobalKey<FormState> userFormKey;
  final String newUserRole;
  final String? newUserStoreId;
  final bool canManageInventory;
  final bool canManageOrders;
  final bool isCreatingUser;
  final TextEditingController userEmailController;
  final TextEditingController userPasswordController;
  final TextEditingController userFullNameController;
  final TextEditingController userPhoneController;
  final VoidCallback onCreateUser;
  final ValueChanged<String> onNewUserRoleChanged;
  final ValueChanged<String?> onNewUserStoreChanged;
  final ValueChanged<bool> onInventoryPermissionChanged;
  final ValueChanged<bool> onOrdersPermissionChanged;

  @override
  Widget build(BuildContext context) {
    final customers = profiles.where((profile) => profile.role == 'customer');
    final riders = profiles.where((profile) => profile.role == 'rider');
    final riderAdmins =
        profiles.where((profile) => profile.role == 'rider_admin');
    final staffAdmins = profiles.where(
      (profile) => profile.role == 'admin' || profile.role == 'super_admin',
    );
    final storeStaff =
        profiles.where((profile) => profile.role == 'store_admin');

    return _AdminSectionPage(
      title: 'Users',
      description:
          'Create customer, rider, store admin, rider admin, and Luumoh staff accounts.',
      children: [
        _AdminMetricGrid(
          children: [
            _MetricCard(label: 'Customers', value: customers.length.toString()),
            _MetricCard(label: 'Riders', value: riders.length.toString()),
            _MetricCard(
              label: 'Rider admins',
              value: riderAdmins.length.toString(),
            ),
            _MetricCard(
              label: 'Store staff',
              value: storeStaff.length.toString(),
            ),
            _MetricCard(
              label: 'Luumoh staff',
              value: staffAdmins.length.toString(),
            ),
            _MetricCard(label: 'Memberships', value: members.length.toString()),
          ],
        ),
        const SizedBox(height: 16),
        _CreateOperationalUserPanel(
          formKey: userFormKey,
          stores: stores,
          selectedRole: newUserRole,
          selectedStoreId: newUserStoreId,
          emailController: userEmailController,
          passwordController: userPasswordController,
          fullNameController: userFullNameController,
          phoneController: userPhoneController,
          canManageInventory: canManageInventory,
          canManageOrders: canManageOrders,
          isSubmitting: isCreatingUser,
          onRoleChanged: onNewUserRoleChanged,
          onStoreChanged: onNewUserStoreChanged,
          onInventoryPermissionChanged: onInventoryPermissionChanged,
          onOrdersPermissionChanged: onOrdersPermissionChanged,
          onSubmit: onCreateUser,
        ),
      ],
    );
  }
}

enum _AccessDirectoryType {
  customers,
  stores,
  riders,
  storeAdmins,
  riderAdmins,
}

class _AdminAccessManagementPage extends StatefulWidget {
  const _AdminAccessManagementPage({
    required this.stores,
    required this.profiles,
    required this.orders,
    required this.members,
    required this.selectedUserId,
    required this.selectedRole,
    required this.selectedStoreId,
    required this.canManageInventory,
    required this.canManageOrders,
    required this.isUpdatingAccess,
    required this.onUserChanged,
    required this.onRoleChanged,
    required this.onStoreChanged,
    required this.onInventoryPermissionChanged,
    required this.onOrdersPermissionChanged,
    required this.onSetRole,
    required this.onEditProfile,
    required this.onAddStoreMember,
    required this.onUpdateMemberInventory,
    required this.onUpdateMemberOrders,
    required this.onRemoveMember,
    required this.onRemoveRider,
    required this.onDeleteUser,
  });

  final List<StoreSummary> stores;
  final List<UserProfile> profiles;
  final List<OrderSummary> orders;
  final List<StoreMember> members;
  final String? selectedUserId;
  final String selectedRole;
  final String? selectedStoreId;
  final bool canManageInventory;
  final bool canManageOrders;
  final bool isUpdatingAccess;
  final ValueChanged<UserProfile?> onUserChanged;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String?> onStoreChanged;
  final ValueChanged<bool> onInventoryPermissionChanged;
  final ValueChanged<bool> onOrdersPermissionChanged;
  final VoidCallback onSetRole;
  final ValueChanged<UserProfile> onEditProfile;
  final VoidCallback onAddStoreMember;
  final void Function(StoreMember member, bool value) onUpdateMemberInventory;
  final void Function(StoreMember member, bool value) onUpdateMemberOrders;
  final ValueChanged<StoreMember> onRemoveMember;
  final ValueChanged<UserProfile> onRemoveRider;
  final Future<void> Function(UserProfile profile) onDeleteUser;

  @override
  State<_AdminAccessManagementPage> createState() =>
      _AdminAccessManagementPageState();
}

class _AdminRidersPage extends StatelessWidget {
  const _AdminRidersPage({
    required this.repository,
    required this.profiles,
    required this.orders,
    required this.onRemoveRider,
  });

  final PlatformRepository repository;
  final List<UserProfile> profiles;
  final List<OrderSummary> orders;
  final ValueChanged<UserProfile> onRemoveRider;

  @override
  Widget build(BuildContext context) {
    final riders = profiles.where((profile) => profile.role == 'rider');
    final assignedOrders =
        orders.where((order) => order.riderId != null).length;

    return _AdminSectionPage(
      title: 'Riders',
      description:
          'Monitor rider availability and keep delivery assignments moving.',
      children: [
        _AdminMetricGrid(
          children: [
            _MetricCard(label: 'Riders', value: riders.length.toString()),
            _MetricCard(
              label: 'Assigned orders',
              value: assignedOrders.toString(),
            ),
            _MetricCard(
              label: 'Active deliveries',
              value: orders
                  .where((order) =>
                      order.riderId != null && _isActiveStoreOrder(order))
                  .length
                  .toString(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AdminRidersPanel(
          repository: repository,
          profiles: profiles,
          onRemoveRider: onRemoveRider,
        ),
      ],
    );
  }
}

class _AdminAccessManagementPageState
    extends State<_AdminAccessManagementPage> {
  final _searchController = TextEditingController();
  _AccessDirectoryType? _selectedType;
  var _page = 0;
  UserProfile? _openedProfile;
  StoreSummary? _openedStore;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectType(_AccessDirectoryType type) {
    setState(() {
      _selectedType = type;
      _page = 0;
      _openedProfile = null;
      _openedStore = null;
    });
  }

  void _openProfile(UserProfile profile) {
    widget.onUserChanged(profile);
    widget.onRoleChanged(profile.role);
    setState(() {
      _openedProfile = profile;
      _openedStore = null;
    });
  }

  void _openStore(StoreSummary store) {
    widget.onStoreChanged(store.id);
    setState(() {
      _openedStore = store;
      _openedProfile = null;
    });
  }

  void _closeDetails() {
    setState(() {
      _openedProfile = null;
      _openedStore = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final customers = _filterProfiles(
      widget.profiles.where((profile) => profile.role == 'customer').toList(),
      query,
    );
    final riders = _filterProfiles(
      widget.profiles.where((profile) => profile.role == 'rider').toList(),
      query,
    );
    final storeAdmins = _filterProfiles(
      widget.profiles
          .where((profile) => profile.role == 'store_admin')
          .toList(),
      query,
    );
    final riderAdmins = _filterProfiles(
      widget.profiles
          .where((profile) => profile.role == 'rider_admin')
          .toList(),
      query,
    );
    final stores = _filterStores(
      widget.stores,
      widget.members,
      widget.profiles,
      query,
    );
    final selectedType = _selectedType;
    final visibleCount = selectedType == null
        ? 0
        : switch (selectedType) {
            _AccessDirectoryType.customers => customers.length,
            _AccessDirectoryType.stores => stores.length,
            _AccessDirectoryType.riders => riders.length,
            _AccessDirectoryType.storeAdmins => storeAdmins.length,
            _AccessDirectoryType.riderAdmins => riderAdmins.length,
          };
    final safePage = _coerceListPage(_page, visibleCount);
    if (safePage != _page) {
      _page = safePage;
    }

    return _AdminSectionPage(
      title: 'Access',
      description:
          'Open a directory, review the profile, and make access changes from the user or store detail page.',
      children: [
        _AdminMetricGrid(
          children: [
            _MetricCard(
              label: 'Customers',
              value: customers.length.toString(),
              icon: Icons.person_outline,
              onTap: () => _selectType(_AccessDirectoryType.customers),
            ),
            _MetricCard(
              label: 'Stores',
              value: stores.length.toString(),
              icon: Icons.storefront_outlined,
              onTap: () => _selectType(_AccessDirectoryType.stores),
            ),
            _MetricCard(
              label: 'Riders',
              value: riders.length.toString(),
              icon: Icons.delivery_dining,
              onTap: () => _selectType(_AccessDirectoryType.riders),
            ),
            _MetricCard(
              label: 'Store admins',
              value: storeAdmins.length.toString(),
              icon: Icons.store_mall_directory_outlined,
              onTap: () => _selectType(_AccessDirectoryType.storeAdmins),
            ),
            _MetricCard(
              label: 'Rider admins',
              value: riderAdmins.length.toString(),
              icon: Icons.support_agent_outlined,
              onTap: () => _selectType(_AccessDirectoryType.riderAdmins),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_openedProfile != null)
          _AccessProfileDetailPage(
            profile: _openedProfile!,
            profiles: widget.profiles,
            stores: widget.stores,
            orders: _ordersForProfile(
              _openedProfile!,
              widget.orders,
              widget.members,
            ),
            members: widget.members,
            selectedUserId: widget.selectedUserId,
            selectedRole: widget.selectedRole,
            selectedStoreId: widget.selectedStoreId,
            canManageInventory: widget.canManageInventory,
            canManageOrders: widget.canManageOrders,
            isUpdatingAccess: widget.isUpdatingAccess,
            onBack: _closeDetails,
            onUserChanged: widget.onUserChanged,
            onRoleChanged: widget.onRoleChanged,
            onStoreChanged: widget.onStoreChanged,
            onInventoryPermissionChanged: widget.onInventoryPermissionChanged,
            onOrdersPermissionChanged: widget.onOrdersPermissionChanged,
            onSetRole: widget.onSetRole,
            onEditProfile: widget.onEditProfile,
            onAddStoreMember: widget.onAddStoreMember,
            onUpdateMemberInventory: widget.onUpdateMemberInventory,
            onUpdateMemberOrders: widget.onUpdateMemberOrders,
            onRemoveMember: widget.onRemoveMember,
            onRemoveRider: widget.onRemoveRider,
            onDeleteUser: (profile) async {
              await widget.onDeleteUser(profile);
              if (mounted) {
                _closeDetails();
              }
            },
          )
        else if (_openedStore != null)
          _AccessStoreDetailPage(
            store: _openedStore!,
            stores: widget.stores,
            profiles: widget.profiles,
            orders: widget.orders
                .where((order) => order.storeId == _openedStore!.id)
                .toList(),
            members: _membersForStore(widget.members, _openedStore!.id),
            isUpdatingAccess: widget.isUpdatingAccess,
            onBack: _closeDetails,
            onUpdateMemberInventory: widget.onUpdateMemberInventory,
            onUpdateMemberOrders: widget.onUpdateMemberOrders,
            onRemoveMember: widget.onRemoveMember,
          )
        else if (selectedType != null) ...[
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() => _page = 0),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _page = 0;
                      }),
                      icon: const Icon(Icons.close),
                    ),
              labelText: 'Search names, phone numbers, roles, or stores',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _AccessDirectoryList(
            type: selectedType,
            page: safePage,
            customers: customers,
            stores: stores,
            riders: riders,
            storeAdmins: storeAdmins,
            riderAdmins: riderAdmins,
            members: widget.members,
            profiles: widget.profiles,
            onPageChanged: (page) => setState(() => _page = page),
            onProfileSelected: _openProfile,
            onStoreSelected: _openStore,
          ),
        ],
      ],
    );
  }
}

class _AccessDirectoryList extends StatelessWidget {
  const _AccessDirectoryList({
    required this.type,
    required this.page,
    required this.customers,
    required this.stores,
    required this.riders,
    required this.storeAdmins,
    required this.riderAdmins,
    required this.members,
    required this.profiles,
    required this.onPageChanged,
    required this.onProfileSelected,
    required this.onStoreSelected,
  });

  final _AccessDirectoryType type;
  final int page;
  final List<UserProfile> customers;
  final List<StoreSummary> stores;
  final List<UserProfile> riders;
  final List<UserProfile> storeAdmins;
  final List<UserProfile> riderAdmins;
  final List<StoreMember> members;
  final List<UserProfile> profiles;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<UserProfile> onProfileSelected;
  final ValueChanged<StoreSummary> onStoreSelected;

  @override
  Widget build(BuildContext context) {
    final title = switch (type) {
      _AccessDirectoryType.customers => 'Customers',
      _AccessDirectoryType.stores => 'Stores',
      _AccessDirectoryType.riders => 'Riders',
      _AccessDirectoryType.storeAdmins => 'Store admins',
      _AccessDirectoryType.riderAdmins => 'Rider admins',
    };
    final icon = switch (type) {
      _AccessDirectoryType.customers => Icons.person_outline,
      _AccessDirectoryType.stores => Icons.storefront_outlined,
      _AccessDirectoryType.riders => Icons.delivery_dining,
      _AccessDirectoryType.storeAdmins => Icons.store_mall_directory_outlined,
      _AccessDirectoryType.riderAdmins => Icons.support_agent_outlined,
    };
    final totalItems = switch (type) {
      _AccessDirectoryType.customers => customers.length,
      _AccessDirectoryType.stores => stores.length,
      _AccessDirectoryType.riders => riders.length,
      _AccessDirectoryType.storeAdmins => storeAdmins.length,
      _AccessDirectoryType.riderAdmins => riderAdmins.length,
    };
    final start = page * _adminListPageSize;
    final people = switch (type) {
      _AccessDirectoryType.customers =>
        customers.skip(start).take(_adminListPageSize).toList(),
      _AccessDirectoryType.riders =>
        riders.skip(start).take(_adminListPageSize).toList(),
      _AccessDirectoryType.storeAdmins =>
        storeAdmins.skip(start).take(_adminListPageSize).toList(),
      _AccessDirectoryType.riderAdmins =>
        riderAdmins.skip(start).take(_adminListPageSize).toList(),
      _AccessDirectoryType.stores => const <UserProfile>[],
    };
    final pagedStores = type == _AccessDirectoryType.stores
        ? stores.skip(start).take(_adminListPageSize).toList()
        : const <StoreSummary>[];

    return _AccessSectionShell(
      title: title,
      icon: icon,
      count: totalItems,
      child: totalItems == 0
          ? Text('No ${title.toLowerCase()} match this search.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PagedListControls(
                  page: page,
                  totalItems: totalItems,
                  onPageChanged: onPageChanged,
                ),
                const SizedBox(height: 10),
                if (type == _AccessDirectoryType.stores)
                  for (final store in pagedStores)
                    _AccessStoreRow(
                      store: store,
                      members: _membersForStore(members, store.id),
                      profiles: profiles,
                      onSelected: () => onStoreSelected(store),
                    )
                else
                  for (final profile in people)
                    _AccessPersonRow(
                      profile: profile,
                      onSelected: () => onProfileSelected(profile),
                    ),
                const SizedBox(height: 10),
                _PagedListControls(
                  page: page,
                  totalItems: totalItems,
                  onPageChanged: onPageChanged,
                ),
              ],
            ),
    );
  }
}

class _AccessSectionShell extends StatelessWidget {
  const _AccessSectionShell({
    required this.title,
    required this.icon,
    required this.count,
    required this.child,
  });

  final String title;
  final IconData icon;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text('$count')),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _AccessPersonRow extends StatelessWidget {
  const _AccessPersonRow({
    required this.profile,
    required this.onSelected,
  });

  final UserProfile profile;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final phone = profile.phone?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final details = Row(
                  children: [
                    CircleAvatar(
                        child: Text(_initialsFor(profile.displayName))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              _humanStatus(profile.role),
                              if (phone != null && phone.isNotEmpty) phone,
                            ].join(' | '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final action = OutlinedButton.icon(
                  onPressed: onSelected,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Open'),
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      details,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: 8),
                    action,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessStoreRow extends StatelessWidget {
  const _AccessStoreRow({
    required this.store,
    required this.members,
    required this.profiles,
    required this.onSelected,
  });

  final StoreSummary store;
  final List<StoreMember> members;
  final List<UserProfile> profiles;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final adminNames = members
        .map((member) => _findProfileById(profiles, member.userId))
        .whereType<UserProfile>()
        .map((profile) => profile.displayName)
        .take(3)
        .join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final details = Row(
                  children: [
                    CircleAvatar(
                      child: Icon(
                        store.isActive
                            ? Icons.storefront_outlined
                            : Icons.storefront,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            store.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              _humanStatus(store.category),
                              '${members.length} staff',
                              if (adminNames.isNotEmpty) adminNames,
                            ].join(' | '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final action = OutlinedButton.icon(
                  onPressed: onSelected,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Open'),
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      details,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: 8),
                    action,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessProfileDetailPage extends StatelessWidget {
  const _AccessProfileDetailPage({
    required this.profile,
    required this.profiles,
    required this.stores,
    required this.orders,
    required this.members,
    required this.selectedUserId,
    required this.selectedRole,
    required this.selectedStoreId,
    required this.canManageInventory,
    required this.canManageOrders,
    required this.isUpdatingAccess,
    required this.onBack,
    required this.onUserChanged,
    required this.onRoleChanged,
    required this.onStoreChanged,
    required this.onInventoryPermissionChanged,
    required this.onOrdersPermissionChanged,
    required this.onSetRole,
    required this.onEditProfile,
    required this.onAddStoreMember,
    required this.onUpdateMemberInventory,
    required this.onUpdateMemberOrders,
    required this.onRemoveMember,
    required this.onRemoveRider,
    required this.onDeleteUser,
  });

  final UserProfile profile;
  final List<UserProfile> profiles;
  final List<StoreSummary> stores;
  final List<OrderSummary> orders;
  final List<StoreMember> members;
  final String? selectedUserId;
  final String selectedRole;
  final String? selectedStoreId;
  final bool canManageInventory;
  final bool canManageOrders;
  final bool isUpdatingAccess;
  final VoidCallback onBack;
  final ValueChanged<UserProfile?> onUserChanged;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String?> onStoreChanged;
  final ValueChanged<bool> onInventoryPermissionChanged;
  final ValueChanged<bool> onOrdersPermissionChanged;
  final VoidCallback onSetRole;
  final ValueChanged<UserProfile> onEditProfile;
  final VoidCallback onAddStoreMember;
  final void Function(StoreMember member, bool value) onUpdateMemberInventory;
  final void Function(StoreMember member, bool value) onUpdateMemberOrders;
  final ValueChanged<StoreMember> onRemoveMember;
  final ValueChanged<UserProfile> onRemoveRider;
  final Future<void> Function(UserProfile profile) onDeleteUser;

  @override
  Widget build(BuildContext context) {
    final userMembers =
        members.where((member) => member.userId == profile.id).toList();
    final paidOrders =
        orders.where((order) => order.paymentStatus == 'paid').toList();
    final activeOrders = orders.where(_isActiveStoreOrder).length;
    final deliveredOrders =
        orders.where((order) => order.status == 'delivered').length;
    final distanceKm = orders.fold<double>(
        0, (total, order) => total + order.deliveryDistanceKm);
    final revenue = paidOrders.fold<double>(
      0,
      (total, order) => total + _revenueForProfile(profile, order),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccessDetailHeader(
          title: profile.displayName,
          subtitle: [
            _humanStatus(profile.role),
            if (profile.phone?.trim().isNotEmpty == true) profile.phone!.trim(),
          ].join(' | '),
          icon: profile.role == 'rider'
              ? Icons.delivery_dining
              : Icons.person_outline,
          onBack: onBack,
        ),
        const SizedBox(height: 16),
        _AdminMetricGrid(
          children: [
            _MetricCard(
              label: 'Orders',
              value: orders.length.toString(),
              icon: Icons.receipt_long_outlined,
            ),
            _MetricCard(
              label: 'Active',
              value: activeOrders.toString(),
              icon: Icons.timelapse_outlined,
            ),
            _MetricCard(
              label: 'Delivered',
              value: deliveredOrders.toString(),
              icon: Icons.verified_outlined,
            ),
            _MetricCard(
              label: 'Route km',
              value: distanceKm.toStringAsFixed(1),
              icon: Icons.route_outlined,
            ),
            _MetricCard(
              label: 'Revenue',
              value: _compactRevenue(revenue),
              icon: Icons.trending_up,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AccessManagementPanel(
          profiles: profiles,
          stores: stores,
          selectedUserId: selectedUserId,
          selectedRole: selectedRole,
          selectedStoreId: selectedStoreId,
          canManageInventory: canManageInventory,
          canManageOrders: canManageOrders,
          isSubmitting: isUpdatingAccess,
          onUserChanged: onUserChanged,
          onRoleChanged: onRoleChanged,
          onStoreChanged: onStoreChanged,
          onInventoryPermissionChanged: onInventoryPermissionChanged,
          onOrdersPermissionChanged: onOrdersPermissionChanged,
          onSetRole: onSetRole,
          onEditProfile: onEditProfile,
          onAddStoreMember: onAddStoreMember,
        ),
        const SizedBox(height: 16),
        _AccessRiskActionsPanel(
          profile: profile,
          memberships: userMembers,
          stores: stores,
          isSubmitting: isUpdatingAccess,
          onRemoveMember: onRemoveMember,
          onRemoveRider: onRemoveRider,
          onDeleteUser: onDeleteUser,
        ),
        const SizedBox(height: 16),
        _AccessStoreStaffList(
          title: 'Store access',
          stores: stores,
          profiles: profiles,
          members: userMembers,
          isSubmitting: isUpdatingAccess,
          onInventoryPermissionChanged: onUpdateMemberInventory,
          onOrdersPermissionChanged: onUpdateMemberOrders,
          onRemoveMember: onRemoveMember,
        ),
        const SizedBox(height: 16),
        _AccessOrdersSnapshot(title: 'Orders', orders: orders),
        const SizedBox(height: 16),
        _AccessRoutesSnapshot(orders: orders),
      ],
    );
  }
}

class _AccessStoreDetailPage extends StatelessWidget {
  const _AccessStoreDetailPage({
    required this.store,
    required this.stores,
    required this.profiles,
    required this.orders,
    required this.members,
    required this.isUpdatingAccess,
    required this.onBack,
    required this.onUpdateMemberInventory,
    required this.onUpdateMemberOrders,
    required this.onRemoveMember,
  });

  final StoreSummary store;
  final List<StoreSummary> stores;
  final List<UserProfile> profiles;
  final List<OrderSummary> orders;
  final List<StoreMember> members;
  final bool isUpdatingAccess;
  final VoidCallback onBack;
  final void Function(StoreMember member, bool value) onUpdateMemberInventory;
  final void Function(StoreMember member, bool value) onUpdateMemberOrders;
  final ValueChanged<StoreMember> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    final paidOrders =
        orders.where((order) => order.paymentStatus == 'paid').toList();
    final activeOrders = orders.where(_isActiveStoreOrder).length;
    final deliveredOrders =
        orders.where((order) => order.status == 'delivered').length;
    final revenue = paidOrders.fold<double>(
      0,
      (total, order) => total + order.storePayoutAmount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccessDetailHeader(
          title: store.name,
          subtitle: [
            _humanStatus(store.category),
            if (store.address.trim().isNotEmpty) store.address.trim(),
          ].join(' | '),
          icon: Icons.storefront_outlined,
          onBack: onBack,
        ),
        const SizedBox(height: 16),
        _AdminMetricGrid(
          children: [
            _MetricCard(
              label: 'Orders',
              value: orders.length.toString(),
              icon: Icons.receipt_long_outlined,
            ),
            _MetricCard(
              label: 'Active',
              value: activeOrders.toString(),
              icon: Icons.timelapse_outlined,
            ),
            _MetricCard(
              label: 'Delivered',
              value: deliveredOrders.toString(),
              icon: Icons.verified_outlined,
            ),
            _MetricCard(
              label: 'Staff',
              value: members.length.toString(),
              icon: Icons.badge_outlined,
            ),
            _MetricCard(
              label: 'Revenue',
              value: _compactRevenue(revenue),
              icon: Icons.trending_up,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AccessStoreStaffList(
          title: 'Store admins',
          stores: stores,
          profiles: profiles,
          members: members,
          isSubmitting: isUpdatingAccess,
          onInventoryPermissionChanged: onUpdateMemberInventory,
          onOrdersPermissionChanged: onUpdateMemberOrders,
          onRemoveMember: onRemoveMember,
        ),
        const SizedBox(height: 16),
        _AccessOrdersSnapshot(title: 'Store orders', orders: orders),
        const SizedBox(height: 16),
        _AccessRoutesSnapshot(orders: orders),
      ],
    );
  }
}

class _AccessDetailHeader extends StatelessWidget {
  const _AccessDetailHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(icon, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    subtitle.isEmpty ? 'No additional details' : subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

class _AccessRiskActionsPanel extends StatelessWidget {
  const _AccessRiskActionsPanel({
    required this.profile,
    required this.memberships,
    required this.stores,
    required this.isSubmitting,
    required this.onRemoveMember,
    required this.onRemoveRider,
    required this.onDeleteUser,
  });

  final UserProfile profile;
  final List<StoreMember> memberships;
  final List<StoreSummary> stores;
  final bool isSubmitting;
  final ValueChanged<StoreMember> onRemoveMember;
  final ValueChanged<UserProfile> onRemoveRider;
  final Future<void> Function(UserProfile profile) onDeleteUser;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Access actions',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: isSubmitting || profile.role != 'rider'
                      ? null
                      : () => onRemoveRider(profile),
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('Remove rider access'),
                ),
                for (final member in memberships)
                  OutlinedButton.icon(
                    onPressed:
                        isSubmitting ? null : () => onRemoveMember(member),
                    icon: const Icon(Icons.link_off_outlined),
                    label: Text(
                      'Remove ${_findStoreById(stores, member.storeId)?.name ?? 'store'}',
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: isSubmitting ? null : () => onDeleteUser(profile),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete account'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Permanent deletion removes the auth account and profile. Historical orders remain for reporting.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessStoreStaffList extends StatelessWidget {
  const _AccessStoreStaffList({
    required this.title,
    required this.stores,
    required this.profiles,
    required this.members,
    required this.isSubmitting,
    required this.onInventoryPermissionChanged,
    required this.onOrdersPermissionChanged,
    required this.onRemoveMember,
  });

  final String title;
  final List<StoreSummary> stores;
  final List<UserProfile> profiles;
  final List<StoreMember> members;
  final bool isSubmitting;
  final void Function(StoreMember member, bool value)
      onInventoryPermissionChanged;
  final void Function(StoreMember member, bool value) onOrdersPermissionChanged;
  final ValueChanged<StoreMember> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (members.isEmpty)
              const Text('No store access records for this detail page.')
            else
              for (final member in members)
                _AccessStoreStaffRow(
                  member: member,
                  profile: _findProfileById(profiles, member.userId),
                  store: _findStoreById(stores, member.storeId),
                  isSubmitting: isSubmitting,
                  onInventoryPermissionChanged: onInventoryPermissionChanged,
                  onOrdersPermissionChanged: onOrdersPermissionChanged,
                  onRemoveMember: onRemoveMember,
                ),
          ],
        ),
      ),
    );
  }
}

class _AccessStoreStaffRow extends StatelessWidget {
  const _AccessStoreStaffRow({
    required this.member,
    required this.profile,
    required this.store,
    required this.isSubmitting,
    required this.onInventoryPermissionChanged,
    required this.onOrdersPermissionChanged,
    required this.onRemoveMember,
  });

  final StoreMember member;
  final UserProfile? profile;
  final StoreSummary? store;
  final bool isSubmitting;
  final void Function(StoreMember member, bool value)
      onInventoryPermissionChanged;
  final void Function(StoreMember member, bool value) onOrdersPermissionChanged;
  final ValueChanged<StoreMember> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
        title: Text(profile?.displayName ?? 'Unknown staff'),
        subtitle: Text(store?.name ?? 'Unknown store'),
        trailing: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('Inventory'),
              selected: member.canManageInventory,
              onSelected: isSubmitting
                  ? null
                  : (value) => onInventoryPermissionChanged(member, value),
            ),
            FilterChip(
              label: const Text('Orders'),
              selected: member.canManageOrders,
              onSelected: isSubmitting
                  ? null
                  : (value) => onOrdersPermissionChanged(member, value),
            ),
            IconButton(
              tooltip: 'Remove store access',
              onPressed: isSubmitting ? null : () => onRemoveMember(member),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessOrdersSnapshot extends StatelessWidget {
  const _AccessOrdersSnapshot({required this.title, required this.orders});

  final String title;
  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context) {
    final recent = orders.take(20).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                Chip(label: Text('${orders.length} total')),
              ],
            ),
            const SizedBox(height: 8),
            if (recent.isEmpty)
              const Text('No orders found for this detail page.')
            else
              for (final order in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Icon(_orderStatusIcon(order.status)),
                  ),
                  title: Text('${order.storeName} | #${_shortId(order.id)}'),
                  subtitle: Text(
                    '${_humanStatus(order.status)} | '
                    '${_humanStatus(order.paymentStatus)} | '
                    '${_formatDateTime(order.createdAt)}',
                  ),
                  trailing: Text(_formatNaira(order.totalAmount)),
                ),
          ],
        ),
      ),
    );
  }
}

class _AccessRoutesSnapshot extends StatelessWidget {
  const _AccessRoutesSnapshot({required this.orders});

  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context) {
    final routeOrders =
        orders.where((order) => order.deliveryDistanceKm > 0).take(20).toList();
    final distanceKm = orders.fold<double>(
        0, (total, order) => total + order.deliveryDistanceKm);
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
                    'Routes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('${distanceKm.toStringAsFixed(1)} km')),
              ],
            ),
            const SizedBox(height: 8),
            if (routeOrders.isEmpty)
              const Text('No route distance has been recorded yet.')
            else
              for (final order in routeOrders)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const CircleAvatar(child: Icon(Icons.route_outlined)),
                  title:
                      Text('${order.deliveryDistanceKm.toStringAsFixed(1)} km'),
                  subtitle: Text(
                    [
                      if (order.storeAddress.trim().isNotEmpty)
                        order.storeAddress.trim(),
                      if (order.deliveryAddress.trim().isNotEmpty)
                        order.deliveryAddress.trim(),
                    ].join(' -> '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text('#${_shortId(order.id)}'),
                ),
          ],
        ),
      ),
    );
  }
}

class _AccessManagementPanel extends StatelessWidget {
  const _AccessManagementPanel({
    required this.profiles,
    required this.stores,
    required this.selectedUserId,
    required this.selectedRole,
    required this.selectedStoreId,
    required this.canManageInventory,
    required this.canManageOrders,
    required this.isSubmitting,
    required this.onUserChanged,
    required this.onRoleChanged,
    required this.onStoreChanged,
    required this.onInventoryPermissionChanged,
    required this.onOrdersPermissionChanged,
    required this.onSetRole,
    required this.onEditProfile,
    required this.onAddStoreMember,
  });

  final List<UserProfile> profiles;
  final List<StoreSummary> stores;
  final String? selectedUserId;
  final String selectedRole;
  final String? selectedStoreId;
  final bool canManageInventory;
  final bool canManageOrders;
  final bool isSubmitting;
  final ValueChanged<UserProfile?> onUserChanged;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String?> onStoreChanged;
  final ValueChanged<bool> onInventoryPermissionChanged;
  final ValueChanged<bool> onOrdersPermissionChanged;
  final VoidCallback onSetRole;
  final ValueChanged<UserProfile> onEditProfile;
  final VoidCallback onAddStoreMember;

  static const _roles = [
    'customer',
    'rider',
    'store_admin',
    'rider_admin',
    'admin',
    'super_admin',
  ];

  @override
  Widget build(BuildContext context) {
    final selectedProfile = _findProfileById(profiles, selectedUserId);
    final isStoreRole = selectedRole == 'store_admin';

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
                    'Role controls',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (selectedProfile != null)
                  Chip(
                    avatar: const Icon(Icons.verified_user_outlined, size: 18),
                    label: Text(_humanStatus(selectedProfile.role)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Select a user, assign their platform role, and optionally attach them to a store.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final userField = DropdownButtonFormField<String>(
                  initialValue:
                      profiles.any((profile) => profile.id == selectedUserId)
                          ? selectedUserId
                          : null,
                  items: [
                    for (final profile in profiles)
                      DropdownMenuItem(
                        value: profile.id,
                        child: Text(
                          '${profile.displayName} (${profile.role})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: isSubmitting
                      ? null
                      : (value) => onUserChanged(
                            _findProfileById(profiles, value),
                          ),
                  decoration: const InputDecoration(
                    labelText: 'User',
                    border: OutlineInputBorder(),
                  ),
                );

                final roleField = DropdownButtonFormField<String>(
                  initialValue:
                      _roles.contains(selectedRole) ? selectedRole : 'customer',
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
                          value: store.id, child: Text(store.name)),
                  ],
                  onChanged:
                      isSubmitting || selectedProfile == null || !isStoreRole
                          ? null
                          : onStoreChanged,
                  decoration: const InputDecoration(
                    labelText: 'Store to add',
                    border: OutlineInputBorder(),
                  ),
                );

                final fields = [userField, roleField, storeField];
                if (constraints.maxWidth < 820) {
                  return Column(
                    children: [
                      for (final field in fields) ...[
                        field,
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                }

                return Row(
                  children: [
                    for (final field in fields) ...[
                      Expanded(child: field),
                      if (field != fields.last) const SizedBox(width: 12),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (selectedProfile != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.person_outline, size: 18),
                        label: Text(selectedProfile.displayName),
                      ),
                      Chip(
                        avatar: const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 18,
                        ),
                        label: Text(
                            'Current ${_humanStatus(selectedProfile.role)}'),
                      ),
                      Chip(
                        avatar: const Icon(Icons.swap_horiz, size: 18),
                        label: Text('New ${_humanStatus(selectedRole)}'),
                      ),
                      if (selectedProfile.phone?.trim().isNotEmpty == true)
                        Chip(
                          avatar: const Icon(Icons.phone_outlined, size: 18),
                          label: Text(selectedProfile.phone!.trim()),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (isStoreRole) ...[
              Text(
                'Store permissions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (isStoreRole) ...[
                  FilterChip(
                    label: const Text('Inventory'),
                    avatar: const Icon(Icons.inventory_2_outlined),
                    selected: canManageInventory,
                    onSelected:
                        isSubmitting ? null : onInventoryPermissionChanged,
                  ),
                  FilterChip(
                    label: const Text('Orders'),
                    avatar: const Icon(Icons.receipt_long_outlined),
                    selected: canManageOrders,
                    onSelected: isSubmitting ? null : onOrdersPermissionChanged,
                  ),
                ],
                FilledButton.icon(
                  onPressed: isSubmitting || selectedProfile == null
                      ? null
                      : onSetRole,
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: Text(isSubmitting ? 'Saving...' : 'Apply role'),
                ),
                OutlinedButton.icon(
                  onPressed: isSubmitting || selectedProfile == null
                      ? null
                      : () => onEditProfile(selectedProfile),
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Edit contact'),
                ),
                FilledButton.icon(
                  onPressed: isSubmitting ||
                          selectedProfile == null ||
                          selectedStoreId == null ||
                          !isStoreRole
                      ? null
                      : onAddStoreMember,
                  icon: const Icon(Icons.storefront),
                  label: const Text('Add store access'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (selectedProfile == null)
              const Text('No users available yet')
            else if (!isStoreRole)
              Text(
                'Store access is only needed for store admins. Role changes for rider admins, super admins, riders, admins, and customers do not require a store.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Text(
                selectedStoreId == null
                    ? 'Choose a store before adding store access.'
                    : 'Selected user ID: ${selectedProfile.id}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
