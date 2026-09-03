part of '../../main.dart';

class _TrackingPane extends StatefulWidget {
  const _TrackingPane({
    required this.repository,
    required this.ordersStream,
    required this.hasMapboxToken,
    required this.catalogByProductId,
    required this.payingOrderIds,
    required this.cancellingOrderIds,
    required this.receivingOrderIds,
    required this.onPayNow,
    required this.onCancelOrder,
    required this.onMarkReceived,
    required this.onReorder,
    required this.onReportIssue,
    required this.onReviewOrder,
  });

  final PlatformRepository repository;
  final Stream<List<OrderSummary>> ordersStream;
  final bool hasMapboxToken;
  final Map<String, CatalogItem> catalogByProductId;
  final Set<String> payingOrderIds;
  final Set<String> cancellingOrderIds;
  final Set<String> receivingOrderIds;
  final ValueChanged<OrderSummary> onPayNow;
  final ValueChanged<OrderSummary> onCancelOrder;
  final ValueChanged<OrderSummary> onMarkReceived;
  final ValueChanged<OrderSummary> onReorder;
  final ValueChanged<OrderSummary> onReportIssue;
  final ValueChanged<OrderSummary> onReviewOrder;

  @override
  State<_TrackingPane> createState() => _TrackingPaneState();
}

class _TrackingPaneState extends State<_TrackingPane> {
  var _showActive = true;
  var _statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderSummary>>(
      stream: widget.ordersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Orders failed to load',
            message: snapshot.error.toString(),
          );
        }

        final orders = snapshot.data ?? const <OrderSummary>[];
        final visibleOrders = orders
            .where((order) => _showActive
                ? _isActiveCustomerOrder(order)
                : !_isActiveCustomerOrder(order))
            .where((order) => _matchesCustomerOrderFilter(
                  order,
                  _statusFilter,
                ))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          shrinkWrap: true,
          children: [
            Text(
              'Orders',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 18),
            if (orders.isNotEmpty) ...[
              _CustomerTrackingAlerts(orders: orders),
              const SizedBox(height: 14),
              _OrdersTabSwitcher(
                showActive: _showActive,
                onChanged: (value) => setState(() {
                  _showActive = value;
                  _statusFilter = 'all';
                }),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: _CustomerOrderFilterButton(
                  selected: _statusFilter,
                  showActive: _showActive,
                  onSelected: (value) => setState(() => _statusFilter = value),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (orders.isEmpty)
              const Text('Sign in and place an order to track it here.')
            else if (visibleOrders.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Text(
                  _showActive ? 'No in-progress orders.' : 'No order history.',
                ),
              )
            else
              for (final order in visibleOrders.take(30))
                _CustomerOrderListTile(
                  order: order,
                  repository: widget.repository,
                  hasMapboxToken: widget.hasMapboxToken,
                  catalogByProductId: widget.catalogByProductId,
                  isPaying: widget.payingOrderIds.contains(order.id),
                  isCancelling: widget.cancellingOrderIds.contains(order.id),
                  isReceiving: widget.receivingOrderIds.contains(order.id),
                  onPayNow: widget.onPayNow,
                  onCancelOrder: widget.onCancelOrder,
                  onMarkReceived: widget.onMarkReceived,
                  onReorder: widget.onReorder,
                  onReportIssue: widget.onReportIssue,
                  onReviewOrder: widget.onReviewOrder,
                ),
          ],
        );
      },
    );
  }
}

class _OrdersTabSwitcher extends StatelessWidget {
  const _OrdersTabSwitcher({
    required this.showActive,
    required this.onChanged,
  });

  final bool showActive;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _OrdersTabButton(
                label: 'In progress',
                selected: showActive,
                onTap: () => onChanged(true),
              ),
            ),
            Expanded(
              child: _OrdersTabButton(
                label: 'History',
                selected: !showActive,
                onTap: () => onChanged(false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / 2;
            return Stack(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                AnimatedAlign(
                  alignment:
                      showActive ? Alignment.centerLeft : Alignment.centerRight,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: width,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xff111827),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _OrdersTabButton extends StatelessWidget {
  const _OrdersTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
                color: selected
                    ? const Color(0xff111827)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

class _CustomerOrderFilterButton extends StatelessWidget {
  const _CustomerOrderFilterButton({
    required this.selected,
    required this.showActive,
    required this.onSelected,
  });

  final String selected;
  final bool showActive;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final filters = _customerOrderFilters(showActive);
    final label = _customerOrderFilterLabel(selected);

    return PopupMenuButton<String>(
      tooltip: 'Sort orders',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final filter in filters)
          PopupMenuItem<String>(
            value: filter.value,
            child: Row(
              children: [
                Icon(filter.icon, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(filter.label)),
                if (selected == filter.value) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune, size: 18),
              const SizedBox(width: 8),
              Text(
                label == 'All' ? 'Sort' : label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerOrderFilter {
  const _CustomerOrderFilter(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}

void _openCustomerOrderDetail({
  required BuildContext context,
  required OrderSummary order,
  required PlatformRepository repository,
  required bool hasMapboxToken,
  required Map<String, CatalogItem> catalogByProductId,
  required bool isPaying,
  required bool isCancelling,
  required bool isReceiving,
  required ValueChanged<OrderSummary> onPayNow,
  required ValueChanged<OrderSummary> onCancelOrder,
  required ValueChanged<OrderSummary> onMarkReceived,
  required ValueChanged<OrderSummary> onReorder,
  required ValueChanged<OrderSummary> onReportIssue,
  required ValueChanged<OrderSummary> onReviewOrder,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => _CustomerOrderDetailPage(
        order: order,
        repository: repository,
        hasMapboxToken: hasMapboxToken,
        catalogByProductId: catalogByProductId,
        isPaying: isPaying,
        isCancelling: isCancelling,
        isReceiving: isReceiving,
        onPayNow: onPayNow,
        onCancelOrder: onCancelOrder,
        onMarkReceived: onMarkReceived,
        onReorder: onReorder,
        onReportIssue: onReportIssue,
        onReviewOrder: onReviewOrder,
      ),
    ),
  );
}

class _OrderLifecycleHero extends StatelessWidget {
  const _OrderLifecycleHero({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stage = _trackingStageForOrder(order);
    final isActive = _isActiveCustomerOrder(order);
    final eta =
        isActive && order.etaMinutes != null ? '${order.etaMinutes} min' : null;
    final progress = (stage / 4).clamp(0.0, 1.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? scheme.primaryContainer.withValues(alpha: 0.42)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? scheme.primary.withValues(alpha: 0.24)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _AnimatedOrderIcon(stage: stage, isActive: isActive),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Column(
                    key: ValueKey('${order.id}-${order.status}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _trackingStageTitle(order),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${order.storeName} | Order #${_shortId(order.id)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _LifecycleMotionPath(progress: progress, isActive: isActive),
          const SizedBox(height: 14),
          _TrackingProgressRail(stage: stage, isActive: isActive),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniInfoChip(
                icon: Icons.payments_outlined,
                label: _formatNaira(order.totalAmount),
              ),
              _MiniInfoChip(
                icon: Icons.receipt_long_outlined,
                label: _humanStatus(order.paymentStatus),
              ),
              if (eta != null) _MiniInfoChip(icon: Icons.schedule, label: eta),
              if (isActive && order.riderName?.trim().isNotEmpty == true)
                _MiniInfoChip(
                  icon: Icons.delivery_dining,
                  label: order.riderName!.trim(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LifecycleMotionPath extends StatefulWidget {
  const _LifecycleMotionPath({
    required this.progress,
    required this.isActive,
  });

  final double progress;
  final bool isActive;

  @override
  State<_LifecycleMotionPath> createState() => _LifecycleMotionPathState();
}

class _LifecycleMotionPathState extends State<_LifecycleMotionPath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _LifecycleMotionPath oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _LifecycleMotionPainter(
              colorScheme: Theme.of(context).colorScheme,
              progress: widget.progress,
              motion: widget.isActive ? _controller.value : 0,
            ),
          );
        },
      ),
    );
  }
}

class _LifecycleMotionPainter extends CustomPainter {
  const _LifecycleMotionPainter({
    required this.colorScheme,
    required this.progress,
    required this.motion,
  });

  final ColorScheme colorScheme;
  final double progress;
  final double motion;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final left = 18.0;
    final right = size.width - 18;
    final fullWidth = right - left;
    final activeEnd = left + fullWidth * progress;
    final basePaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final activePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(left, y), Offset(right, y), basePaint);
    canvas.drawLine(Offset(left, y), Offset(activeEnd, y), activePaint);

    final pulseX = left + fullWidth * ((progress + motion * 0.18).clamp(0, 1));
    final pulsePaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.18);
    canvas.drawCircle(
        Offset(pulseX, y), 18 + math.sin(motion * math.pi) * 4, pulsePaint);
    canvas.drawCircle(
      Offset(activeEnd, y),
      10,
      Paint()..color = colorScheme.primary,
    );
  }

  @override
  bool shouldRepaint(covariant _LifecycleMotionPainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme ||
        oldDelegate.progress != progress ||
        oldDelegate.motion != motion;
  }
}

class _AnimatedOrderIcon extends StatefulWidget {
  const _AnimatedOrderIcon({
    required this.stage,
    this.isActive = true,
  });

  final int stage;
  final bool isActive;

  @override
  State<_AnimatedOrderIcon> createState() => _AnimatedOrderIconState();
}

class _AnimatedOrderIconState extends State<_AnimatedOrderIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedOrderIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = widget.stage >= 3
        ? Icons.delivery_dining
        : widget.stage >= 1
            ? Icons.restaurant_menu
            : Icons.payments_outlined;
    return ScaleTransition(
      scale: widget.isActive
          ? Tween<double>(begin: 0.94, end: 1.05).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
            )
          : const AlwaysStoppedAnimation<double>(1),
      child: CircleAvatar(
        radius: 24,
        backgroundColor: scheme.primaryContainer,
        child: Icon(icon, color: scheme.primary),
      ),
    );
  }
}

class _TrackingProgressRail extends StatelessWidget {
  const _TrackingProgressRail({
    required this.stage,
    this.isActive = true,
  });

  final int stage;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.payment, 'Paid'),
      (Icons.storefront, 'Accepted'),
      (Icons.restaurant, 'Preparing'),
      (Icons.delivery_dining, 'Rider'),
      (Icons.home_outlined, 'Arriving'),
    ];
    return Row(
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          Expanded(
            child: _TrackingProgressStep(
              icon: steps[index].$1,
              label: steps[index].$2,
              isActive: index <= stage,
              isCurrent: isActive && index == stage,
            ),
          ),
          if (index != steps.length - 1)
            Container(
              width: 14,
              height: 2,
              color: index < stage
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
        ],
      ],
    );
  }
}

class _TrackingProgressStep extends StatelessWidget {
  const _TrackingProgressStep({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isCurrent,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isActive ? scheme.primary : scheme.outline;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: isCurrent ? 34 : 30,
          height: isCurrent ? 34 : 30,
          decoration: BoxDecoration(
            color: isActive ? scheme.primaryContainer : scheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: color),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

class _CustomerTrackingAlerts extends StatelessWidget {
  const _CustomerTrackingAlerts({required this.orders});

  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context) {
    final paymentRequired =
        orders.where((order) => order.paymentStatus == 'pending').length;
    final lateEtas = orders.where(_isOrderEtaLate).length;
    final activeDeliveries = orders.where(_isActiveCustomerOrder).length;
    if (paymentRequired == 0 && lateEtas == 0 && activeDeliveries == 0) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (paymentRequired > 0)
          Chip(
            avatar: const Icon(Icons.payment_outlined, size: 18),
            label: Text('$paymentRequired awaiting payment'),
          ),
        if (lateEtas > 0)
          Chip(
            avatar: const Icon(Icons.timer_off_outlined, size: 18),
            label: Text('$lateEtas late ETA'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        if (activeDeliveries > 0)
          Chip(
            avatar: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text('$activeDeliveries active'),
          ),
      ],
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

class _CustomerOrderListTile extends StatelessWidget {
  const _CustomerOrderListTile({
    required this.order,
    required this.repository,
    required this.hasMapboxToken,
    required this.catalogByProductId,
    required this.isPaying,
    required this.isCancelling,
    required this.isReceiving,
    required this.onPayNow,
    required this.onCancelOrder,
    required this.onMarkReceived,
    required this.onReorder,
    required this.onReportIssue,
    required this.onReviewOrder,
  });

  final OrderSummary order;
  final PlatformRepository repository;
  final bool hasMapboxToken;
  final Map<String, CatalogItem> catalogByProductId;
  final bool isPaying;
  final bool isCancelling;
  final bool isReceiving;
  final ValueChanged<OrderSummary> onPayNow;
  final ValueChanged<OrderSummary> onCancelOrder;
  final ValueChanged<OrderSummary> onMarkReceived;
  final ValueChanged<OrderSummary> onReorder;
  final ValueChanged<OrderSummary> onReportIssue;
  final ValueChanged<OrderSummary> onReviewOrder;

  @override
  Widget build(BuildContext context) {
    final canReview = order.status == 'delivered';
    return StreamBuilder<List<OrderLineItem>>(
      stream: repository.watchOrderItems(order.id),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <OrderLineItem>[];
        final imageUrl = _orderPreviewImageUrl(items, catalogByProductId);
        final summary = _orderItemSummary(items);
        final statusColor = _customerOrderStatusColor(order);

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openCustomerOrderDetail(
            context: context,
            order: order,
            repository: repository,
            hasMapboxToken: hasMapboxToken,
            catalogByProductId: catalogByProductId,
            isPaying: isPaying,
            isCancelling: isCancelling,
            isReceiving: isReceiving,
            onPayNow: onPayNow,
            onCancelOrder: onCancelOrder,
            onMarkReceived: onMarkReceived,
            onReorder: onReorder,
            onReportIssue: onReportIssue,
            onReviewOrder: onReviewOrder,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OrderPreviewImage(
                  imageUrl: imageUrl,
                  storeName: order.storeName,
                  statusColor: statusColor,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CustomerStatusPill(
                        label: _customerOrderStatusLabel(order),
                        color: statusColor,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        order.storeName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.16,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.22,
                            ),
                      ),
                      if (canReview) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => onReviewOrder(order),
                          icon: const Icon(Icons.star_outline, size: 18),
                          label: const Text('Review'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatNaira(order.totalAmount),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
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

class _OrderPreviewImage extends StatelessWidget {
  const _OrderPreviewImage({
    required this.imageUrl,
    required this.storeName,
    required this.statusColor,
  });

  final String? imageUrl;
  final String storeName;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final initials = _storeInitials(storeName);
    final url = imageUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 74,
        height: 74,
        child: url == null || url.isEmpty
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _CustomerStatusPill extends StatelessWidget {
  const _CustomerStatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _CustomerOrderDetailPage extends StatelessWidget {
  const _CustomerOrderDetailPage({
    required this.order,
    required this.repository,
    required this.hasMapboxToken,
    required this.catalogByProductId,
    required this.isPaying,
    required this.isCancelling,
    required this.isReceiving,
    required this.onPayNow,
    required this.onCancelOrder,
    required this.onMarkReceived,
    required this.onReorder,
    required this.onReportIssue,
    required this.onReviewOrder,
  });

  final OrderSummary order;
  final PlatformRepository repository;
  final bool hasMapboxToken;
  final Map<String, CatalogItem> catalogByProductId;
  final bool isPaying;
  final bool isCancelling;
  final bool isReceiving;
  final ValueChanged<OrderSummary> onPayNow;
  final ValueChanged<OrderSummary> onCancelOrder;
  final ValueChanged<OrderSummary> onMarkReceived;
  final ValueChanged<OrderSummary> onReorder;
  final ValueChanged<OrderSummary> onReportIssue;
  final ValueChanged<OrderSummary> onReviewOrder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OrderSummary?>(
      stream: repository.watchOrder(order.id),
      initialData: order,
      builder: (context, orderSnapshot) {
        final currentOrder = orderSnapshot.data ?? order;
        return StreamBuilder<List<OrderLineItem>>(
          stream: repository.watchOrderItems(currentOrder.id),
          builder: (context, itemSnapshot) {
            final items = itemSnapshot.data ?? const <OrderLineItem>[];
            final canReorder = _canReorderSamePrice(items, catalogByProductId);
            final needsPayment = currentOrder.paymentStatus == 'pending';
            final canCancel = currentOrder.status == 'pending_payment' &&
                currentOrder.paymentStatus == 'pending';
            final canReview = currentOrder.status == 'delivered';
            final canMarkReceived = currentOrder.paymentStatus == 'paid' &&
                currentOrder.status == 'out_for_delivery';
            final showRiderTracking = _shouldShowRiderTracking(currentOrder);

            return Scaffold(
              appBar: AppBar(title: const Text('Order summary')),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
                children: [
                  _OrderLifecycleHero(order: currentOrder),
                  const SizedBox(height: 12),
                  _OrderDetailSection(
                    title: 'Status',
                    children: [
                      _DetailRow(
                        label: 'Order status',
                        value: _humanStatus(currentOrder.status),
                      ),
                      _DetailRow(
                        label: 'Payment',
                        value: _humanStatus(currentOrder.paymentStatus),
                      ),
                      _DetailRow(
                        label: 'Date and time',
                        value: _formatDateTime(currentOrder.createdAt),
                      ),
                      _DetailRow(
                        label: 'Order ID',
                        value: currentOrder.id,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _OrderDetailSection(
                    title: 'Items',
                    children: [
                      if (items.isEmpty)
                        const Text('Items will appear here.')
                      else
                        for (final item in items)
                          _DetailRow(
                            label: '${item.quantity} x ${item.productName}',
                            value: _formatNaira(item.lineTotal),
                          ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _OrderDetailSection(
                    title: 'Delivery details',
                    children: [
                      _DetailRow(label: 'Store', value: currentOrder.storeName),
                      _DetailRow(
                        label: 'Store address',
                        value: currentOrder.storeAddress.isEmpty
                            ? 'Store address pending'
                            : currentOrder.storeAddress,
                      ),
                      _DetailRow(
                        label: 'Customer address',
                        value: currentOrder.fulfillmentType == 'pickup'
                            ? 'Pickup at store'
                            : currentOrder.deliveryAddress,
                      ),
                      if (currentOrder.deliveryDistanceKm > 0)
                        _DetailRow(
                          label: 'Distance',
                          value:
                              '${currentOrder.deliveryDistanceKm.toStringAsFixed(1)} km',
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _OrderDetailSection(
                    title: 'Price breakdown',
                    children: [
                      _DetailRow(
                        label: 'Items subtotal',
                        value: _formatNaira(currentOrder.itemsSubtotal),
                      ),
                      if (currentOrder.discountAmount > 0)
                        _DetailRow(
                          label: 'Discount',
                          value:
                              '-${_formatNaira(currentOrder.discountAmount)}',
                        ),
                      _DetailRow(
                        label: 'Delivery fee',
                        value: _formatNaira(currentOrder.deliveryFee),
                      ),
                      _DetailRow(
                        label: 'Service fee',
                        value: _formatNaira(currentOrder.serviceFee),
                      ),
                      const Divider(),
                      _DetailRow(
                        label: 'Total',
                        value: _formatNaira(currentOrder.totalAmount),
                        isStrong: true,
                      ),
                    ],
                  ),
                  if (showRiderTracking) ...[
                    const SizedBox(height: 12),
                    _RiderLocationPanel(
                      repository: repository,
                      order: currentOrder,
                      hasMapboxToken: hasMapboxToken,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _OrderDetailSection(
                    title: 'Timeline',
                    children: [
                      StreamBuilder<List<DeliveryEvent>>(
                        stream: repository.watchDeliveryEvents(currentOrder.id),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Text('Timeline failed: ${snapshot.error}');
                          }

                          final events =
                              snapshot.data ?? const <DeliveryEvent>[];
                          if (events.isEmpty) {
                            return const Text(
                              'Delivery updates will appear here.',
                            );
                          }

                          return Column(
                            children: [
                              for (final event in events)
                                _DeliveryEventRow(event: event),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _OrderIssuesList(
                    repository: repository,
                    orderId: currentOrder.id,
                  ),
                  const SizedBox(height: 12),
                  _OrderReviewsList(
                    repository: repository,
                    orderId: currentOrder.id,
                  ),
                  const SizedBox(height: 12),
                  if (needsPayment)
                    FilledButton.icon(
                      onPressed: isPaying || isCancelling
                          ? null
                          : () => onPayNow(currentOrder),
                      icon: const Icon(Icons.payment),
                      label: Text(isPaying ? 'Opening checkout...' : 'Pay now'),
                    ),
                  if (canCancel)
                    OutlinedButton.icon(
                      onPressed: isPaying || isCancelling
                          ? null
                          : () => onCancelOrder(currentOrder),
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(isCancelling ? 'Cancelling...' : 'Cancel'),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => onReportIssue(currentOrder),
                        icon: const Icon(Icons.support_agent_outlined),
                        label: const Text('Report issue'),
                      ),
                      if (canReview)
                        OutlinedButton.icon(
                          onPressed: () => onReviewOrder(currentOrder),
                          icon: const Icon(Icons.star_outline),
                          label: const Text('Review'),
                        ),
                      if (canMarkReceived)
                        FilledButton.icon(
                          onPressed: isReceiving
                              ? null
                              : () => onMarkReceived(currentOrder),
                          icon: isReceiving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(
                            isReceiving ? 'Confirming...' : 'Mark received',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              floatingActionButton: canReorder
                  ? FloatingActionButton.extended(
                      backgroundColor: const Color(0xff16a34a),
                      foregroundColor: Colors.white,
                      onPressed: () => onReorder(currentOrder),
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: const Text('Reorder'),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

class _OrderDetailSection extends StatelessWidget {
  const _OrderDetailSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isStrong = false,
  });

  final String label;
  final String value;
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    final style = isStrong
        ? Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w900)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderLocationPanel extends StatelessWidget {
  const _RiderLocationPanel({
    required this.repository,
    required this.order,
    required this.hasMapboxToken,
  });

  final PlatformRepository repository;
  final OrderSummary order;
  final bool hasMapboxToken;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RiderLocationUpdate>>(
      stream: repository.watchRiderLocations(order.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineState(
            title: 'Rider location failed',
            message: snapshot.error.toString(),
          );
        }

        final locations = snapshot.data ?? const <RiderLocationUpdate>[];
        final latest = locations.isEmpty ? null : locations.first;
        final storePoint = _firstPoint(
          order.storeLatitude,
          order.storeLongitude,
          latest?.storeLatitude,
          latest?.storeLongitude,
        );
        final customerPoint = _firstPoint(
          order.deliveryLatitude,
          order.deliveryLongitude,
          latest?.deliveryLatitude,
          latest?.deliveryLongitude,
        );
        final riderPoint =
            latest == null ? null : _LatLng(latest.latitude, latest.longitude);
        final distanceKm = order.deliveryDistanceKm > 0
            ? order.deliveryDistanceKm
            : latest?.deliveryDistanceKm ?? 0;
        final riderEtaMinutes = _liveEtaMinutes(
          order: order,
          riderPoint: riderPoint,
          customerPoint: customerPoint,
          fallbackDistanceKm: distanceKm,
        );
        final mapsUri = _routeMapsUri(
          storePoint: storePoint,
          customerPoint: customerPoint,
          riderPoint: riderPoint,
        );
        final hasRoute = storePoint != null || customerPoint != null;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            color: Theme.of(context).colorScheme.surface,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 220,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _MapboxRouteMap(
                      points: [
                        if (storePoint != null) storePoint,
                        if (customerPoint != null) customerPoint,
                        if (riderPoint != null) riderPoint,
                      ],
                      fallback: CustomPaint(
                        painter: _DeliveryRoutePainter(
                          storePoint: storePoint,
                          customerPoint: customerPoint,
                          riderPoint: riderPoint,
                          colorScheme: Theme.of(context).colorScheme,
                        ),
                      ),
                      enabled: hasMapboxToken,
                    ),
                    Positioned(
                      left: 14,
                      top: 14,
                      child: _TrackingBadge(
                        icon: latest == null
                            ? Icons.location_searching
                            : Icons.navigation,
                        label: latest == null
                            ? 'Waiting for rider GPS'
                            : 'Live rider location',
                      ),
                    ),
                    if (riderEtaMinutes != null)
                      Positioned(
                        right: 14,
                        bottom: 14,
                        child: _TrackingEtaPill(minutes: riderEtaMinutes),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.fulfillmentType == 'pickup'
                                ? 'Pickup route'
                                : 'Delivery route',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (mapsUri != null)
                          TextButton.icon(
                            onPressed: () => launchUrl(
                              mapsUri,
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Open map'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TrackingInfoChip(
                          icon: Icons.storefront_outlined,
                          label: order.storeName,
                        ),
                        if (order.fulfillmentType != 'pickup')
                          _TrackingInfoChip(
                            icon: Icons.home_outlined,
                            label: order.deliveryAddress.isEmpty
                                ? 'Customer location'
                                : order.deliveryAddress,
                          ),
                        if (distanceKm > 0)
                          _TrackingInfoChip(
                            icon: Icons.route_outlined,
                            label: '${distanceKm.toStringAsFixed(1)} km',
                          ),
                        if (order.deliveryFee > 0)
                          _TrackingInfoChip(
                            icon: Icons.payments_outlined,
                            label:
                                'Delivery NGN ${order.deliveryFee.toStringAsFixed(2)}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      latest == null
                          ? hasRoute
                              ? 'The route is ready. Rider live movement will appear as soon as they share location.'
                              : 'Map tracking will appear when store, customer, or rider coordinates are available.'
                          : 'Updated ${_formatDateTime(latest.createdAt)}'
                              '${latest.accuracyMeters == null ? '' : ' | accuracy ${latest.accuracyMeters!.toStringAsFixed(0)}m'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LatLng {
  const _LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class _MapboxRouteMap extends StatelessWidget {
  const _MapboxRouteMap({
    required this.points,
    required this.fallback,
    required this.enabled,
  });

  final List<_LatLng> points;
  final Widget fallback;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || points.isEmpty) {
      return fallback;
    }

    final center = _centerPoint(points);
    return Stack(
      fit: StackFit.expand,
      children: [
        mapbox.MapWidget(
          key: ValueKey(
            'mapbox-${center.latitude.toStringAsFixed(4)}-${center.longitude.toStringAsFixed(4)}-${points.length}',
          ),
          styleUri: mapbox.MapboxStyles.STANDARD,
          viewport: mapbox.CameraViewportState(
            center: mapbox.Point(
              coordinates: mapbox.Position(center.longitude, center.latitude),
            ),
            zoom: points.length == 1 ? 14 : 11,
          ),
        ),
        IgnorePointer(child: fallback),
      ],
    );
  }
}

class _DeliveryRoutePainter extends CustomPainter {
  const _DeliveryRoutePainter({
    required this.storePoint,
    required this.customerPoint,
    required this.riderPoint,
    required this.colorScheme,
  });

  final _LatLng? storePoint;
  final _LatLng? customerPoint;
  final _LatLng? riderPoint;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = colorScheme.surfaceContainerHighest;
    canvas.drawRect(Offset.zero & size, background);

    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var x = 28.0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 24.0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = [
      if (storePoint != null) storePoint!,
      if (customerPoint != null) customerPoint!,
      if (riderPoint != null) riderPoint!,
    ];
    if (points.isEmpty) {
      _drawEmptyMap(canvas, size);
      return;
    }

    final bounds = _MapBounds.from(points);
    Offset project(_LatLng point) => bounds.project(point, size);

    final storeOffset = storePoint == null ? null : project(storePoint!);
    final customerOffset =
        customerPoint == null ? null : project(customerPoint!);
    final riderOffset = riderPoint == null ? null : project(riderPoint!);

    if (storeOffset != null && customerOffset != null) {
      final routePaint = Paint()
        ..color = colorScheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(storeOffset.dx, storeOffset.dy)
        ..quadraticBezierTo(
          size.width / 2,
          math.min(storeOffset.dy, customerOffset.dy) - 34,
          customerOffset.dx,
          customerOffset.dy,
        );
      canvas.drawPath(path, routePaint);
    }

    if (storeOffset != null) {
      _drawPin(canvas, storeOffset, colorScheme.primary, Icons.storefront);
    }
    if (customerOffset != null) {
      _drawPin(canvas, customerOffset, colorScheme.tertiary, Icons.home);
    }
    if (riderOffset != null) {
      _drawPin(
        canvas,
        riderOffset,
        colorScheme.error,
        Icons.delivery_dining,
        radius: 22,
      );
    }
  }

  void _drawEmptyMap(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colorScheme.outline.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 34, paint);
    canvas.drawLine(center.translate(-52, 0), center.translate(52, 0), paint);
    canvas.drawLine(center.translate(0, -52), center.translate(0, 52), paint);
  }

  void _drawPin(
    Canvas canvas,
    Offset offset,
    Color color,
    IconData icon, {
    double radius = 18,
  }) {
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(offset.translate(0, 4), radius, shadowPaint);
    canvas.drawCircle(offset, radius, Paint()..color = color);
    canvas.drawCircle(
      offset,
      radius - 4,
      Paint()..color = colorScheme.surface.withValues(alpha: 0.94),
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: radius,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      offset - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _DeliveryRoutePainter oldDelegate) {
    return oldDelegate.storePoint != storePoint ||
        oldDelegate.customerPoint != customerPoint ||
        oldDelegate.riderPoint != riderPoint ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _MapBounds {
  const _MapBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  factory _MapBounds.from(List<_LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    if ((maxLat - minLat).abs() < 0.001) {
      minLat -= 0.01;
      maxLat += 0.01;
    }
    if ((maxLng - minLng).abs() < 0.001) {
      minLng -= 0.01;
      maxLng += 0.01;
    }
    return _MapBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }

  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  Offset project(_LatLng point, Size size) {
    const padding = 34.0;
    final drawableWidth = math.max(size.width - (padding * 2), 1);
    final drawableHeight = math.max(size.height - (padding * 2), 1);
    final x = padding +
        ((point.longitude - minLng) / (maxLng - minLng)) * drawableWidth;
    final y = padding +
        ((maxLat - point.latitude) / (maxLat - minLat)) * drawableHeight;
    return Offset(x, y);
  }
}

class _TrackingBadge extends StatelessWidget {
  const _TrackingBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _TrackingEtaPill extends StatelessWidget {
  const _TrackingEtaPill({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          '$minutes min ETA',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _TrackingInfoChip extends StatelessWidget {
  const _TrackingInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

_LatLng? _firstPoint(
  double? primaryLatitude,
  double? primaryLongitude,
  double? fallbackLatitude,
  double? fallbackLongitude,
) {
  if (primaryLatitude != null && primaryLongitude != null) {
    return _LatLng(primaryLatitude, primaryLongitude);
  }
  if (fallbackLatitude != null && fallbackLongitude != null) {
    return _LatLng(fallbackLatitude, fallbackLongitude);
  }
  return null;
}

Uri? _routeMapsUri({
  required _LatLng? storePoint,
  required _LatLng? customerPoint,
  required _LatLng? riderPoint,
}) {
  final origin = riderPoint ?? storePoint;
  final destination = customerPoint ?? storePoint ?? riderPoint;
  if (origin == null || destination == null) {
    return null;
  }
  return Uri.https('www.mapbox.com', '/directions/', {
    'origin': '${origin.longitude},${origin.latitude}',
    'destination': '${destination.longitude},${destination.latitude}',
  });
}

int? _liveEtaMinutes({
  required OrderSummary order,
  required _LatLng? riderPoint,
  required _LatLng? customerPoint,
  required double fallbackDistanceKm,
}) {
  if (order.etaMinutes != null) {
    return order.etaMinutes!.clamp(0, 240);
  }
  final distanceKm = riderPoint != null && customerPoint != null
      ? _distanceKm(riderPoint, customerPoint)
      : fallbackDistanceKm;
  if (distanceKm <= 0) {
    return null;
  }
  return math.max(4, (distanceKm / 22 * 60).ceil());
}

double _distanceKm(_LatLng a, _LatLng b) {
  const earthRadiusKm = 6371.0;
  final dLat = _degreesToRadians(b.latitude - a.latitude);
  final dLng = _degreesToRadians(b.longitude - a.longitude);
  final lat1 = _degreesToRadians(a.latitude);
  final lat2 = _degreesToRadians(b.latitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return earthRadiusKm * 2 * math.asin(math.sqrt(h));
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180;

_LatLng _centerPoint(List<_LatLng> points) {
  final latitude =
      points.fold<double>(0, (sum, point) => sum + point.latitude) /
          points.length;
  final longitude =
      points.fold<double>(0, (sum, point) => sum + point.longitude) /
          points.length;
  return _LatLng(latitude, longitude);
}

double? _storeDistanceFromAddress(
  CatalogItem item,
  CustomerAddress? address,
) {
  if (item.storeLatitude == null ||
      item.storeLongitude == null ||
      address?.latitude == null ||
      address?.longitude == null) {
    return null;
  }

  return _distanceKm(
    _LatLng(item.storeLatitude!, item.storeLongitude!),
    _LatLng(address!.latitude!, address.longitude!),
  );
}

double _fuelDeliveryCost(double distanceKm) {
  const litersPerKm = 0.067;
  const fuelPricePerLiter = 1500.0;
  return distanceKm * litersPerKm * fuelPricePerLiter;
}

String _formatNaira(double value) {
  return 'NGN ${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}';
}

String _availabilityLabel(bool isAvailable) {
  return isAvailable ? 'Available' : 'Unavailable';
}

String _averageStoreRating(
  String storeId,
  List<OrderReviewSummary> reviews,
) {
  final storeReviews = _reviewsForStore(storeId, reviews);
  if (storeReviews.isEmpty) {
    return 'New';
  }

  final total = storeReviews.fold<int>(
    0,
    (sum, review) => sum + review.rating,
  );
  return '${(total / storeReviews.length).toStringAsFixed(1)} avg';
}

String? _averageProductRating(List<ProductReviewSummary> reviews) {
  if (reviews.isEmpty) {
    return null;
  }
  final total = reviews.fold<int>(0, (sum, review) => sum + review.rating);
  return '${(total / reviews.length).toStringAsFixed(1)} item';
}

List<OrderReviewSummary> _reviewsForStore(
  String storeId,
  List<OrderReviewSummary> reviews,
) {
  final storeReviews =
      reviews.where((review) => review.storeId == storeId).toList();
  storeReviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return storeReviews;
}

double? _storeRatingValue(
  String storeId,
  List<OrderReviewSummary> reviews,
) {
  final storeReviews = _reviewsForStore(storeId, reviews);
  if (storeReviews.isEmpty) {
    return null;
  }

  final total = storeReviews.fold<int>(
    0,
    (sum, review) => sum + review.rating,
  );
  return total / storeReviews.length;
}

bool _canReorderSamePrice(
  List<OrderLineItem> items,
  Map<String, CatalogItem> catalogByProductId,
) {
  if (items.isEmpty) {
    return false;
  }

  String? storeId;
  for (final item in items) {
    final catalogItem = catalogByProductId[item.productId];
    if (catalogItem == null ||
        !catalogItem.isAvailable ||
        catalogItem.quantityAvailable < item.quantity ||
        (catalogItem.price - item.unitPrice).abs() > 0.01) {
      return false;
    }
    storeId ??= catalogItem.storeId;
    if (catalogItem.storeId != storeId) {
      return false;
    }
  }
  return true;
}
