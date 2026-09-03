part of '../../main.dart';

class _AssignedOrdersPane extends StatefulWidget {
  const _AssignedOrdersPane({
    required this.repository,
    required this.onUpdateEta,
    required this.onOutForDelivery,
    required this.onDelivered,
    required this.onShareLocation,
    required this.onToggleLiveLocation,
    required this.onNavigate,
    required this.onCallCustomer,
    required this.onMessageCustomer,
    required this.liveLocationOrderId,
    required this.sharingLocationOrderIds,
  });

  final PlatformRepository repository;
  final ValueChanged<OrderSummary> onUpdateEta;
  final ValueChanged<OrderSummary> onOutForDelivery;
  final ValueChanged<OrderSummary> onDelivered;
  final ValueChanged<OrderSummary> onShareLocation;
  final ValueChanged<OrderSummary> onToggleLiveLocation;
  final void Function(OrderSummary order, _RiderRouteTarget target) onNavigate;
  final ValueChanged<OrderSummary> onCallCustomer;
  final ValueChanged<OrderSummary> onMessageCustomer;
  final String? liveLocationOrderId;
  final Set<String> sharingLocationOrderIds;

  @override
  State<_AssignedOrdersPane> createState() => _AssignedOrdersPaneState();
}

class _AssignedOrdersPaneState extends State<_AssignedOrdersPane> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderSummary>>(
      stream: widget.repository.watchMyRiderOrders(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Assigned orders failed to load',
            message: '${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _InlineState(
            title: 'Loading assigned orders',
            message: 'Fetching your deliveries...',
            isLoading: true,
          );
        }

        final orders = snapshot.data ?? const <OrderSummary>[];
        final activeOrders = orders.where(_isActiveRiderOrder).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            Text(
              'Active delivery',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _RiderWorkSummary(orders: orders),
            const SizedBox(height: 12),
            if (activeOrders.isEmpty)
              const _InlineState(
                title: 'No active delivery',
                message:
                    'Accepted orders will appear here with pickup and drop-off actions.',
              )
            else
              for (final order in activeOrders) ...[
                _ActiveDeliveryCard(
                  repository: widget.repository,
                  order: order,
                  isSharingLocation:
                      widget.sharingLocationOrderIds.contains(order.id),
                  isLiveLocation: widget.liveLocationOrderId == order.id,
                  onUpdateEta: () => widget.onUpdateEta(order),
                  onShareLocation: () => widget.onShareLocation(order),
                  onToggleLiveLocation: () =>
                      widget.onToggleLiveLocation(order),
                  onNavigateToStore: () =>
                      widget.onNavigate(order, _RiderRouteTarget.store),
                  onNavigateToCustomer: () =>
                      widget.onNavigate(order, _RiderRouteTarget.customer),
                  onCallCustomer: () => widget.onCallCustomer(order),
                  onMessageCustomer: () => widget.onMessageCustomer(order),
                  onConfirmPickup: () => widget.onOutForDelivery(order),
                  onConfirmDropOff: () => widget.onDelivered(order),
                ),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }
}

class _RiderOrdersPane extends StatefulWidget {
  const _RiderOrdersPane({
    required this.repository,
    required this.onUpdateEta,
    required this.onOutForDelivery,
    required this.onDelivered,
    required this.onShareLocation,
    required this.onToggleLiveLocation,
    required this.onNavigate,
    required this.onCallCustomer,
    required this.onMessageCustomer,
    required this.liveLocationOrderId,
    required this.sharingLocationOrderIds,
  });

  final PlatformRepository repository;
  final ValueChanged<OrderSummary> onUpdateEta;
  final ValueChanged<OrderSummary> onOutForDelivery;
  final ValueChanged<OrderSummary> onDelivered;
  final ValueChanged<OrderSummary> onShareLocation;
  final ValueChanged<OrderSummary> onToggleLiveLocation;
  final void Function(OrderSummary order, _RiderRouteTarget target) onNavigate;
  final ValueChanged<OrderSummary> onCallCustomer;
  final ValueChanged<OrderSummary> onMessageCustomer;
  final String? liveLocationOrderId;
  final Set<String> sharingLocationOrderIds;

  @override
  State<_RiderOrdersPane> createState() => _RiderOrdersPaneState();
}

class _RiderOrdersPaneState extends State<_RiderOrdersPane> {
  final _searchController = TextEditingController();
  var _showActive = true;
  var _filter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderSummary>>(
      stream: widget.repository.watchMyRiderOrders(),
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
            message: 'Fetching your delivery history...',
            isLoading: true,
          );
        }

        final orders = snapshot.data ?? const <OrderSummary>[];
        final visibleOrders = _filteredOrders(orders)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            Text('Orders', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _RiderWorkSummary(orders: orders),
            const SizedBox(height: 12),
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
                labelText: 'Search orders, customer, store, or address',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.delivery_dining_outlined),
                  label: Text('Active'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.history),
                  label: Text('Finished'),
                ),
              ],
              selected: {_showActive},
              onSelectionChanged: (selection) {
                setState(() {
                  _showActive = selection.first;
                  _filter = 'all';
                });
              },
            ),
            const SizedBox(height: 8),
            _RiderOrderFilters(
              selected: _filter,
              showActive: _showActive,
              onSelected: (value) => setState(() => _filter = value),
            ),
            const SizedBox(height: 12),
            if (orders.isEmpty)
              const Text('Orders you accept will appear here.')
            else if (visibleOrders.isEmpty)
              Text(
                _showActive
                    ? 'No ${_riderFilterLabel(_filter).toLowerCase()} active orders'
                    : 'No ${_riderFilterLabel(_filter).toLowerCase()} finished orders',
              )
            else if (_showActive)
              for (final order in visibleOrders) ...[
                _ActiveDeliveryCard(
                  repository: widget.repository,
                  order: order,
                  isSharingLocation:
                      widget.sharingLocationOrderIds.contains(order.id),
                  isLiveLocation: widget.liveLocationOrderId == order.id,
                  onUpdateEta: () => widget.onUpdateEta(order),
                  onShareLocation: () => widget.onShareLocation(order),
                  onToggleLiveLocation: () =>
                      widget.onToggleLiveLocation(order),
                  onNavigateToStore: () =>
                      widget.onNavigate(order, _RiderRouteTarget.store),
                  onNavigateToCustomer: () =>
                      widget.onNavigate(order, _RiderRouteTarget.customer),
                  onCallCustomer: () => widget.onCallCustomer(order),
                  onMessageCustomer: () => widget.onMessageCustomer(order),
                  onConfirmPickup: () => widget.onOutForDelivery(order),
                  onConfirmDropOff: () => widget.onDelivered(order),
                ),
                const SizedBox(height: 12),
              ]
            else
              for (final order in visibleOrders)
                _RiderFinishedOrderTile(order: order),
          ],
        );
      },
    );
  }

  List<OrderSummary> _filteredOrders(List<OrderSummary> orders) {
    return orders.where((order) {
      final matchesSegment = _showActive
          ? _isActiveRiderOrder(order)
          : _isFinishedRiderOrder(order);
      return matchesSegment &&
          _riderOrderMatchesFilter(order, _filter) &&
          _matchesRiderOrderSearch(order, _searchController.text);
    }).toList();
  }
}

class _RiderOrderFilters extends StatelessWidget {
  const _RiderOrderFilters({
    required this.selected,
    required this.showActive,
    required this.onSelected,
  });

  final String selected;
  final bool showActive;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final filters = showActive
        ? const [
            _RiderOrderFilter('all', 'All active', Icons.list),
            _RiderOrderFilter('ready_for_pickup', 'Pickup', Icons.storefront),
            _RiderOrderFilter(
              'out_for_delivery',
              'Drop-off',
              Icons.delivery_dining_outlined,
            ),
          ]
        : const [
            _RiderOrderFilter('all', 'All finished', Icons.history),
            _RiderOrderFilter('delivered', 'Fulfilled', Icons.done_all),
            _RiderOrderFilter('cancelled', 'Cancelled', Icons.cancel_outlined),
            _RiderOrderFilter('expired', 'Expired', Icons.timer_off_outlined),
            _RiderOrderFilter('declined', 'Declined', Icons.block_outlined),
            _RiderOrderFilter('failed', 'Failed payment', Icons.error_outline),
          ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in filters)
          ChoiceChip(
            avatar: Icon(filter.icon, size: 18),
            label: Text(filter.label),
            selected: selected == filter.value,
            onSelected: (_) => onSelected(filter.value),
          ),
      ],
    );
  }
}

class _RiderOrderFilter {
  const _RiderOrderFilter(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}

class _RiderFinishedOrderTile extends StatelessWidget {
  const _RiderFinishedOrderTile({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    final statusColor = order.status == 'delivered'
        ? const Color(0xff047857)
        : order.status == 'cancelled'
            ? const Color(0xffb91c1c)
            : Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.receipt_long_outlined, color: statusColor),
        title: Text('${_numericOrderCode(order.id)} | ${order.storeName}'),
        subtitle: Text(
          '${_customerName(order)} | ${_formatDateTime(order.updatedAt)}\n'
          '${_humanStatus(order.status)} | ${order.deliveryAddress}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatRiderRevenue(order.riderPayoutAmount),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              _humanStatus(order.paymentStatus),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
