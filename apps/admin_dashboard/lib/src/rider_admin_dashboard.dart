part of '../main.dart';

class _RiderAdminDashboard extends StatelessWidget {
  const _RiderAdminDashboard({
    required this.repository,
    required this.userEmail,
    required this.selectedIndex,
    required this.userFormKey,
    required this.isCreatingUser,
    required this.isUpdatingAccess,
    required this.userEmailController,
    required this.userPasswordController,
    required this.userFullNameController,
    required this.userPhoneController,
    required this.onSectionChanged,
    required this.onNewUserRoleChanged,
    required this.onCreateUser,
    required this.onRemoveRider,
  });

  final PlatformRepository repository;
  final String userEmail;
  final int selectedIndex;
  final GlobalKey<FormState> userFormKey;
  final bool isCreatingUser;
  final bool isUpdatingAccess;
  final TextEditingController userEmailController;
  final TextEditingController userPasswordController;
  final TextEditingController userFullNameController;
  final TextEditingController userPhoneController;
  final ValueChanged<int> onSectionChanged;
  final ValueChanged<String> onNewUserRoleChanged;
  final VoidCallback onCreateUser;
  final ValueChanged<UserProfile> onRemoveRider;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserProfile>>(
      stream: repository.watchProfiles(),
      builder: (context, profilesSnapshot) {
        return StreamBuilder<List<OrderSummary>>(
          stream: repository.watchAllOrders(),
          builder: (context, ordersSnapshot) {
            return StreamBuilder<List<RiderAvailability>>(
              stream: repository.watchRiderAvailability(),
              builder: (context, availabilitySnapshot) {
                return StreamBuilder<List<RiderSettlementSummary>>(
                  stream: repository.watchRiderSettlements(),
                  builder: (context, settlementsSnapshot) {
                    return StreamBuilder<List<RiderLocationUpdate>>(
                      stream: repository.watchAllRiderLocations(),
                      builder: (context, locationsSnapshot) {
                        final error = profilesSnapshot.error ??
                            ordersSnapshot.error ??
                            availabilitySnapshot.error ??
                            settlementsSnapshot.error;
                        if (error != null) {
                          return _InlineState(
                            title: 'Rider dashboard failed to load',
                            message: error.toString(),
                          );
                        }

                        final isLoading = profilesSnapshot.connectionState ==
                                ConnectionState.waiting ||
                            ordersSnapshot.connectionState ==
                                ConnectionState.waiting;
                        if (isLoading) {
                          return const _InlineState(
                            title: 'Loading rider command',
                            message: 'Fetching riders, orders, and routes...',
                            isLoading: true,
                          );
                        }

                        return _RiderAdminDashboardBody(
                          repository: repository,
                          userEmail: userEmail,
                          profiles:
                              profilesSnapshot.data ?? const <UserProfile>[],
                          orders: ordersSnapshot.data ?? const <OrderSummary>[],
                          availability: availabilitySnapshot.data ??
                              const <RiderAvailability>[],
                          settlements: settlementsSnapshot.data ??
                              const <RiderSettlementSummary>[],
                          locations: locationsSnapshot.data ??
                              const <RiderLocationUpdate>[],
                          selectedIndex: selectedIndex,
                          userFormKey: userFormKey,
                          isCreatingUser: isCreatingUser,
                          isUpdatingAccess: isUpdatingAccess,
                          userEmailController: userEmailController,
                          userPasswordController: userPasswordController,
                          userFullNameController: userFullNameController,
                          userPhoneController: userPhoneController,
                          onSectionChanged: onSectionChanged,
                          onNewUserRoleChanged: onNewUserRoleChanged,
                          onCreateUser: onCreateUser,
                          onRemoveRider: onRemoveRider,
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
  }
}

class _RiderAdminDashboardBody extends StatelessWidget {
  const _RiderAdminDashboardBody({
    required this.repository,
    required this.userEmail,
    required this.profiles,
    required this.orders,
    required this.availability,
    required this.settlements,
    required this.locations,
    required this.selectedIndex,
    required this.userFormKey,
    required this.isCreatingUser,
    required this.isUpdatingAccess,
    required this.userEmailController,
    required this.userPasswordController,
    required this.userFullNameController,
    required this.userPhoneController,
    required this.onSectionChanged,
    required this.onNewUserRoleChanged,
    required this.onCreateUser,
    required this.onRemoveRider,
  });

  final PlatformRepository repository;
  final String userEmail;
  final List<UserProfile> profiles;
  final List<OrderSummary> orders;
  final List<RiderAvailability> availability;
  final List<RiderSettlementSummary> settlements;
  final List<RiderLocationUpdate> locations;
  final int selectedIndex;
  final GlobalKey<FormState> userFormKey;
  final bool isCreatingUser;
  final bool isUpdatingAccess;
  final TextEditingController userEmailController;
  final TextEditingController userPasswordController;
  final TextEditingController userFullNameController;
  final TextEditingController userPhoneController;
  final ValueChanged<int> onSectionChanged;
  final ValueChanged<String> onNewUserRoleChanged;
  final VoidCallback onCreateUser;
  final ValueChanged<UserProfile> onRemoveRider;

  @override
  Widget build(BuildContext context) {
    final riders = profiles.where((profile) => profile.role == 'rider').toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final riderOrders = orders.where((order) => order.riderId != null).toList();
    final onlineRiders =
        availability.where((item) => item.isOnline).map((item) => item.riderId);
    final activeDeliveries = riderOrders.where(_isActiveStoreOrder).length;
    final deliveredOrders =
        riderOrders.where((order) => order.status == 'delivered').length;
    final cancelledOrders =
        riderOrders.where((order) => order.status == 'cancelled').length;
    final deliveryRevenue = riderOrders.fold<double>(
      0,
      (total, order) => total + order.deliveryFee,
    );
    final riderPayout = riderOrders.fold<double>(
      0,
      (total, order) => total + order.riderPayoutAmount,
    );
    final kmCovered = riderOrders.fold<double>(
      0,
      (total, order) => total + order.deliveryDistanceKm,
    );
    final availabilityByRiderId = {
      for (final item in availability) item.riderId: item,
    };

    final header = _RiderAdminHeader(
      userEmail: userEmail,
      onlineCount: onlineRiders.toSet().length,
      riderCount: riders.length,
    );
    final sections = [
      _AdminDashboardSection(
        label: 'Overview',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        page: _AdminSectionPage(
          title: 'Rider operations',
          description:
              'Monitor rider capacity, live deliveries, route coverage, and delivery revenue in one focused workspace.',
          children: [
            header,
            const SizedBox(height: 16),
            _AdminMetricGrid(
              children: [
                _MetricCard(label: 'Riders', value: riders.length.toString()),
                _MetricCard(
                  label: 'Online now',
                  value: onlineRiders.toSet().length.toString(),
                ),
                _MetricCard(
                  label: 'Active deliveries',
                  value: activeDeliveries.toString(),
                ),
                _MetricCard(
                  label: 'Delivered',
                  value: deliveredOrders.toString(),
                ),
                _MetricCard(
                  label: 'Cancelled',
                  value: cancelledOrders.toString(),
                ),
                _MetricCard(
                  label: 'Delivery revenue',
                  value: _formatNaira(deliveryRevenue),
                ),
                _MetricCard(
                  label: 'Rider payout',
                  value: _formatNaira(riderPayout),
                ),
                _MetricCard(
                  label: 'KM covered',
                  value: kmCovered.toStringAsFixed(1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _AdminRevenueChart(
              title: 'Delivery revenue trend',
              orders: riderOrders,
              valueForOrder: (order) => order.deliveryFee,
            ),
            const SizedBox(height: 16),
            _OrderStatusSummaryPanel(orders: riderOrders),
            const SizedBox(height: 16),
            _RiderLeaderboardPanel(
              riders: riders,
              orders: riderOrders,
              availabilityByRiderId: availabilityByRiderId,
            ),
          ],
        ),
      ),
      _AdminDashboardSection(
        label: 'Orders',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        page: _AdminSectionPage(
          title: 'Rider orders',
          description:
              'Track assigned, picked up, delivered, and cancelled rider orders with route context.',
          children: [
            header,
            const SizedBox(height: 16),
            _RiderOrdersPanel(orders: riderOrders),
          ],
        ),
      ),
      _AdminDashboardSection(
        label: 'Routes',
        icon: Icons.route_outlined,
        selectedIcon: Icons.route,
        page: _AdminSectionPage(
          title: 'Routes and coverage',
          description:
              'Review recent rider location pings, store-to-customer distance, and route coverage.',
          children: [
            header,
            const SizedBox(height: 16),
            _RiderRoutesPanel(
              orders: riderOrders,
              locations: locations,
            ),
          ],
        ),
      ),
      _AdminDashboardSection(
        label: 'Revenue',
        icon: Icons.payments_outlined,
        selectedIcon: Icons.payments,
        page: _AdminSectionPage(
          title: 'Rider revenue',
          description:
              'Monitor generated delivery fees, rider split amounts, platform delivery margin, and direct Monnify routing.',
          children: [
            header,
            const SizedBox(height: 16),
            _RiderRevenuePanel(
              orders: riderOrders,
              settlements: settlements,
            ),
          ],
        ),
      ),
      _AdminDashboardSection(
        label: 'Riders',
        icon: Icons.delivery_dining_outlined,
        selectedIcon: Icons.delivery_dining,
        page: _AdminSectionPage(
          title: 'Rider access',
          description:
              'Add riders, monitor availability, and remove delivery access when a rider should no longer receive work.',
          children: [
            header,
            const SizedBox(height: 16),
            _RiderAdminCreateRiderPanel(
              formKey: userFormKey,
              emailController: userEmailController,
              passwordController: userPasswordController,
              fullNameController: userFullNameController,
              phoneController: userPhoneController,
              isSubmitting: isCreatingUser,
              onSubmit: () {
                onNewUserRoleChanged('rider');
                onCreateUser();
              },
            ),
            const SizedBox(height: 16),
            _AdminRidersPanel(
              repository: repository,
              profiles: profiles,
              onRemoveRider: onRemoveRider,
            ),
          ],
        ),
      ),
    ];

    final safeIndex = selectedIndex >= sections.length ? 0 : selectedIndex;
    return AbsorbPointer(
      absorbing: isUpdatingAccess,
      child: _AdminDashboardShell(
        title: 'Rider admin',
        userEmail: userEmail,
        sections: sections,
        selectedIndex: safeIndex,
        onSectionChanged: onSectionChanged,
      ),
    );
  }
}

class _RiderAdminHeader extends StatelessWidget {
  const _RiderAdminHeader({
    required this.userEmail,
    required this.onlineCount,
    required this.riderCount,
  });

  final String userEmail;
  final int onlineCount;
  final int riderCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          avatar: const Icon(Icons.delivery_dining, size: 18),
          label: Text('$onlineCount online'),
        ),
        Chip(
          avatar: const Icon(Icons.groups_outlined, size: 18),
          label: Text('$riderCount riders'),
        ),
        Chip(
          avatar: const Icon(Icons.person_outline, size: 18),
          label: Text(userEmail),
        ),
      ],
    );
  }
}

class _RiderLeaderboardPanel extends StatelessWidget {
  const _RiderLeaderboardPanel({
    required this.riders,
    required this.orders,
    required this.availabilityByRiderId,
  });

  final List<UserProfile> riders;
  final List<OrderSummary> orders;
  final Map<String, RiderAvailability> availabilityByRiderId;

  @override
  Widget build(BuildContext context) {
    final sortedRiders = riders.toList()
      ..sort((a, b) {
        final aDelivered = orders
            .where(
                (order) => order.riderId == a.id && order.status == 'delivered')
            .length;
        final bDelivered = orders
            .where(
                (order) => order.riderId == b.id && order.status == 'delivered')
            .length;
        return bDelivered.compareTo(aDelivered);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Top rider activity',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (sortedRiders.isEmpty)
              const Text('No rider accounts yet.')
            else
              for (final rider in sortedRiders.take(8))
                _CompactRiderTile(
                  rider: rider,
                  orders: orders,
                  availability: availabilityByRiderId[rider.id],
                ),
          ],
        ),
      ),
    );
  }
}

class _RiderOrdersPanel extends StatefulWidget {
  const _RiderOrdersPanel({required this.orders});

  final List<OrderSummary> orders;

  @override
  State<_RiderOrdersPanel> createState() => _RiderOrdersPanelState();
}

class _RiderOrdersPanelState extends State<_RiderOrdersPanel> {
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
        'delivered' => order.status == 'delivered',
        'cancelled' => order.status == 'cancelled',
        'all' => true,
        _ => _isActiveStoreOrder(order),
      };
      final query = _searchController.text.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          order.id.toLowerCase().contains(query) ||
          order.storeName.toLowerCase().contains(query) ||
          (order.riderName ?? '').toLowerCase().contains(query) ||
          order.deliveryAddress.toLowerCase().contains(query);
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
                    'Rider order monitor',
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
                labelText: 'Search rider, store, order, or drop-off',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in const [
                  ('active', 'Active'),
                  ('delivered', 'Delivered'),
                  ('cancelled', 'Cancelled'),
                  ('all', 'All'),
                ])
                  ChoiceChip(
                    label: Text(filter.$2),
                    selected: _filter == filter.$1,
                    onSelected: (_) => setState(() {
                      _filter = filter.$1;
                      _page = 0;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.orders.isEmpty)
              const Text('No rider orders yet.')
            else if (visibleOrders.isEmpty)
              const Text('No rider orders match these filters.')
            else ...[
              _PagedListControls(
                page: safePage,
                totalItems: visibleOrders.length,
                onPageChanged: (page) => setState(() => _page = page),
              ),
              const SizedBox(height: 8),
              for (final order in pagedOrders)
                _RiderOrderMonitorTile(order: order),
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

class _RiderOrderMonitorTile extends StatelessWidget {
  const _RiderOrderMonitorTile({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(_orderStatusIcon(order.status)),
        ),
        title: Text('${order.storeName} | Order #${_shortId(order.id)}'),
        subtitle: Text(
          [
            order.riderName ?? 'Unassigned rider',
            _humanStatus(order.status),
            _formatNaira(order.deliveryFee),
            '${order.deliveryDistanceKm.toStringAsFixed(1)} km',
            if (order.deliveryAddress.trim().isNotEmpty) order.deliveryAddress,
          ].join(' | '),
        ),
        trailing: Chip(label: Text(_humanStatus(order.paymentStatus))),
      ),
    );
  }
}

class _RiderRoutesPanel extends StatefulWidget {
  const _RiderRoutesPanel({
    required this.orders,
    required this.locations,
  });

  final List<OrderSummary> orders;
  final List<RiderLocationUpdate> locations;

  @override
  State<_RiderRoutesPanel> createState() => _RiderRoutesPanelState();
}

class _RiderRoutesPanelState extends State<_RiderRoutesPanel> {
  var _page = 0;

  @override
  Widget build(BuildContext context) {
    final kmCovered = widget.orders.fold<double>(
      0,
      (total, order) => total + order.deliveryDistanceKm,
    );
    final activeRoutes = widget.orders
        .where((order) => order.riderId != null && _isActiveStoreOrder(order));
    final recentLocations = widget.locations.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final safePage = _coerceListPage(_page, recentLocations.length);
    if (safePage != _page) {
      _page = safePage;
    }
    final pagedLocations = recentLocations
        .skip(safePage * _adminListPageSize)
        .take(_adminListPageSize)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdminMetricGrid(
          children: [
            _MetricCard(
              label: 'Active routes',
              value: activeRoutes.length.toString(),
            ),
            _MetricCard(
              label: 'Route pings',
              value: widget.locations.length.toString(),
            ),
            _MetricCard(
              label: 'KM covered',
              value: kmCovered.toStringAsFixed(1),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Recent route updates',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (recentLocations.isEmpty)
                  const Text('No rider location updates yet.')
                else ...[
                  _PagedListControls(
                    page: safePage,
                    totalItems: recentLocations.length,
                    onPageChanged: (page) => setState(() => _page = page),
                  ),
                  const SizedBox(height: 8),
                  for (final update in pagedLocations)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.my_location_outlined),
                      title: Text(
                        update.riderName ?? 'Rider ${_shortId(update.riderId)}',
                      ),
                      subtitle: Text(
                        [
                          update.storeName ?? 'Delivery route',
                          'Order ${_shortId(update.orderId)}',
                          '${update.latitude.toStringAsFixed(5)}, ${update.longitude.toStringAsFixed(5)}',
                          _formatDateTime(update.createdAt),
                        ].join(' | '),
                      ),
                      trailing: update.deliveryDistanceKm <= 0
                          ? null
                          : Chip(
                              label: Text(
                                '${update.deliveryDistanceKm.toStringAsFixed(1)} km',
                              ),
                            ),
                    ),
                  const SizedBox(height: 8),
                  _PagedListControls(
                    page: safePage,
                    totalItems: recentLocations.length,
                    onPageChanged: (page) => setState(() => _page = page),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RiderRevenuePanel extends StatefulWidget {
  const _RiderRevenuePanel({
    required this.orders,
    required this.settlements,
  });

  final List<OrderSummary> orders;
  final List<RiderSettlementSummary> settlements;

  @override
  State<_RiderRevenuePanel> createState() => _RiderRevenuePanelState();
}

class _RiderRevenuePanelState extends State<_RiderRevenuePanel> {
  var _page = 0;

  @override
  Widget build(BuildContext context) {
    final deliveryFees = widget.orders.fold<double>(
      0,
      (total, order) => total + order.deliveryFee,
    );
    final riderPayout = widget.orders.fold<double>(
      0,
      (total, order) => total + order.riderPayoutAmount,
    );
    final pendingSettlements = widget.settlements
        .where((settlement) => settlement.status == 'pending');
    final pendingPayout = pendingSettlements.fold<double>(
      0,
      (total, settlement) => total + settlement.riderPayoutAmount,
    );
    final deliveryMargin = widget.settlements.fold<double>(
      0,
      (total, settlement) => total + settlement.platformDeliveryMargin,
    );
    final safePage = _coerceListPage(_page, widget.settlements.length);
    if (safePage != _page) {
      _page = safePage;
    }
    final pagedSettlements = widget.settlements
        .skip(safePage * _adminListPageSize)
        .take(_adminListPageSize)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdminMetricGrid(
          children: [
            _MetricCard(
              label: 'Delivery fees',
              value: _formatNaira(deliveryFees),
            ),
            _MetricCard(
              label: 'Rider split',
              value: _formatNaira(riderPayout),
            ),
            _MetricCard(
              label: 'Pending split',
              value: _formatNaira(pendingPayout),
            ),
            _MetricCard(
              label: 'Platform margin',
              value: _formatNaira(deliveryMargin),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AdminRevenueChart(
          title: 'Rider split trend',
          orders: widget.orders,
          valueForOrder: (order) => order.riderPayoutAmount,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Rider split records',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (widget.settlements.isEmpty)
                  const Text('No rider split records yet.')
                else ...[
                  _PagedListControls(
                    page: safePage,
                    totalItems: widget.settlements.length,
                    onPageChanged: (page) => setState(() => _page = page),
                  ),
                  const SizedBox(height: 8),
                  for (final settlement in pagedSettlements)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        settlement.status == 'paid'
                            ? Icons.verified_outlined
                            : Icons.pending_actions_outlined,
                      ),
                      title: Text(
                        '${settlement.riderName ?? 'Rider'} | ${_formatNaira(settlement.riderPayoutAmount)}',
                      ),
                      subtitle: Text(
                        '${settlement.storeName} | Order ${_shortId(settlement.orderId)} | '
                        '${_humanStatus(settlement.status)} | '
                        '${_formatDateTime(settlement.updatedAt)}',
                      ),
                      trailing: Chip(
                        label: Text(_formatNaira(settlement.deliveryFeeAmount)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _PagedListControls(
                    page: safePage,
                    totalItems: widget.settlements.length,
                    onPageChanged: (page) => setState(() => _page = page),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RiderAdminCreateRiderPanel extends StatelessWidget {
  const _RiderAdminCreateRiderPanel({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.fullNameController,
    required this.phoneController,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController fullNameController;
  final TextEditingController phoneController;
  final bool isSubmitting;
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
              Text('Add rider', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final fields = [
                    TextFormField(
                      controller: fullNameController,
                      enabled: !isSubmitting,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredText,
                    ),
                    TextFormField(
                      controller: phoneController,
                      enabled: !isSubmitting,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: emailController,
                      enabled: !isSubmitting,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: _emailText,
                    ),
                    TextFormField(
                      controller: passwordController,
                      enabled: !isSubmitting,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Temporary password',
                        border: OutlineInputBorder(),
                      ),
                      validator: _passwordText,
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
                          width: (constraints.maxWidth - 12) / 2,
                          child: field,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: isSubmitting ? null : onSubmit,
                  icon: isSubmitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1),
                  label: Text(isSubmitting ? 'Creating...' : 'Create rider'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminRidersPanel extends StatefulWidget {
  const _AdminRidersPanel({
    required this.repository,
    required this.profiles,
    required this.onRemoveRider,
  });

  final PlatformRepository repository;
  final List<UserProfile> profiles;
  final ValueChanged<UserProfile> onRemoveRider;

  @override
  State<_AdminRidersPanel> createState() => _AdminRidersPanelState();
}

class _AdminRidersPanelState extends State<_AdminRidersPanel> {
  var _page = 0;

  @override
  Widget build(BuildContext context) {
    final riders = widget.profiles
        .where((profile) => profile.role == 'rider')
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final safePage = _coerceListPage(_page, riders.length);
    if (safePage != _page) {
      _page = safePage;
    }
    final pagedRiders = riders
        .skip(safePage * _adminListPageSize)
        .take(_adminListPageSize)
        .toList();

    return StreamBuilder<List<RiderAvailability>>(
      stream: widget.repository.watchRiderAvailability(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Riders failed to load: ${snapshot.error}'),
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

        final availabilityByRiderId = {
          for (final availability
              in snapshot.data ?? const <RiderAvailability>[])
            availability.riderId: availability,
        };
        final onlineCount = riders
            .where(
              (rider) => availabilityByRiderId[rider.id]?.isOnline ?? false,
            )
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
                        'Riders',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Chip(label: Text('$onlineCount online')),
                    const SizedBox(width: 8),
                    Chip(label: Text('${riders.length} total')),
                  ],
                ),
                const SizedBox(height: 8),
                if (riders.isEmpty)
                  const Text('No rider accounts yet.')
                else ...[
                  _PagedListControls(
                    page: safePage,
                    totalItems: riders.length,
                    onPageChanged: (page) => setState(() => _page = page),
                  ),
                  const SizedBox(height: 8),
                  for (final rider in pagedRiders)
                    _AdminRiderTile(
                      rider: rider,
                      availability: availabilityByRiderId[rider.id],
                      onRemove: () => widget.onRemoveRider(rider),
                    ),
                  const SizedBox(height: 8),
                  _PagedListControls(
                    page: safePage,
                    totalItems: riders.length,
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

class _AdminRiderTile extends StatelessWidget {
  const _AdminRiderTile({
    required this.rider,
    required this.availability,
    required this.onRemove,
  });

  final UserProfile rider;
  final RiderAvailability? availability;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isOnline = availability?.isOnline ?? false;
    final phone = rider.phone?.trim();

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              child: Icon(
                isOnline ? Icons.delivery_dining : Icons.person_outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rider.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (phone != null && phone.isNotEmpty) phone,
                      availability == null
                          ? 'Never came online'
                          : 'Last seen ${_formatDateTime(availability!.lastSeenAt)}',
                    ].join(' | '),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: Icon(
                          isOnline
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                        ),
                        label: Text(isOnline ? 'Online' : 'Offline'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onRemove,
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('Remove access'),
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

class _CompactRiderTile extends StatelessWidget {
  const _CompactRiderTile({
    required this.rider,
    required this.orders,
    required this.availability,
  });

  final UserProfile rider;
  final List<OrderSummary> orders;
  final RiderAvailability? availability;

  @override
  Widget build(BuildContext context) {
    final riderOrders =
        orders.where((order) => order.riderId == rider.id).toList();
    final delivered =
        riderOrders.where((order) => order.status == 'delivered').length;
    final generated = riderOrders.fold<double>(
      0,
      (total, order) => total + order.deliveryFee,
    );
    final kmCovered = riderOrders.fold<double>(
      0,
      (total, order) => total + order.deliveryDistanceKm,
    );

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            availability?.isOnline == true
                ? Icons.delivery_dining
                : Icons.person_outline,
          ),
        ),
        title: Text(rider.displayName),
        subtitle: Text(
          '$delivered delivered | ${_formatNaira(generated)} revenue | '
          '${kmCovered.toStringAsFixed(1)} km',
        ),
        trailing: Chip(
          label: Text(availability?.isOnline == true ? 'Online' : 'Offline'),
        ),
      ),
    );
  }
}
