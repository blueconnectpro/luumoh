part of '../main.dart';

class _StoreOwnerDashboard extends StatefulWidget {
  const _StoreOwnerDashboard({
    required this.repository,
    required this.userEmail,
    required this.profile,
  });

  final PlatformRepository repository;
  final String userEmail;
  final UserProfile profile;

  @override
  State<_StoreOwnerDashboard> createState() => _StoreOwnerDashboardState();
}

class _StoreOwnerDashboardState extends State<_StoreOwnerDashboard> {
  String? _selectedStoreId;
  int _selectedManagerPage = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoreMember>>(
      stream: widget.repository.watchMyStoreMemberships(),
      builder: (context, membershipsSnapshot) {
        if (membershipsSnapshot.hasError) {
          return _InlineState(
            title: 'Store access failed to load',
            message: membershipsSnapshot.error.toString(),
          );
        }

        if (membershipsSnapshot.connectionState == ConnectionState.waiting) {
          return const _InlineState(
            title: 'Loading owner dashboard',
            message: 'Fetching your stores...',
            isLoading: true,
          );
        }

        final memberships = membershipsSnapshot.data ?? const <StoreMember>[];
        if (memberships.isEmpty) {
          return const _InlineState(
            title: 'No store access',
            message: 'Ask an admin to add this account to a store.',
          );
        }

        _selectedStoreId ??= memberships.first.storeId;
        final selectedStoreId = _selectedStoreId!;
        final selectedMembership = memberships.firstWhere(
          (membership) => membership.storeId == selectedStoreId,
          orElse: () => memberships.first,
        );
        final allowedStoreIds =
            memberships.map((membership) => membership.storeId).toSet();

        return StreamBuilder<List<StoreSummary>>(
          stream: widget.repository.watchStores(activeOnly: false),
          builder: (context, storesSnapshot) {
            final stores = (storesSnapshot.data ?? const <StoreSummary>[])
                .where((store) => allowedStoreIds.contains(store.id))
                .toList();
            final selectedStore = _storeById(stores, selectedStoreId);

            return StreamBuilder<List<OrderSummary>>(
              stream: widget.repository.watchStoreOrders(selectedStoreId),
              builder: (context, ordersSnapshot) {
                final orders = ordersSnapshot.data ?? const <OrderSummary>[];
                return StreamBuilder<List<StoreInventoryItem>>(
                  stream:
                      widget.repository.watchStoreInventory(selectedStoreId),
                  builder: (context, inventorySnapshot) {
                    final inventory =
                        inventorySnapshot.data ?? const <StoreInventoryItem>[];
                    return StreamBuilder<List<StoreOpeningHour>>(
                      stream: widget.repository.watchStoreOpeningHours(
                        selectedStoreId,
                      ),
                      builder: (context, hoursSnapshot) {
                        final openingHours =
                            hoursSnapshot.data ?? const <StoreOpeningHour>[];
                        return StreamBuilder<List<StoreSettlementSummary>>(
                          stream: widget.repository.watchStoreSettlements(
                            storeId: selectedStoreId,
                          ),
                          builder: (context, settlementsSnapshot) {
                            final settlements = settlementsSnapshot.data ??
                                const <StoreSettlementSummary>[];
                            return StreamBuilder<List<StoreStaffPresence>>(
                              stream: widget.repository.watchStoreStaffPresence(
                                storeId: selectedStoreId,
                              ),
                              builder: (context, presenceSnapshot) {
                                final staffPresence = presenceSnapshot.data ??
                                    const <StoreStaffPresence>[];
                                return StreamBuilder<
                                    List<StoreEmployeeActivity>>(
                                  stream: widget.repository
                                      .watchStoreEmployeeActivities(
                                    storeId: selectedStoreId,
                                  ),
                                  builder: (context, activitySnapshot) {
                                    final staffActivities =
                                        activitySnapshot.data ??
                                            const <StoreEmployeeActivity>[];
                                    return _StoreOwnerDashboardBody(
                                      repository: widget.repository,
                                      userEmail: widget.userEmail,
                                      stores: stores,
                                      selectedStore: selectedStore,
                                      selectedStoreId: selectedStoreId,
                                      selectedMembership: selectedMembership,
                                      orders: orders,
                                      inventory: inventory,
                                      openingHours: openingHours,
                                      settlements: settlements,
                                      staffPresence: staffPresence,
                                      staffActivities: staffActivities,
                                      selectedIndex: _selectedManagerPage,
                                      onSectionChanged: (index) => setState(
                                        () => _selectedManagerPage = index,
                                      ),
                                      onStoreChanged: stores.length <= 1
                                          ? null
                                          : (value) => setState(() {
                                                _selectedStoreId = value;
                                                _selectedManagerPage = 0;
                                              }),
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
            );
          },
        );
      },
    );
  }
}

class _StoreOwnerDashboardBody extends StatelessWidget {
  const _StoreOwnerDashboardBody({
    required this.repository,
    required this.userEmail,
    required this.stores,
    required this.selectedStoreId,
    required this.selectedMembership,
    required this.orders,
    required this.inventory,
    required this.openingHours,
    required this.settlements,
    required this.staffPresence,
    required this.staffActivities,
    required this.selectedIndex,
    required this.onSectionChanged,
    required this.onStoreChanged,
    this.selectedStore,
  });

  final PlatformRepository repository;
  final String userEmail;
  final List<StoreSummary> stores;
  final StoreSummary? selectedStore;
  final String selectedStoreId;
  final StoreMember selectedMembership;
  final List<OrderSummary> orders;
  final List<StoreInventoryItem> inventory;
  final List<StoreOpeningHour> openingHours;
  final List<StoreSettlementSummary> settlements;
  final List<StoreStaffPresence> staffPresence;
  final List<StoreEmployeeActivity> staffActivities;
  final int selectedIndex;
  final ValueChanged<int> onSectionChanged;
  final ValueChanged<String?>? onStoreChanged;

  @override
  Widget build(BuildContext context) {
    final paidOrders =
        orders.where((order) => order.paymentStatus == 'paid').toList();
    final revenue =
        paidOrders.fold<double>(0, (total, order) => total + order.totalAmount);
    final storePayout = paidOrders.fold<double>(
      0,
      (total, order) => total + order.storePayoutAmount,
    );
    final activeOrders = orders.where(_isActiveStoreOrder).length;
    final acceptedOrders = orders.where((order) {
      return const {
        'accepted',
        'preparing',
        'ready_for_pickup',
        'assigned_to_rider',
        'out_for_delivery',
        'delivered',
      }.contains(order.status);
    }).length;
    final deliveredOrders =
        orders.where((order) => order.status == 'delivered').length;
    final cancelledOrders =
        orders.where((order) => order.status == 'cancelled').length;
    final lowStock = inventory
        .where((item) => item.quantityAvailable <= item.reorderLevel)
        .length;
    final activeStaff =
        staffPresence.where((presence) => presence.isActive).length;

    final header = _StoreManagerHeader(
      userEmail: userEmail,
      stores: stores,
      selectedStoreId: selectedStoreId,
      selectedStore: selectedStore,
      onStoreChanged: onStoreChanged,
    );
    final sections = [
      _AdminDashboardSection(
        label: 'Overview',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        page: _AdminSectionPage(
          title: selectedStore?.name ?? 'Store overview',
          description:
              'Store-scoped operations, inventory health, opening hours, and payout health.',
          children: [
            header,
            const SizedBox(height: 16),
            _AdminMetricGrid(
              children: [
                _MetricCard(label: 'Orders', value: orders.length.toString()),
                _MetricCard(
                  label: 'Active orders',
                  value: activeOrders.toString(),
                ),
                _MetricCard(
                  label: 'Accepted',
                  value: acceptedOrders.toString(),
                ),
                _MetricCard(
                  label: 'Delivered',
                  value: deliveredOrders.toString(),
                ),
                _MetricCard(
                  label: 'Cancelled',
                  value: cancelledOrders.toString(),
                ),
                _MetricCard(label: 'Revenue', value: _formatNaira(revenue)),
                _MetricCard(
                  label: 'Store payout',
                  value: _formatNaira(storePayout),
                ),
                _MetricCard(
                  label: 'Inventory SKUs',
                  value: inventory.length.toString(),
                ),
                _MetricCard(label: 'Low stock', value: lowStock.toString()),
                _MetricCard(
                    label: 'Active staff', value: activeStaff.toString()),
              ],
            ),
            const SizedBox(height: 16),
            _AdminRevenueChart(
              title: 'Revenue trend',
              orders: orders,
              valueForOrder: (order) =>
                  order.paymentStatus == 'paid' ? order.totalAmount : 0,
            ),
            const SizedBox(height: 16),
            _OrderStatusSummaryPanel(orders: orders),
            const SizedBox(height: 16),
            _RecentAdminOrdersPanel(orders: orders),
          ],
        ),
      ),
      _AdminDashboardSection(
        label: 'Orders',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        page: _AdminSectionPage(
          title: 'Store orders',
          description:
              'Monitor paid, active, delivered, and cancelled orders for this store.',
          children: [
            header,
            const SizedBox(height: 16),
            _OwnerOrderOpsPanel(
              repository: repository,
              orders: orders,
              canManageOrders: selectedMembership.canManageOrders,
            ),
          ],
        ),
      ),
      _AdminDashboardSection(
        label: 'Inventory',
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        page: _AdminSectionPage(
          title: 'Store inventory',
          description:
              'Monitor catalog items, stock availability, reorder pressure, and product uploads for this store.',
          children: [
            header,
            const SizedBox(height: 16),
            _OwnerInventoryPanel(
              repository: repository,
              storeId: selectedStoreId,
              inventory: inventory,
              canManageInventory: selectedMembership.canManageInventory,
            ),
          ],
        ),
      ),
      _AdminDashboardSection(
        label: 'Hours',
        icon: Icons.schedule_outlined,
        selectedIcon: Icons.schedule,
        page: _AdminSectionPage(
          title: 'Store hours',
          description:
              'Monitor and update opening windows customers rely on before ordering.',
          children: [
            header,
            const SizedBox(height: 16),
            _StoreHoursPanel(
              repository: repository,
              storeId: selectedStoreId,
              hours: openingHours,
              canManage: selectedMembership.canManageOrders,
            ),
          ],
        ),
      ),
      _AdminDashboardSection(
        label: 'Staff',
        icon: Icons.badge_outlined,
        selectedIcon: Icons.badge,
        page: _AdminSectionPage(
          title: 'Staff activity',
          description:
              'See who is active in this store, what they changed, and where order handling needs attention.',
          children: [
            header,
            const SizedBox(height: 16),
            _StoreStaffActivityPanel(
              staffPresence: staffPresence,
              staffActivities: staffActivities,
            ),
          ],
        ),
      ),
      _AdminDashboardSection(
        label: 'Revenue',
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet,
        page: _AdminSectionPage(
          title: 'Store revenue',
          description:
              'Track revenue, fees, store split amounts, and direct Monnify routing for this store.',
          children: [
            header,
            const SizedBox(height: 16),
            _StoreManagerRevenuePanel(
              orders: orders,
              settlements: settlements,
            ),
          ],
        ),
      ),
    ];

    final safeIndex = selectedIndex >= sections.length ? 0 : selectedIndex;
    return _AdminDashboardShell(
      title: 'Store manager',
      userEmail: userEmail,
      sections: sections,
      selectedIndex: safeIndex,
      onSectionChanged: onSectionChanged,
    );
  }
}

class _StoreManagerHeader extends StatelessWidget {
  const _StoreManagerHeader({
    required this.userEmail,
    required this.stores,
    required this.selectedStoreId,
    required this.onStoreChanged,
    this.selectedStore,
  });

  final String userEmail;
  final List<StoreSummary> stores;
  final StoreSummary? selectedStore;
  final String selectedStoreId;
  final ValueChanged<String?>? onStoreChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                avatar: Icon(
                  selectedStore?.isOpen == true
                      ? Icons.storefront
                      : Icons.storefront_outlined,
                  size: 18,
                ),
                label: Text(selectedStore?.isOpen == true ? 'Open' : 'Closed'),
              ),
              Chip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: Text(userEmail),
              ),
              if (selectedStore?.address.trim().isNotEmpty == true)
                Chip(
                  avatar: const Icon(Icons.place_outlined, size: 18),
                  label: Text(selectedStore!.address),
                ),
            ],
          ),
        ),
        if (stores.length > 1) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String>(
              initialValue: selectedStoreId,
              decoration: const InputDecoration(
                labelText: 'Store',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final store in stores)
                  DropdownMenuItem(value: store.id, child: Text(store.name)),
              ],
              onChanged: onStoreChanged,
            ),
          ),
        ],
      ],
    );
  }
}

class _StoreStaffActivityPanel extends StatelessWidget {
  const _StoreStaffActivityPanel({
    required this.staffPresence,
    required this.staffActivities,
  });

  final List<StoreStaffPresence> staffPresence;
  final List<StoreEmployeeActivity> staffActivities;

  @override
  Widget build(BuildContext context) {
    final activeStaff =
        staffPresence.where((presence) => presence.isActive).length;
    final orderActions = staffActivities
        .where((activity) => activity.entityType == 'order')
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final presenceCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Staff presence',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Chip(label: Text('$activeStaff active')),
                  ],
                ),
                const SizedBox(height: 8),
                if (staffPresence.isEmpty)
                  const Text('No staff presence has been recorded yet.')
                else
                  for (final presence in staffPresence.take(12))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Icon(
                          presence.isActive
                              ? Icons.badge
                              : Icons.badge_outlined,
                        ),
                      ),
                      title: Text(presence.staffName),
                      subtitle: Text(
                        [
                          if (presence.staffRole != null) presence.staffRole!,
                          if (presence.staffEmail != null) presence.staffEmail!,
                          'Last seen ${_formatDateTime(presence.lastSeenAt)}',
                        ].join(' | '),
                      ),
                      trailing: Chip(
                        label: Text(presence.isActive ? 'Active' : 'Idle'),
                      ),
                    ),
              ],
            ),
          ),
        );

        final activityCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Activity log',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Chip(label: Text('$orderActions order actions')),
                  ],
                ),
                const SizedBox(height: 8),
                if (staffActivities.isEmpty)
                  const Text('No staff activity has been recorded yet.')
                else
                  for (final activity in staffActivities.take(16))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_activityIcon(activity.entityType)),
                      title: Text(
                        activity.summary.isEmpty
                            ? _humanStatus(activity.action)
                            : activity.summary,
                      ),
                      subtitle: Text(
                        [
                          activity.actorName ?? 'Store staff',
                          _humanStatus(activity.entityType),
                          _formatDateTime(activity.createdAt),
                        ].join(' | '),
                      ),
                    ),
              ],
            ),
          ),
        );

        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              presenceCard,
              const SizedBox(height: 12),
              activityCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: presenceCard),
            const SizedBox(width: 12),
            Expanded(child: activityCard),
          ],
        );
      },
    );
  }
}

class _StoreHoursPanel extends StatelessWidget {
  const _StoreHoursPanel({
    required this.repository,
    required this.storeId,
    required this.hours,
    required this.canManage,
  });

  final PlatformRepository repository;
  final String storeId;
  final List<StoreOpeningHour> hours;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final byDay = {for (final hour in hours) hour.dayOfWeek: hour};

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
                    'Opening hours',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('${hours.length}/7 configured')),
              ],
            ),
            const SizedBox(height: 8),
            for (var day = 0; day < 7; day += 1)
              _StoreHourTile(
                repository: repository,
                storeId: storeId,
                dayOfWeek: day,
                hour: byDay[day],
                canManage: canManage,
              ),
          ],
        ),
      ),
    );
  }
}

class _StoreHourTile extends StatelessWidget {
  const _StoreHourTile({
    required this.repository,
    required this.storeId,
    required this.dayOfWeek,
    required this.canManage,
    this.hour,
  });

  final PlatformRepository repository;
  final String storeId;
  final int dayOfWeek;
  final StoreOpeningHour? hour;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final isClosed = hour?.isClosed ?? true;
    final opensAt = _timeText(hour?.opensAt);
    final closesAt = _timeText(hour?.closesAt);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(isClosed ? Icons.lock_clock : Icons.schedule),
      title: Text(_weekdayName(dayOfWeek)),
      subtitle: Text(isClosed ? 'Closed' : '$opensAt - $closesAt'),
      trailing: IconButton(
        tooltip: 'Edit hours',
        onPressed: canManage
            ? () => _showStoreHourDialog(
                  context,
                  repository: repository,
                  storeId: storeId,
                  dayOfWeek: dayOfWeek,
                  hour: hour,
                )
            : null,
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

class _StoreManagerRevenuePanel extends StatefulWidget {
  const _StoreManagerRevenuePanel({
    required this.orders,
    required this.settlements,
  });

  final List<OrderSummary> orders;
  final List<StoreSettlementSummary> settlements;

  @override
  State<_StoreManagerRevenuePanel> createState() =>
      _StoreManagerRevenuePanelState();
}

class _StoreManagerRevenuePanelState extends State<_StoreManagerRevenuePanel> {
  var _page = 0;

  @override
  Widget build(BuildContext context) {
    final paidOrders =
        widget.orders.where((order) => order.paymentStatus == 'paid').toList();
    final revenue =
        paidOrders.fold<double>(0, (total, order) => total + order.totalAmount);
    final serviceFees =
        paidOrders.fold<double>(0, (total, order) => total + order.serviceFee);
    final payout = paidOrders.fold<double>(
        0, (total, order) => total + order.storePayoutAmount);
    final pendingSettlements = widget.settlements
        .where((settlement) => settlement.status == 'pending');
    final pendingPayout = pendingSettlements.fold<double>(
      0,
      (total, settlement) => total + settlement.payoutAmount,
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
            _MetricCard(label: 'Paid revenue', value: _formatNaira(revenue)),
            _MetricCard(
                label: 'Service fees', value: _formatNaira(serviceFees)),
            _MetricCard(label: 'Store split', value: _formatNaira(payout)),
            _MetricCard(
              label: 'Pending split',
              value: _formatNaira(pendingPayout),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AdminRevenueChart(
          title: 'Revenue trend',
          orders: widget.orders,
          valueForOrder: (order) =>
              order.paymentStatus == 'paid' ? order.totalAmount : 0,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Store split records',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (widget.settlements.isEmpty)
                  const Text('No store split records yet.')
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
                        'Order #${_shortId(settlement.orderId)} | ${_formatNaira(settlement.payoutAmount)}',
                      ),
                      subtitle: Text(
                        '${_humanStatus(settlement.status)} | '
                        'Items ${_formatNaira(settlement.grossItemsAmount)} | '
                        'Discount ${_formatNaira(settlement.discountAmount)} | '
                        '${_formatDateTime(settlement.updatedAt)}',
                      ),
                      trailing: settlement.paidAt == null
                          ? null
                          : Text(_formatDateTime(settlement.paidAt!)),
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

class _OwnerOrderOpsPanel extends StatelessWidget {
  const _OwnerOrderOpsPanel({
    required this.repository,
    required this.orders,
    required this.canManageOrders,
  });

  final PlatformRepository repository;
  final List<OrderSummary> orders;
  final bool canManageOrders;

  @override
  Widget build(BuildContext context) {
    final visible = orders.where((order) {
      return order.paymentStatus == 'paid' &&
          order.status != 'delivered' &&
          order.status != 'cancelled';
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Order operations',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (!canManageOrders) ...[
              const Text(
                  'This staff account can view orders but cannot accept or pack them.'),
              const SizedBox(height: 8),
            ],
            if (visible.isEmpty)
              const Text('No active paid orders.')
            else
              for (final order in visible.take(10))
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.receipt_long_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Order #${_shortId(order.id)}',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_humanStatus(order.status)} | ${_formatNaira(order.totalAmount)}\n'
                                    '${_contactText(name: order.customerName, phone: order.customerPhone, fallback: 'Customer')}',
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
                          children: [
                            FilledButton.tonalIcon(
                              onPressed:
                                  canManageOrders && order.status == 'paid'
                                      ? () => repository.updateStoreOrderStatus(
                                            orderId: order.id,
                                            status: 'accepted',
                                          )
                                      : null,
                              icon: const Icon(Icons.task_alt_outlined),
                              label: const Text('Accept'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: canManageOrders &&
                                      (order.status == 'accepted' ||
                                          order.status == 'preparing')
                                  ? () => repository.updateStoreOrderStatus(
                                        orderId: order.id,
                                        status: 'ready_for_pickup',
                                        note: 'Packed for rider pickup',
                                      )
                                  : null,
                              icon: const Icon(Icons.shopping_bag_outlined),
                              label: const Text('Packed'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _OwnerInventoryPanel extends StatelessWidget {
  const _OwnerInventoryPanel({
    required this.repository,
    required this.storeId,
    required this.inventory,
    required this.canManageInventory,
  });

  final PlatformRepository repository;
  final String storeId;
  final List<StoreInventoryItem> inventory;
  final bool canManageInventory;

  @override
  Widget build(BuildContext context) {
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
                    'Inventory oversight',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: canManageInventory
                      ? () => _showOwnerCreateProductDialog(
                            context,
                            repository: repository,
                            storeId: storeId,
                          )
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add product'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!canManageInventory) ...[
              const Text(
                  'This staff account can view inventory but cannot upload or edit it.'),
              const SizedBox(height: 8),
            ],
            if (inventory.isEmpty)
              const Text(
                  'Inventory uploads and edits will appear after products are added.')
            else
              for (final item in inventory.take(12))
                ListTile(
                  leading: Icon(
                    item.quantityAvailable <= item.reorderLevel
                        ? Icons.warning_amber_outlined
                        : Icons.inventory_2_outlined,
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    'Available ${item.quantityAvailable} | On hand ${item.quantityOnHand} | Reserved ${item.quantityReserved}',
                  ),
                  trailing: Chip(
                    label: Text(
                      item.storeMarkedAvailable ? 'Available' : 'Unavailable',
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showOwnerCreateProductDialog(
  BuildContext context, {
  required PlatformRepository repository,
  required String storeId,
}) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final categoryController = TextEditingController(text: 'general');
  final priceController = TextEditingController();
  final stockController = TextEditingController(text: '10');
  final reorderController = TextEditingController(text: '5');
  final skuController = TextEditingController();
  final imageUrlController = TextEditingController();
  var isSubmitting = false;

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add inventory product'),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Name'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Enter a product name'
                                  : null,
                        ),
                        TextFormField(
                          controller: descriptionController,
                          decoration:
                              const InputDecoration(labelText: 'Description'),
                        ),
                        TextFormField(
                          controller: categoryController,
                          decoration:
                              const InputDecoration(labelText: 'Category'),
                        ),
                        TextFormField(
                          controller: priceController,
                          decoration: const InputDecoration(labelText: 'Price'),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final parsed = double.tryParse(value?.trim() ?? '');
                            return parsed == null || parsed <= 0
                                ? 'Enter a valid price'
                                : null;
                          },
                        ),
                        TextFormField(
                          controller: stockController,
                          decoration:
                              const InputDecoration(labelText: 'Opening stock'),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final parsed = int.tryParse(value?.trim() ?? '');
                            return parsed == null || parsed < 0
                                ? 'Enter valid stock'
                                : null;
                          },
                        ),
                        TextFormField(
                          controller: reorderController,
                          decoration:
                              const InputDecoration(labelText: 'Reorder level'),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final parsed = int.tryParse(value?.trim() ?? '');
                            return parsed == null || parsed < 0
                                ? 'Enter a valid reorder level'
                                : null;
                          },
                        ),
                        TextFormField(
                          controller: skuController,
                          decoration: const InputDecoration(labelText: 'SKU'),
                        ),
                        TextFormField(
                          controller: imageUrlController,
                          decoration:
                              const InputDecoration(labelText: 'Image URL'),
                        ),
                      ],
                    ),
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
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          setDialogState(() => isSubmitting = true);
                          try {
                            await repository.createProduct(
                              storeId: storeId,
                              name: nameController.text.trim(),
                              description: descriptionController.text.trim(),
                              category: categoryController.text.trim().isEmpty
                                  ? 'general'
                                  : categoryController.text.trim(),
                              price: double.parse(priceController.text.trim()),
                              initialStock:
                                  int.parse(stockController.text.trim()),
                              reorderLevel:
                                  int.parse(reorderController.text.trim()),
                              sku: skuController.text.trim().isEmpty
                                  ? null
                                  : skuController.text.trim(),
                              imageUrl: imageUrlController.text.trim().isEmpty
                                  ? null
                                  : imageUrlController.text.trim(),
                            );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Product uploaded'),
                                ),
                              );
                            }
                          } on Object catch (error) {
                            setDialogState(() => isSubmitting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('Product upload failed: $error'),
                                ),
                              );
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    nameController.dispose();
    descriptionController.dispose();
    categoryController.dispose();
    priceController.dispose();
    stockController.dispose();
    reorderController.dispose();
    skuController.dispose();
    imageUrlController.dispose();
  }
}
