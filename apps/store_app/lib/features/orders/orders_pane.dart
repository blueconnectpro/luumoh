part of '../../main.dart';

class _OrdersPane extends StatefulWidget {
  const _OrdersPane({
    required this.repository,
    required this.storeId,
    required this.onStatusChanged,
    required this.onPreparationTimeChanged,
    required this.onModifyOrderItem,
    required this.onCancelOrder,
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

  @override
  State<_OrdersPane> createState() => _OrdersPaneState();
}

class _OrdersPaneState extends State<_OrdersPane> {
  final _searchController = TextEditingController();
  final Set<String> _seenNewOrderIds = {};
  var _primedNewOrderAlerts = false;
  var _scope = 'all';
  var _filter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderSummary>>(
      stream: widget.repository.watchStoreOrders(widget.storeId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Orders failed to load',
            message: '${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _InlineState(
            title: 'Loading orders',
            message: 'Fetching paid and active orders...',
            isLoading: true,
          );
        }

        final orders = snapshot.data ?? const <OrderSummary>[];
        _handleNewOrderAlerts(orders);
        final visibleOrders = _sortedStoreOrders(_filteredOrders(orders));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => setState(_searchController.clear),
                        icon: const Icon(Icons.close),
                      ),
                labelText: 'Search orders or address',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'all',
                  icon: Icon(Icons.all_inbox_outlined),
                  label: Text('All'),
                ),
                ButtonSegment(
                  value: 'active',
                  icon: Icon(Icons.local_shipping_outlined),
                  label: Text('Active'),
                ),
                ButtonSegment(
                  value: 'finished',
                  icon: Icon(Icons.history),
                  label: Text('Finished'),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (selection) {
                setState(() {
                  _scope = selection.first;
                  _filter = 'all';
                });
              },
            ),
            const SizedBox(height: 8),
            _OrderQueueFilters(
              selected: _filter,
              scope: _scope,
              onSelected: (value) => setState(() => _filter = value),
            ),
            const SizedBox(height: 12),
            if (orders.isEmpty) ...[
              const Text('No orders yet'),
            ] else if (visibleOrders.isEmpty) ...[
              Text(
                'No ${_filterLabel(_filter).toLowerCase()} ${_scope == 'all' ? 'orders' : '$_scope orders'}',
              ),
            ] else ...[
              _RecentOrdersByDate(
                repository: widget.repository,
                orders: visibleOrders,
                onStatusChanged: widget.onStatusChanged,
                onPreparationTimeChanged: widget.onPreparationTimeChanged,
                onModifyOrderItem: widget.onModifyOrderItem,
                onCancelOrder: widget.onCancelOrder,
              ),
            ],
          ],
        );
      },
    );
  }

  void _handleNewOrderAlerts(List<OrderSummary> orders) {
    final newOrders = orders
        .where(
            (order) => order.paymentStatus == 'paid' && order.status == 'paid')
        .toList();
    if (!_primedNewOrderAlerts) {
      _seenNewOrderIds.addAll(newOrders.map((order) => order.id));
      _primedNewOrderAlerts = true;
      return;
    }

    OrderSummary? orderToAlert;
    for (final order in newOrders) {
      if (!_seenNewOrderIds.contains(order.id)) {
        orderToAlert = order;
        break;
      }
    }
    if (orderToAlert == null) {
      return;
    }

    final alertOrder = orderToAlert;
    _seenNewOrderIds.add(alertOrder.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      SystemSound.play(SystemSoundType.alert);
      showDialog<void>(
        context: context,
        builder: (context) => _NewOrderDialog(
          repository: widget.repository,
          order: alertOrder,
          onAccept: () => widget.onStatusChanged(alertOrder, 'accepted'),
        ),
      );
    });
  }

  List<OrderSummary> _filteredOrders(List<OrderSummary> orders) {
    return orders.where((order) {
      final matchesSegment = switch (_scope) {
        'active' => _isActiveStoreOrder(order),
        'finished' => _isFinishedStoreOrder(order),
        _ => true,
      };
      final matchesFilter = switch (_filter) {
        'new' => order.status == 'paid',
        'accepted' => order.status == 'accepted',
        'preparing' => order.status == 'preparing',
        'ready' => order.status == 'ready_for_pickup',
        'out_for_delivery' => order.status == 'out_for_delivery',
        'fulfilled' => order.status == 'delivered',
        'cancelled' => order.status == 'cancelled',
        'expired' =>
          order.status == 'expired' || order.paymentStatus == 'expired',
        'failed' => order.paymentStatus == 'failed',
        'refunded' => order.paymentStatus == 'refunded',
        'all' => true,
        _ => true,
      };
      return matchesSegment &&
          matchesFilter &&
          _matchesStoreOrderSearch(
            order,
            _searchController.text,
          );
    }).toList();
  }
}

class _OrderQueueFilters extends StatelessWidget {
  const _OrderQueueFilters({
    required this.selected,
    required this.scope,
    required this.onSelected,
  });

  final String selected;
  final String scope;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final filters = scope == 'finished'
        ? const [
            _OrderFilter('all', 'All finished', Icons.history),
            _OrderFilter('fulfilled', 'Fulfilled', Icons.done_all),
            _OrderFilter('cancelled', 'Cancelled', Icons.cancel_outlined),
            _OrderFilter('expired', 'Expired', Icons.timer_off_outlined),
            _OrderFilter('failed', 'Failed payment', Icons.error_outline),
            _OrderFilter('refunded', 'Refunded', Icons.undo_outlined),
          ]
        : scope == 'active'
            ? const [
                _OrderFilter('all', 'All active', Icons.list),
                _OrderFilter('new', 'New', Icons.new_releases_outlined),
                _OrderFilter(
                    'accepted', 'Accepted', Icons.check_circle_outline),
                _OrderFilter('preparing', 'Preparing', Icons.restaurant),
                _OrderFilter('ready', 'Ready', Icons.inventory_2_outlined),
                _OrderFilter(
                  'out_for_delivery',
                  'With rider',
                  Icons.delivery_dining_outlined,
                ),
              ]
            : const [
                _OrderFilter('all', 'All orders', Icons.all_inbox_outlined),
                _OrderFilter('new', 'New', Icons.new_releases_outlined),
                _OrderFilter(
                    'accepted', 'Accepted', Icons.check_circle_outline),
                _OrderFilter('preparing', 'Preparing', Icons.restaurant),
                _OrderFilter('ready', 'Ready', Icons.inventory_2_outlined),
                _OrderFilter(
                  'out_for_delivery',
                  'With rider',
                  Icons.delivery_dining_outlined,
                ),
                _OrderFilter('fulfilled', 'Fulfilled', Icons.done_all),
                _OrderFilter('cancelled', 'Cancelled', Icons.cancel_outlined),
                _OrderFilter('expired', 'Expired', Icons.timer_off_outlined),
                _OrderFilter('failed', 'Failed payment', Icons.error_outline),
                _OrderFilter('refunded', 'Refunded', Icons.undo_outlined),
              ];
    final selectedFilter = filters.firstWhere(
      (filter) => filter.value == selected,
      orElse: () => filters.first,
    );
    final colors = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerRight,
      child: PopupMenuButton<String>(
        initialValue: selected,
        tooltip: 'Sort orders',
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final filter in filters)
            PopupMenuItem<String>(
              value: filter.value,
              child: Row(
                children: [
                  Icon(filter.icon, size: 19),
                  const SizedBox(width: 10),
                  Expanded(child: Text(filter.label)),
                  if (selected == filter.value)
                    Icon(Icons.check, color: colors.primary, size: 18),
                ],
              ),
            ),
        ],
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune, size: 19),
                const SizedBox(width: 8),
                Text(
                  selected == 'all' ? 'Sort' : selectedFilter.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, size: 19),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentOrdersByDate extends StatelessWidget {
  const _RecentOrdersByDate({
    required this.repository,
    required this.orders,
    required this.onStatusChanged,
    required this.onPreparationTimeChanged,
    required this.onModifyOrderItem,
    required this.onCancelOrder,
  });

  final PlatformRepository repository;
  final List<OrderSummary> orders;
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
    final groups = _groupOrdersByLocalDate(orders);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                _CountBadge(count: group.orders.length),
              ],
            ),
          ),
          for (final statusGroup in _groupOrdersByStoreStatus(group.orders))
            _OrderStatusSection(
              label: statusGroup.label,
              orders: statusGroup.orders,
              repository: repository,
              onStatusChanged: onStatusChanged,
              onPreparationTimeChanged: onPreparationTimeChanged,
              onModifyOrderItem: onModifyOrderItem,
              onCancelOrder: onCancelOrder,
            ),
        ],
      ],
    );
  }
}

class _OrderDateGroup {
  const _OrderDateGroup({
    required this.label,
    required this.orders,
  });

  final String label;
  final List<OrderSummary> orders;
}

class _OrderStatusGroup {
  const _OrderStatusGroup({
    required this.label,
    required this.orders,
  });

  final String label;
  final List<OrderSummary> orders;
}

class _OrderStatusSection extends StatelessWidget {
  const _OrderStatusSection({
    required this.label,
    required this.orders,
    required this.repository,
    required this.onStatusChanged,
    required this.onPreparationTimeChanged,
    required this.onModifyOrderItem,
    required this.onCancelOrder,
  });

  final String label;
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Row(
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(width: 8),
                _CountBadge(count: orders.length),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final cardWidth = width >= 820
                  ? (width - 24) / 3
                  : width >= 560
                      ? (width - 12) / 2
                      : width;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final order in orders)
                    SizedBox(
                      width: cardWidth,
                      child: _StoreOrderCard(
                        repository: repository,
                        order: order,
                        onStatusChanged: onStatusChanged,
                        onPreparationTimeChanged: onPreparationTimeChanged,
                        onModifyOrderItem: onModifyOrderItem,
                        onCancelOrder: onCancelOrder,
                      ),
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

class _OrderFilter {
  const _OrderFilter(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}
