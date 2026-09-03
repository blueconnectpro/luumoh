part of '../../main.dart';

class _RiderLifecyclePane extends StatelessWidget {
  const _RiderLifecyclePane({
    required this.repository,
    required this.hasMapboxToken,
    required this.isOnline,
    required this.isAvailabilityLoading,
    required this.isAvailabilitySubmitting,
    required this.onAvailabilityChanged,
    required this.onAccept,
    required this.onDecline,
    required this.onUpdateEta,
    required this.onConfirmPickup,
    required this.onConfirmDropOff,
    required this.onShareLocation,
    required this.onToggleLiveLocation,
    required this.onNavigate,
    required this.onCallCustomer,
    required this.onMessageCustomer,
    required this.onOpenMenu,
    required this.liveLocationOrderId,
    required this.sharingLocationOrderIds,
  });

  final PlatformRepository repository;
  final bool hasMapboxToken;
  final bool isOnline;
  final bool isAvailabilityLoading;
  final bool isAvailabilitySubmitting;
  final ValueChanged<bool> onAvailabilityChanged;
  final ValueChanged<OrderSummary> onAccept;
  final ValueChanged<OrderSummary> onDecline;
  final ValueChanged<OrderSummary> onUpdateEta;
  final ValueChanged<OrderSummary> onConfirmPickup;
  final ValueChanged<OrderSummary> onConfirmDropOff;
  final ValueChanged<OrderSummary> onShareLocation;
  final ValueChanged<OrderSummary> onToggleLiveLocation;
  final void Function(OrderSummary order, _RiderRouteTarget target) onNavigate;
  final ValueChanged<OrderSummary> onCallCustomer;
  final ValueChanged<OrderSummary> onMessageCustomer;
  final VoidCallback onOpenMenu;
  final String? liveLocationOrderId;
  final Set<String> sharingLocationOrderIds;

  @override
  Widget build(BuildContext context) {
    if (isAvailabilityLoading) {
      return _RiderIdleMapStage(
        isOnline: isOnline,
        isLoading: true,
        isSubmitting: isAvailabilitySubmitting,
        hasMapboxToken: hasMapboxToken,
        onAvailabilityChanged: onAvailabilityChanged,
        onOpenMenu: onOpenMenu,
        title: 'Checking rider status',
        message: 'Loading your availability...',
      );
    }

    if (!isOnline) {
      return _RiderIdleMapStage(
        isOnline: false,
        isLoading: false,
        isSubmitting: isAvailabilitySubmitting,
        hasMapboxToken: hasMapboxToken,
        onAvailabilityChanged: onAvailabilityChanged,
        onOpenMenu: onOpenMenu,
        title: 'You are offline',
        message:
            'Tap the status pill above to go online and receive pickup offers.',
      );
    }

    return StreamBuilder<List<OrderSummary>>(
      stream: repository.watchMyRiderOrders(),
      builder: (context, assignedSnapshot) {
        if (assignedSnapshot.hasError) {
          return _InlineState(
            title: 'Assigned orders failed to load',
            message: '${assignedSnapshot.error}',
          );
        }

        final assignedOrders = assignedSnapshot.data ?? const <OrderSummary>[];
        final activeOrders = assignedOrders.where(_isActiveRiderOrder).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (activeOrders.isNotEmpty) {
          final order = activeOrders.first;
          return _RiderActiveLifecycleScreen(
            repository: repository,
            order: order,
            isSharingLocation: sharingLocationOrderIds.contains(order.id),
            isLiveLocation: liveLocationOrderId == order.id,
            onUpdateEta: () => onUpdateEta(order),
            onConfirmPickup: () => onConfirmPickup(order),
            onConfirmDropOff: () => onConfirmDropOff(order),
            onShareLocation: () => onShareLocation(order),
            onToggleLiveLocation: () => onToggleLiveLocation(order),
            onNavigateToStore: () => onNavigate(order, _RiderRouteTarget.store),
            onNavigateToCustomer: () =>
                onNavigate(order, _RiderRouteTarget.customer),
            onCallCustomer: () => onCallCustomer(order),
            onMessageCustomer: () => onMessageCustomer(order),
            onOpenMenu: onOpenMenu,
            isOnline: isOnline,
            isAvailabilitySubmitting: isAvailabilitySubmitting,
            hasMapboxToken: hasMapboxToken,
            onAvailabilityChanged: onAvailabilityChanged,
          );
        }

        if (assignedSnapshot.connectionState == ConnectionState.waiting) {
          return _RiderIdleMapStage(
            isOnline: isOnline,
            isLoading: true,
            isSubmitting: isAvailabilitySubmitting,
            hasMapboxToken: hasMapboxToken,
            onAvailabilityChanged: onAvailabilityChanged,
            onOpenMenu: onOpenMenu,
            title: 'Loading rider home',
            message: 'Checking for active deliveries...',
          );
        }

        return StreamBuilder<List<OrderSummary>>(
          stream: repository.watchAvailableRiderOrders(),
          builder: (context, offerSnapshot) {
            if (offerSnapshot.hasError) {
              return _InlineState(
                title: 'Pickups failed to load',
                message:
                    '${offerSnapshot.error}\n\nMake sure this account has the rider role.',
              );
            }

            if (offerSnapshot.connectionState == ConnectionState.waiting) {
              return _RiderIdleMapStage(
                isOnline: isOnline,
                isLoading: true,
                isSubmitting: isAvailabilitySubmitting,
                hasMapboxToken: hasMapboxToken,
                onAvailabilityChanged: onAvailabilityChanged,
                onOpenMenu: onOpenMenu,
                title: 'Loading pickups',
                message: 'Fetching orders ready for pickup...',
              );
            }

            final offers = offerSnapshot.data ?? const <OrderSummary>[];
            if (offers.isEmpty) {
              return _RiderIdleMapStage(
                isOnline: isOnline,
                isLoading: false,
                isSubmitting: isAvailabilitySubmitting,
                hasMapboxToken: hasMapboxToken,
                onAvailabilityChanged: onAvailabilityChanged,
                onOpenMenu: onOpenMenu,
                title: 'No new orders',
                message:
                    'Pickup-ready delivery orders will appear here as soon as stores mark them ready.',
              );
            }

            final order = offers.first;
            return _RiderOfferScreen(
              repository: repository,
              order: order,
              offerCount: offers.length,
              onAccept: () => onAccept(order),
              onDecline: () => onDecline(order),
              onNavigateToStore: () => onNavigate(
                order,
                _RiderRouteTarget.store,
              ),
              onOpenMenu: onOpenMenu,
              isOnline: isOnline,
              isAvailabilitySubmitting: isAvailabilitySubmitting,
              hasMapboxToken: hasMapboxToken,
              onAvailabilityChanged: onAvailabilityChanged,
            );
          },
        );
      },
    );
  }
}

class _RiderOfferScreen extends StatelessWidget {
  const _RiderOfferScreen({
    required this.repository,
    required this.order,
    required this.offerCount,
    required this.onAccept,
    required this.onDecline,
    required this.onNavigateToStore,
    required this.onOpenMenu,
    required this.isOnline,
    required this.isAvailabilitySubmitting,
    required this.hasMapboxToken,
    required this.onAvailabilityChanged,
  });

  final PlatformRepository repository;
  final OrderSummary order;
  final int offerCount;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onNavigateToStore;
  final VoidCallback onOpenMenu;
  final bool isOnline;
  final bool isAvailabilitySubmitting;
  final bool hasMapboxToken;
  final ValueChanged<bool> onAvailabilityChanged;

  @override
  Widget build(BuildContext context) {
    final distanceLabel = order.deliveryDistanceKm > 0
        ? '${order.deliveryDistanceKm.toStringAsFixed(1)} km'
        : 'Route pending';
    final payout = order.riderPayoutAmount > 0
        ? _formatRiderRevenue(order.riderPayoutAmount)
        : _formatRiderRevenue(order.deliveryFee);

    return _RiderMapStage(
      target: _RiderRouteTarget.store,
      order: order,
      showBothStops: true,
      onOpenMenu: onOpenMenu,
      isOnline: isOnline,
      isAvailabilitySubmitting: isAvailabilitySubmitting,
      hasMapboxToken: hasMapboxToken,
      onAvailabilityChanged: onAvailabilityChanged,
      sheet: _RiderBottomSheetSurface(
        maxWidth: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(
                '$payout ($distanceLabel)',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: const Color(0xff16a34a),
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const _SoftLabel(text: 'cash needed'),
                if (offerCount > 1) _SoftLabel(text: '$offerCount offers'),
                _SoftLabel(text: '${order.etaMinutes ?? 20} min ETA'),
              ],
            ),
            const SizedBox(height: 16),
            _RouteStopLine(
              icon: Icons.storefront_outlined,
              title: order.storeName,
              subtitle: _storeAddress(order),
            ),
            const SizedBox(height: 10),
            _RouteStopLine(
              icon: Icons.person_pin_circle_outlined,
              title: _customerName(order),
              subtitle: order.deliveryAddress.isEmpty
                  ? 'Customer address pending'
                  : order.deliveryAddress,
            ),
            const SizedBox(height: 12),
            _OrderItemsCountLine(
              repository: repository,
              orderId: order.id,
              trailing: IconButton(
                tooltip: 'Navigate to store',
                icon: const Icon(Icons.navigation_outlined),
                onPressed: onNavigateToStore,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _LifecycleActionButton(
                    label: 'Decline',
                    color: const Color(0xffdc2626),
                    icon: Icons.close,
                    onPressed: onDecline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LifecycleActionButton(
                    label: 'Accept',
                    color: const Color(0xff16a34a),
                    icon: Icons.check,
                    onPressed: onAccept,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderActiveLifecycleScreen extends StatelessWidget {
  const _RiderActiveLifecycleScreen({
    required this.repository,
    required this.order,
    required this.isSharingLocation,
    required this.isLiveLocation,
    required this.onUpdateEta,
    required this.onConfirmPickup,
    required this.onConfirmDropOff,
    required this.onShareLocation,
    required this.onToggleLiveLocation,
    required this.onNavigateToStore,
    required this.onNavigateToCustomer,
    required this.onCallCustomer,
    required this.onMessageCustomer,
    required this.onOpenMenu,
    required this.isOnline,
    required this.isAvailabilitySubmitting,
    required this.hasMapboxToken,
    required this.onAvailabilityChanged,
  });

  final PlatformRepository repository;
  final OrderSummary order;
  final bool isSharingLocation;
  final bool isLiveLocation;
  final VoidCallback onUpdateEta;
  final VoidCallback onConfirmPickup;
  final VoidCallback onConfirmDropOff;
  final VoidCallback onShareLocation;
  final VoidCallback onToggleLiveLocation;
  final VoidCallback onNavigateToStore;
  final VoidCallback onNavigateToCustomer;
  final VoidCallback onCallCustomer;
  final VoidCallback onMessageCustomer;
  final VoidCallback onOpenMenu;
  final bool isOnline;
  final bool isAvailabilitySubmitting;
  final bool hasMapboxToken;
  final ValueChanged<bool> onAvailabilityChanged;

  @override
  Widget build(BuildContext context) {
    final headingToStore = order.status == 'ready_for_pickup' ||
        order.status == 'accepted' ||
        order.status == 'preparing';
    final target =
        headingToStore ? _RiderRouteTarget.store : _RiderRouteTarget.customer;

    return _RiderMapStage(
      target: target,
      order: order,
      showBothStops: false,
      onOpenMenu: onOpenMenu,
      isOnline: isOnline,
      isAvailabilitySubmitting: isAvailabilitySubmitting,
      hasMapboxToken: hasMapboxToken,
      onAvailabilityChanged: onAvailabilityChanged,
      sheet: headingToStore
          ? _PickupLifecycleSheet(
              repository: repository,
              order: order,
              isSharingLocation: isSharingLocation,
              isLiveLocation: isLiveLocation,
              onUpdateEta: onUpdateEta,
              onConfirmPickup: onConfirmPickup,
              onShareLocation: onShareLocation,
              onToggleLiveLocation: onToggleLiveLocation,
              onNavigateToStore: onNavigateToStore,
            )
          : _DropOffLifecycleSheet(
              repository: repository,
              order: order,
              isSharingLocation: isSharingLocation,
              isLiveLocation: isLiveLocation,
              onConfirmDropOff: onConfirmDropOff,
              onShareLocation: onShareLocation,
              onToggleLiveLocation: onToggleLiveLocation,
              onNavigateToCustomer: onNavigateToCustomer,
              onCallCustomer: onCallCustomer,
              onMessageCustomer: onMessageCustomer,
            ),
    );
  }
}

class _PickupLifecycleSheet extends StatelessWidget {
  const _PickupLifecycleSheet({
    required this.repository,
    required this.order,
    required this.isSharingLocation,
    required this.isLiveLocation,
    required this.onUpdateEta,
    required this.onConfirmPickup,
    required this.onShareLocation,
    required this.onToggleLiveLocation,
    required this.onNavigateToStore,
  });

  final PlatformRepository repository;
  final OrderSummary order;
  final bool isSharingLocation;
  final bool isLiveLocation;
  final VoidCallback onUpdateEta;
  final VoidCallback onConfirmPickup;
  final VoidCallback onShareLocation;
  final VoidCallback onToggleLiveLocation;
  final VoidCallback onNavigateToStore;

  @override
  Widget build(BuildContext context) {
    return _RiderBottomSheetSurface(
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.storeName,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 2),
                    const Text('1 order'),
                    const SizedBox(height: 12),
                    Text(
                      _storeAddress(order),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              _RoundActionButton(
                tooltip: 'Navigate to store',
                icon: Icons.navigation_outlined,
                onPressed: onNavigateToStore,
              ),
            ],
          ),
          const Divider(height: 28),
          Text('Company: ${order.storeName}'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _SoftLabel(text: 'Check on the order', warm: true),
              _SoftLabel(text: order.fulfillmentType),
              _SoftLabel(
                  text: order.etaMinutes == null
                      ? 'ETA pending'
                      : 'ETA ${order.etaMinutes} min'),
            ],
          ),
          const SizedBox(height: 16),
          _PickupOrderCodeTile(order: order),
          const SizedBox(height: 12),
          _OrderIdentityRow(repository: repository, order: order),
          const SizedBox(height: 16),
          _OrderItemsExpandable(repository: repository, orderId: order.id),
          const Divider(height: 28),
          const _PaymentStatusBlock(label: 'No payment at pickup'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onUpdateEta,
                icon: const Icon(Icons.schedule),
                label: Text(order.etaMinutes == null
                    ? 'Set ETA'
                    : 'ETA ${order.etaMinutes}m'),
              ),
              OutlinedButton.icon(
                onPressed: isSharingLocation ? null : onShareLocation,
                icon: const Icon(Icons.my_location),
                label: Text(isSharingLocation ? 'Sharing...' : 'Share'),
              ),
              OutlinedButton.icon(
                onPressed: onToggleLiveLocation,
                icon: Icon(isLiveLocation
                    ? Icons.location_disabled_outlined
                    : Icons.location_searching),
                label: Text(isLiveLocation ? 'Stop live' : 'Live'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _LifecycleActionButton(
            label: 'Confirm pick-up',
            color: const Color(0xff16a34a),
            icon: Icons.inventory_2_outlined,
            onPressed: onConfirmPickup,
          ),
        ],
      ),
    );
  }
}

class _DropOffLifecycleSheet extends StatelessWidget {
  const _DropOffLifecycleSheet({
    required this.repository,
    required this.order,
    required this.isSharingLocation,
    required this.isLiveLocation,
    required this.onConfirmDropOff,
    required this.onShareLocation,
    required this.onToggleLiveLocation,
    required this.onNavigateToCustomer,
    required this.onCallCustomer,
    required this.onMessageCustomer,
  });

  final PlatformRepository repository;
  final OrderSummary order;
  final bool isSharingLocation;
  final bool isLiveLocation;
  final VoidCallback onConfirmDropOff;
  final VoidCallback onShareLocation;
  final VoidCallback onToggleLiveLocation;
  final VoidCallback onNavigateToCustomer;
  final VoidCallback onCallCustomer;
  final VoidCallback onMessageCustomer;

  @override
  Widget build(BuildContext context) {
    return _RiderBottomSheetSurface(
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _customerName(order),
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      order.deliveryAddress.isEmpty
                          ? 'Customer address pending'
                          : order.deliveryAddress,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              _RoundActionButton(
                tooltip: 'Call customer',
                icon: Icons.call_outlined,
                onPressed: onCallCustomer,
              ),
              const SizedBox(width: 8),
              _RoundActionButton(
                tooltip: 'Message customer',
                icon: Icons.chat_bubble_outline,
                onPressed: onMessageCustomer,
              ),
            ],
          ),
          const Divider(height: 28),
          Text(
            _numericOrderCode(order.id),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '#${_shortId(order.id)} | ${_customerName(order)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(
            order.storeName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          _OrderItemsExpandable(repository: repository, orderId: order.id),
          const Divider(height: 28),
          const _PaymentStatusBlock(label: 'Paid online'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onNavigateToCustomer,
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Navigate to customer'),
              ),
              OutlinedButton.icon(
                onPressed: isSharingLocation ? null : onShareLocation,
                icon: const Icon(Icons.my_location),
                label: Text(isSharingLocation ? 'Sharing...' : 'Share'),
              ),
              OutlinedButton.icon(
                onPressed: onToggleLiveLocation,
                icon: Icon(isLiveLocation
                    ? Icons.location_disabled_outlined
                    : Icons.location_searching),
                label: Text(isLiveLocation ? 'Stop live' : 'Live'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _LifecycleActionButton(
            label: 'Confirm drop-off',
            color: const Color(0xff16a34a),
            icon: Icons.done_all,
            onPressed: onConfirmDropOff,
          ),
        ],
      ),
    );
  }
}
