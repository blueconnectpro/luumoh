part of '../../main.dart';

class _RiderMapStage extends StatelessWidget {
  const _RiderMapStage({
    required this.order,
    required this.target,
    required this.sheet,
    required this.onOpenMenu,
    required this.isOnline,
    required this.isAvailabilitySubmitting,
    required this.hasMapboxToken,
    required this.onAvailabilityChanged,
    this.showBothStops = false,
  });

  final OrderSummary order;
  final _RiderRouteTarget target;
  final Widget sheet;
  final VoidCallback onOpenMenu;
  final bool isOnline;
  final bool isAvailabilitySubmitting;
  final bool hasMapboxToken;
  final ValueChanged<bool> onAvailabilityChanged;
  final bool showBothStops;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _RiderRouteMap(
            order: order,
            target: target,
            height: MediaQuery.sizeOf(context).height,
            showBothStops: showBothStops,
            hasMapboxToken: hasMapboxToken,
            onOpenMenu: onOpenMenu,
            isOnline: isOnline,
            isAvailabilitySubmitting: isAvailabilitySubmitting,
            onAvailabilityChanged: onAvailabilityChanged,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: sheet,
        ),
      ],
    );
  }
}

class _RiderIdleMapStage extends StatelessWidget {
  const _RiderIdleMapStage({
    required this.isOnline,
    required this.isLoading,
    required this.isSubmitting,
    required this.hasMapboxToken,
    required this.onAvailabilityChanged,
    required this.onOpenMenu,
    required this.title,
    required this.message,
  });

  final bool isOnline;
  final bool isLoading;
  final bool isSubmitting;
  final bool hasMapboxToken;
  final ValueChanged<bool> onAvailabilityChanged;
  final VoidCallback onOpenMenu;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: _RiderMapboxMapBackground(
            enabled: hasMapboxToken,
            fallback: DecoratedBox(
              decoration:
                  BoxDecoration(color: colorScheme.surfaceContainerHighest),
              child: CustomPaint(painter: _RouteMapPainter(colorScheme)),
            ),
          ),
        ),
        Positioned(
          left: 30,
          top: 36,
          child: _MapCircleButton(
            icon: Icons.menu,
            onPressed: onOpenMenu,
          ),
        ),
        Positioned(
          top: 30,
          left: 0,
          right: 0,
          child: Center(
            child: _MapStatusPill(
              isOnline: isOnline,
              isSubmitting: isSubmitting || isLoading,
              onTap: isLoading ? null : () => onAvailabilityChanged(!isOnline),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _RiderBottomSheetSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isLoading) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                ],
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
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
        ),
      ],
    );
  }
}

class _RiderBottomSheetSurface extends StatelessWidget {
  const _RiderBottomSheetSurface({
    required this.child,
    this.maxWidth = 560,
    this.maxHeightFactor = 0.62,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFactor;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: [
                BoxShadow(color: Color(0x33000000), blurRadius: 20),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xff9ca3af),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LifecycleActionButton extends StatelessWidget {
  const _LifecycleActionButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _SoftLabel extends StatelessWidget {
  const _SoftLabel({
    required this.text,
    this.warm = false,
  });

  final String text;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warm ? const Color(0xfffff7ed) : const Color(0xfff3f4f6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          text,
          style: TextStyle(
            color: warm ? const Color(0xffc2410c) : const Color(0xff4b5563),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PickupOrderCodeTile extends StatelessWidget {
  const _PickupOrderCodeTile({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xff99f6e4), width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '#${_shortId(order.id)}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.open_in_full, color: Color(0xff0f766e)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderIdentityRow extends StatelessWidget {
  const _OrderIdentityRow({
    required this.repository,
    required this.order,
  });

  final PlatformRepository repository;
  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_numericOrderCode(order.id)} - #${_shortId(order.id)} - ${_customerName(order)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        _OrderItemsCountLine(repository: repository, orderId: order.id),
      ],
    );
  }
}

class _OrderItemsCountLine extends StatelessWidget {
  const _OrderItemsCountLine({
    required this.repository,
    required this.orderId,
    this.trailing,
  });

  final PlatformRepository repository;
  final String orderId;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderLineItem>>(
      stream: repository.watchOrderItems(orderId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <OrderLineItem>[];
        final count =
            items.fold<int>(0, (total, item) => total + item.quantity);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              count == 1 ? '1 item' : '$count items',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xff047857),
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, color: Color(0xff047857)),
            if (trailing != null) trailing!,
          ],
        );
      },
    );
  }
}

class _OrderItemsExpandable extends StatefulWidget {
  const _OrderItemsExpandable({
    required this.repository,
    required this.orderId,
  });

  final PlatformRepository repository;
  final String orderId;

  @override
  State<_OrderItemsExpandable> createState() => _OrderItemsExpandableState();
}

class _OrderItemsExpandableState extends State<_OrderItemsExpandable> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderLineItem>>(
      stream: widget.repository.watchOrderItems(widget.orderId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <OrderLineItem>[];
        final count =
            items.fold<int>(0, (total, item) => total + item.quantity);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  const Spacer(),
                  Text(
                    count == 1 ? '1 item' : '$count items',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xff047857),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: const Color(0xff047857),
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Text('Order items will appear here.')
              else
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Text(
                          '${item.quantity} x',
                          style: const TextStyle(
                            color: Color(0xff047857),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.productName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(_formatRiderRevenue(item.lineTotal)),
                      ],
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }
}

class _PaymentStatusBlock extends StatelessWidget {
  const _PaymentStatusBlock({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _ActiveDeliveryCard extends StatelessWidget {
  const _ActiveDeliveryCard({
    required this.repository,
    required this.order,
    required this.isSharingLocation,
    required this.isLiveLocation,
    required this.onUpdateEta,
    required this.onShareLocation,
    required this.onToggleLiveLocation,
    required this.onNavigateToStore,
    required this.onNavigateToCustomer,
    required this.onCallCustomer,
    required this.onMessageCustomer,
    required this.onConfirmPickup,
    required this.onConfirmDropOff,
  });

  final PlatformRepository repository;
  final OrderSummary order;
  final bool isSharingLocation;
  final bool isLiveLocation;
  final VoidCallback onUpdateEta;
  final VoidCallback onShareLocation;
  final VoidCallback onToggleLiveLocation;
  final VoidCallback onNavigateToStore;
  final VoidCallback onNavigateToCustomer;
  final VoidCallback onCallCustomer;
  final VoidCallback onMessageCustomer;
  final VoidCallback onConfirmPickup;
  final VoidCallback onConfirmDropOff;

  @override
  Widget build(BuildContext context) {
    final isHeadingToStore =
        order.status == 'ready_for_pickup' || order.status == 'accepted';
    final title = isHeadingToStore ? order.storeName : _customerName(order);
    final address =
        isHeadingToStore ? _storeAddress(order) : order.deliveryAddress;
    final target =
        isHeadingToStore ? _RiderRouteTarget.store : _RiderRouteTarget.customer;
    final primaryLabel =
        isHeadingToStore ? 'Confirm pickup' : 'Confirm drop-off';
    final primaryAction = isHeadingToStore ? onConfirmPickup : onConfirmDropOff;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RiderRouteMap(order: order, target: target, height: 260),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isHeadingToStore ? 'Go to store' : 'Go to customer',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    _RoundActionButton(
                      tooltip: isHeadingToStore
                          ? 'Navigate to store'
                          : 'Navigate to customer',
                      icon: Icons.navigation_outlined,
                      onPressed: isHeadingToStore
                          ? onNavigateToStore
                          : onNavigateToCustomer,
                    ),
                    if (!isHeadingToStore) ...[
                      const SizedBox(width: 8),
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
                  ],
                ),
                const SizedBox(height: 12),
                _RouteStopLine(
                  icon: isHeadingToStore
                      ? Icons.storefront_outlined
                      : Icons.person_pin_circle_outlined,
                  title: address.isEmpty ? 'Address pending' : address,
                  subtitle: isHeadingToStore
                      ? 'Check order with store staff'
                      : 'Paid online',
                ),
                const Divider(height: 24),
                _OrderIdentityBlock(order: order),
                const SizedBox(height: 12),
                _OrderItemsList(repository: repository, orderId: order.id),
                const SizedBox(height: 12),
                _RiderLocationPanel(
                  repository: repository,
                  orderId: order.id,
                  compact: true,
                ),
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
                      label: Text(
                          isSharingLocation ? 'Sharing...' : 'Share location'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onToggleLiveLocation,
                      icon: Icon(isLiveLocation
                          ? Icons.location_disabled_outlined
                          : Icons.location_searching),
                      label: Text(isLiveLocation ? 'Stop live' : 'Start live'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: primaryAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: Text(primaryLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderRouteMap extends StatelessWidget {
  const _RiderRouteMap({
    required this.order,
    required this.target,
    required this.height,
    this.onOpenMenu,
    this.isOnline = true,
    this.isAvailabilitySubmitting = false,
    this.onAvailabilityChanged,
    this.hasMapboxToken = false,
    this.showBothStops = false,
  });

  final OrderSummary order;
  final _RiderRouteTarget target;
  final double height;
  final VoidCallback? onOpenMenu;
  final bool isOnline;
  final bool isAvailabilitySubmitting;
  final ValueChanged<bool>? onAvailabilityChanged;
  final bool hasMapboxToken;
  final bool showBothStops;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final targetIcon = target == _RiderRouteTarget.store
        ? Icons.storefront
        : Icons.person_pin_circle;

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _RiderMapboxMapBackground(
              order: order,
              target: target,
              showBothStops: showBothStops,
              enabled: hasMapboxToken,
              fallback: CustomPaint(painter: _RouteMapPainter(colorScheme)),
            ),
            Positioned(
              left: 30,
              top: 36,
              child: _MapCircleButton(
                icon: Icons.menu,
                onPressed:
                    onOpenMenu ?? () => Scaffold.maybeOf(context)?.openDrawer(),
              ),
            ),
            Positioned(
              top: 30,
              left: 0,
              right: 0,
              child: Center(
                child: _MapStatusPill(
                  isOnline: isOnline,
                  isSubmitting: isAvailabilitySubmitting,
                  onTap: onAvailabilityChanged == null
                      ? null
                      : () => onAvailabilityChanged!(!isOnline),
                ),
              ),
            ),
            Positioned(
              left: 92,
              bottom: 66,
              child:
                  _MapPin(icon: Icons.my_location, color: colorScheme.primary),
            ),
            if (showBothStops) ...[
              const Positioned(
                left: 168,
                bottom: 92,
                child: _MapPin(
                  icon: Icons.storefront,
                  color: Color(0xff111827),
                  label: 'Store',
                ),
              ),
              const Positioned(
                right: 88,
                bottom: 54,
                child: _MapPin(
                  icon: Icons.person,
                  color: Color(0xff111827),
                  label: 'Customer',
                ),
              ),
            ] else
              Positioned(
                right: 88,
                bottom: 54,
                child: _MapPin(
                  icon: targetIcon,
                  color: const Color(0xff059669),
                  label:
                      target == _RiderRouteTarget.store ? 'Store' : 'Customer',
                ),
              ),
            Positioned(
              right: 24,
              bottom: 28,
              child: _MapCircleButton(
                icon: Icons.near_me_outlined,
                filled: true,
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderNavigationPage extends StatefulWidget {
  const _RiderNavigationPage({
    required this.order,
    required this.target,
    required this.mapboxLocation,
    required this.initialOrigin,
    required this.destination,
  });

  final OrderSummary order;
  final _RiderRouteTarget target;
  final MapboxLocationService mapboxLocation;
  final MapboxPoint? initialOrigin;
  final MapboxPoint? destination;

  @override
  State<_RiderNavigationPage> createState() => _RiderNavigationPageState();
}

class _RiderNavigationPageState extends State<_RiderNavigationPage> {
  MapboxPoint? _origin;
  MapboxRouteEstimate? _estimate;
  Object? _routeError;
  var _isLoading = true;
  var _isOpeningExternal = false;

  @override
  void initState() {
    super.initState();
    _origin = widget.initialOrigin;
    unawaited(_loadRoute());
  }

  Future<void> _loadRoute() async {
    setState(() {
      _isLoading = true;
      _routeError = null;
    });

    try {
      var origin = _origin;
      final destination = widget.destination;
      if (origin == null && widget.mapboxLocation.isConfigured) {
        origin = await widget.mapboxLocation.currentPoint();
      }

      MapboxRouteEstimate? estimate;
      if (origin != null &&
          destination != null &&
          widget.mapboxLocation.isConfigured) {
        estimate = await widget.mapboxLocation.routeEstimate(
          origin: origin,
          destination: destination,
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _origin = origin;
        _estimate = estimate;
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _routeError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _openExternalNavigation() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isOpeningExternal = true);

    final uris = _navigationUris(
      order: widget.order,
      target: widget.target,
      origin: _origin,
      destination: widget.destination,
      mapboxLocation: widget.mapboxLocation,
    );

    var opened = false;
    for (final uri in uris) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) {
        break;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() => _isOpeningExternal = false);
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open turn-by-turn navigation')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStore = widget.target == _RiderRouteTarget.store;
    final destinationName =
        _navigationDestinationName(widget.order, widget.target);
    final destinationAddress = _navigationAddress(widget.order, widget.target);
    final title = isStore ? 'Navigate to store' : 'Navigate to customer';
    final action = isStore ? 'Head to pickup' : 'Head to drop-off';
    final colorScheme = Theme.of(context).colorScheme;
    final sheetReserve =
        ((MediaQuery.sizeOf(context).height * 0.48).clamp(300.0, 390.0))
            .toDouble();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: _NavigationMapPreview(
                    enabled: widget.mapboxLocation.isConfigured,
                    origin: _origin,
                    destination: widget.destination,
                    estimate: _estimate,
                    target: widget.target,
                  ),
                ),
                SizedBox(height: sheetReserve),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _MapCircleButton(
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(color: Color(0x22000000), blurRadius: 12),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isStore
                                ? Icons.storefront_outlined
                                : Icons.person_pin_circle_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isStore ? 'Store route' : 'Customer route',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _RiderBottomSheetSurface(
              maxWidth: 640,
              maxHeightFactor: 0.48,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    destinationName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (destinationAddress.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      destinationAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _RouteMetricTile(
                          icon: Icons.schedule,
                          label: 'ETA',
                          value: _estimate == null
                              ? (_isLoading ? '...' : 'Pending')
                              : '${_estimate!.durationMinutes} min',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _RouteMetricTile(
                          icon: Icons.route_outlined,
                          label: 'Distance',
                          value: _estimate == null
                              ? (_isLoading ? '...' : 'Pending')
                              : '${_estimate!.distanceKm.toStringAsFixed(1)} km',
                        ),
                      ),
                    ],
                  ),
                  if (_routeError != null) ...[
                    const SizedBox(height: 8),
                    const _RouteNotice(
                      icon: Icons.location_off_outlined,
                      text:
                          'Live route estimate unavailable. Check GPS or use turn-by-turn maps.',
                    ),
                  ] else if (widget.destination == null) ...[
                    const SizedBox(height: 8),
                    const _RouteNotice(
                      icon: Icons.search_off_outlined,
                      text:
                          'Store coordinates are not saved yet. Turn-by-turn maps will use the address.',
                    ),
                  ],
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed:
                        _isOpeningExternal ? null : _openExternalNavigation,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    icon: _isOpeningExternal
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.navigation_outlined),
                    label: Text(_isOpeningExternal
                        ? 'Opening maps...'
                        : '$action directions'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _loadRoute,
                    icon: const Icon(Icons.my_location),
                    label:
                        Text(_isLoading ? 'Updating route...' : 'Refresh GPS'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationMapPreview extends StatelessWidget {
  const _NavigationMapPreview({
    required this.enabled,
    required this.origin,
    required this.destination,
    required this.estimate,
    required this.target,
  });

  final bool enabled;
  final MapboxPoint? origin;
  final MapboxPoint? destination;
  final MapboxRouteEstimate? estimate;
  final _RiderRouteTarget target;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final points = <MapboxPoint>[
      if (origin != null) origin!,
      if (destination != null) destination!,
      ...?estimate?.geometry,
    ];
    final hasMap = enabled && points.isNotEmpty;
    final targetIcon = target == _RiderRouteTarget.store
        ? Icons.storefront
        : Icons.person_pin_circle;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasMap)
          mapbox.MapWidget(
            key: ValueKey(
              'rider-nav-${points.length}-'
              '${_riderMapCenter(points).latitude.toStringAsFixed(4)}',
            ),
            styleUri: mapbox.MapboxStyles.STANDARD,
            viewport: mapbox.CameraViewportState(
              center: mapbox.Point(
                coordinates: mapbox.Position(
                  _riderMapCenter(points).longitude,
                  _riderMapCenter(points).latitude,
                ),
              ),
              zoom: points.length > 1 ? 12 : 14,
            ),
          )
        else
          CustomPaint(painter: _RouteMapPainter(colorScheme)),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _NavigationRouteOverlayPainter(
                colorScheme: colorScheme,
                showRoute: origin != null && destination != null,
              ),
            ),
          ),
        ),
        if (origin != null)
          const Positioned(
            left: 76,
            bottom: 150,
            child: _MapPin(
              icon: Icons.my_location,
              color: Color(0xff2563eb),
              label: 'You',
            ),
          ),
        if (destination != null)
          Positioned(
            right: 72,
            top: 168,
            child: _MapPin(
              icon: targetIcon,
              color: const Color(0xff059669),
              label: target == _RiderRouteTarget.store ? 'Store' : 'Customer',
            ),
          ),
      ],
    );
  }
}

class _NavigationRouteOverlayPainter extends CustomPainter {
  const _NavigationRouteOverlayPainter({
    required this.colorScheme,
    required this.showRoute,
  });

  final ColorScheme colorScheme;
  final bool showRoute;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showRoute) {
      return;
    }

    final routePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final routeShadow = Paint()
      ..color = Colors.white.withValues(alpha: 0.84)
      ..strokeWidth = 13
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.20, size.height * 0.72)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.62,
        size.width * 0.55,
        size.height * 0.68,
        size.width * 0.64,
        size.height * 0.48,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.30,
        size.width * 0.82,
        size.height * 0.24,
        size.width * 0.84,
        size.height * 0.18,
      );
    canvas
      ..drawPath(path, routeShadow)
      ..drawPath(path, routePaint);
  }

  @override
  bool shouldRepaint(covariant _NavigationRouteOverlayPainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme ||
        oldDelegate.showRoute != showRoute;
  }
}

class _RouteMetricTile extends StatelessWidget {
  const _RouteMetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfff8fafc),
        border: Border.all(color: const Color(0xffe5e7eb)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xff2563eb)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
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

class _RouteNotice extends StatelessWidget {
  const _RouteNotice({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfffffbeb),
        border: Border.all(color: const Color(0xfffde68a)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xffb45309)),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _RiderMapboxMapBackground extends StatelessWidget {
  const _RiderMapboxMapBackground({
    required this.enabled,
    required this.fallback,
    this.order,
    this.target,
    this.showBothStops = false,
  });

  final bool enabled;
  final Widget fallback;
  final OrderSummary? order;
  final _RiderRouteTarget? target;
  final bool showBothStops;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return fallback;
    }

    final points = <MapboxPoint>[];
    final currentOrder = order;
    if (currentOrder != null) {
      if (showBothStops) {
        final store = _destinationPoint(currentOrder, _RiderRouteTarget.store);
        final customer =
            _destinationPoint(currentOrder, _RiderRouteTarget.customer);
        if (store != null) {
          points.add(store);
        }
        if (customer != null) {
          points.add(customer);
        }
      } else {
        final currentTarget = target;
        if (currentTarget != null) {
          final destination = _destinationPoint(currentOrder, currentTarget);
          if (destination != null) {
            points.add(destination);
          }
        }
      }
    }

    if (points.isEmpty) {
      return fallback;
    }

    final center = _riderMapCenter(points);
    return mapbox.MapWidget(
      key: ValueKey(
        'rider-map-${center.latitude.toStringAsFixed(4)}-'
        '${center.longitude.toStringAsFixed(4)}-${points.length}',
      ),
      styleUri: mapbox.MapboxStyles.STANDARD,
      viewport: mapbox.CameraViewportState(
        center: mapbox.Point(
          coordinates: mapbox.Position(center.longitude, center.latitude),
        ),
        zoom: points.length > 1 ? 11 : 13,
      ),
    );
  }
}

class _RouteMapPainter extends CustomPainter {
  const _RouteMapPainter(this.colorScheme);

  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = colorScheme.surfaceContainerHighest;
    canvas.drawRect(Offset.zero & size, background);

    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final minorRoadPaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final routePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.18 + i * 0.16);
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 24), minorRoadPaint);
    }
    for (var i = 0; i < 4; i++) {
      final x = size.width * (0.14 + i * 0.22);
      canvas.drawLine(
          Offset(x, 0), Offset(x + 28, size.height), minorRoadPaint);
    }

    final mainPath = Path()
      ..moveTo(size.width * 0.12, size.height * 0.68)
      ..quadraticBezierTo(
        size.width * 0.42,
        size.height * 0.55,
        size.width * 0.62,
        size.height * 0.72,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.85,
        size.width * 0.92,
        size.height * 0.56,
      );
    canvas.drawPath(mainPath, roadPaint);

    final routePath = Path()
      ..moveTo(size.width * 0.28, size.height * 0.68)
      ..quadraticBezierTo(
        size.width * 0.48,
        size.height * 0.58,
        size.width * 0.70,
        size.height * 0.66,
      );
    canvas.drawPath(routePath, routePaint);
  }

  @override
  bool shouldRepaint(covariant _RouteMapPainter oldDelegate) =>
      oldDelegate.colorScheme != colorScheme;
}

class _MapStatusPill extends StatelessWidget {
  const _MapStatusPill({
    required this.isOnline,
    this.isSubmitting = false,
    this.onTap,
  });

  final bool isOnline;
  final bool isSubmitting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      elevation: 7,
      shadowColor: const Color(0x22000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: isSubmitting ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Status',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    isSubmitting
                        ? 'Updating'
                        : isOnline
                            ? 'Online'
                            : 'Offline',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              if (isSubmitting)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.circle,
                  size: 11,
                  color: isOnline ? const Color(0xff22c55e) : Colors.grey,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
