part of '../../main.dart';

class _AddressPage extends StatefulWidget {
  const _AddressPage({
    required this.initialAddresses,
    required this.addressesStream,
    required this.selectedAddressId,
    required this.addressController,
    required this.draftAddressPoint,
    required this.hasMapboxToken,
    required this.addressError,
    required this.isAddressLoading,
    required this.isSavingAddress,
    required this.isUpdatingAddress,
    required this.isResolvingAddress,
    required this.onAddressTextChanged,
    required this.onUseCurrentLocation,
    required this.onFindTypedAddress,
    required this.onSaveAddress,
    required this.onSelectAddress,
    required this.onSetDefaultAddress,
    required this.onDeleteAddress,
    required this.onUpdateAddress,
  });

  final List<CustomerAddress> initialAddresses;
  final Stream<List<CustomerAddress>> addressesStream;
  final String? selectedAddressId;
  final TextEditingController addressController;
  final MapboxPoint? draftAddressPoint;
  final bool hasMapboxToken;
  final Object? addressError;
  final bool isAddressLoading;
  final bool isSavingAddress;
  final bool isUpdatingAddress;
  final bool isResolvingAddress;
  final VoidCallback onAddressTextChanged;
  final Future<MapboxPoint?> Function(VoidCallback refresh)
      onUseCurrentLocation;
  final Future<MapboxPoint?> Function(VoidCallback refresh) onFindTypedAddress;
  final Future<void> Function(VoidCallback refresh) onSaveAddress;
  final ValueChanged<CustomerAddress> onSelectAddress;
  final Future<void> Function(CustomerAddress address) onSetDefaultAddress;
  final Future<void> Function(CustomerAddress address) onDeleteAddress;
  final Future<void> Function({
    required CustomerAddress address,
    required String label,
    required String addressText,
    required MapboxPoint? point,
    required bool isDefault,
  }) onUpdateAddress;

  @override
  State<_AddressPage> createState() => _AddressPageState();
}

class _AddressPageState extends State<_AddressPage> {
  late String? _selectedAddressId = widget.selectedAddressId;
  late MapboxPoint? _mapPoint = widget.draftAddressPoint;
  var _isResolving = false;
  var _isSaving = false;
  var _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    final isBusy = _isResolving || _isSaving || _isUpdating;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Delivery address'),
        actions: [
          if (isBusy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: StreamBuilder<List<CustomerAddress>>(
        stream: widget.addressesStream,
        initialData: widget.initialAddresses,
        builder: (context, snapshot) {
          final addresses = snapshot.data ?? widget.initialAddresses;
          final selected = _findAddressById(addresses, _selectedAddressId) ??
              _preferredAddress(addresses);
          final selectedPoint = _mapPoint ??
              (selected?.latitude == null || selected?.longitude == null
                  ? null
                  : MapboxPoint(
                      latitude: selected!.latitude!,
                      longitude: selected.longitude!,
                    ));
          final suggestionText = widget.addressController.text.trim().isNotEmpty
              ? widget.addressController.text.trim()
              : selected?.address;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _AddressMapPreview(
                point: selectedPoint,
                enabled: widget.hasMapboxToken,
              ),
              const SizedBox(height: 12),
              _BestAddressSuggestionCard(
                suggestion: suggestionText,
                isResolving: _isResolving || widget.isResolvingAddress,
                onSuggest: isBusy ? null : _findTypedAddress,
                onUseCurrent: isBusy ? null : _useCurrentLocation,
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: widget.addressController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: isBusy ? null : (_) => _findTypedAddress(),
                    onChanged: (_) {
                      setState(() => _mapPoint = null);
                      widget.onAddressTextChanged();
                    },
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: 'Search delivery address',
                      hintText: 'Street, area, city',
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Find address',
                        onPressed: isBusy ? null : _findTypedAddress,
                        icon: const Icon(Icons.travel_explore),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Search or use GPS to pin coordinates for delivery pricing.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : _useCurrentLocation,
                    icon: const Icon(Icons.my_location_outlined),
                    label: Text(_isResolving ? 'Finding...' : 'Use GPS'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : _findTypedAddress,
                    icon: const Icon(Icons.place_outlined),
                    label: const Text('Pick match'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : _useTypedAddress,
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: const Text('Typed only'),
                  ),
                  FilledButton.icon(
                    onPressed: isBusy ? null : _saveAddress,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(_isSaving ? 'Saving...' : 'Save address'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _AddressBookSection(
                addresses: addresses,
                selectedAddressId: _selectedAddressId,
                error: widget.addressError ?? snapshot.error,
                isLoading: widget.isAddressLoading &&
                    snapshot.connectionState == ConnectionState.waiting,
                isUpdating: isBusy || widget.isUpdatingAddress,
                onSelectAddress: _selectSavedAddress,
                onSetDefaultAddress: _setDefaultAddress,
                onDeleteAddress: _deleteAddress,
                onEditAddress: _editAddress,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _useCurrentLocation({String? label}) async {
    setState(() => _isResolving = true);
    final point = await widget.onUseCurrentLocation(() {
      if (mounted) {
        setState(() {});
      }
    });
    if (!mounted) {
      return;
    }
    setState(() {
      _mapPoint = point ?? _mapPoint;
      _selectedAddressId = null;
      _isResolving = false;
    });
    if (label != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(label)),
      );
    }
  }

  Future<void> _findTypedAddress() async {
    setState(() => _isResolving = true);
    final point = await widget.onFindTypedAddress(() {
      if (mounted) {
        setState(() {});
      }
    });
    if (!mounted) {
      return;
    }
    setState(() {
      _mapPoint = point ?? _mapPoint;
      _selectedAddressId = null;
      _isResolving = false;
    });
  }

  void _useTypedAddress() {
    final address = widget.addressController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a delivery address first')),
      );
      return;
    }

    widget.onAddressTextChanged();
    setState(() {
      _mapPoint = null;
      _selectedAddressId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Written address ready')),
    );
  }

  Future<void> _saveAddress() async {
    setState(() => _isSaving = true);
    await widget.onSaveAddress(() {
      if (mounted) {
        setState(() {});
      }
    });
    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  void _selectSavedAddress(CustomerAddress address) {
    widget.onSelectAddress(address);
    setState(() {
      _selectedAddressId = address.id;
      _mapPoint = address.latitude == null || address.longitude == null
          ? null
          : MapboxPoint(
              latitude: address.latitude!,
              longitude: address.longitude!,
            );
    });
  }

  Future<void> _setDefaultAddress(CustomerAddress address) async {
    setState(() => _isUpdating = true);
    await widget.onSetDefaultAddress(address);
    if (mounted) {
      setState(() {
        _selectedAddressId = address.id;
        _isUpdating = false;
      });
    }
  }

  Future<void> _deleteAddress(CustomerAddress address) async {
    setState(() => _isUpdating = true);
    await widget.onDeleteAddress(address);
    if (mounted) {
      setState(() {
        if (_selectedAddressId == address.id) {
          _selectedAddressId = null;
          _mapPoint = null;
        }
        _isUpdating = false;
      });
    }
  }

  Future<void> _editAddress(CustomerAddress address) async {
    final result = await showDialog<_AddressEditResult>(
      context: context,
      builder: (context) => _EditAddressDialog(address: address),
    );
    if (result == null || !mounted) {
      return;
    }

    setState(() => _isUpdating = true);
    await widget.onUpdateAddress(
      address: address,
      label: result.label,
      addressText: result.address,
      point: null,
      isDefault: result.isDefault,
    );
    if (mounted) {
      setState(() {
        _selectedAddressId = address.id;
        _isUpdating = false;
      });
    }
  }
}

class _AddressMapPreview extends StatelessWidget {
  const _AddressMapPreview({
    required this.point,
    required this.enabled,
  });

  final MapboxPoint? point;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 220,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (enabled && point != null)
              mapbox.MapWidget(
                key: ValueKey(
                  'address-map-${point!.latitude.toStringAsFixed(4)}-'
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
                  child: Icon(Icons.map_outlined, size: 52),
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
                  child: Icon(Icons.location_on, color: Color(0xff2563eb)),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        point == null
                            ? Icons.info_outline
                            : Icons.check_circle_outline,
                        color: point == null
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          point == null
                              ? enabled
                                  ? 'No delivery pin yet. Search or use GPS.'
                                  : 'Mapbox token is not configured.'
                              : 'Pinned at ${point!.latitude.toStringAsFixed(5)}, ${point!.longitude.toStringAsFixed(5)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
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

class _BestAddressSuggestionCard extends StatelessWidget {
  const _BestAddressSuggestionCard({
    required this.suggestion,
    required this.isResolving,
    required this.onSuggest,
    required this.onUseCurrent,
  });

  final String? suggestion;
  final bool isResolving;
  final VoidCallback? onSuggest;
  final VoidCallback? onUseCurrent;

  @override
  Widget build(BuildContext context) {
    final text = suggestion == null || suggestion!.trim().isEmpty
        ? 'Type your street, area, or landmark to find the best Mapbox match.'
        : suggestion!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Best address suggestion',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(text),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: isResolving ? null : onSuggest,
                  icon: const Icon(Icons.near_me_outlined),
                  label: Text(isResolving ? 'Checking...' : 'Find best match'),
                ),
                OutlinedButton.icon(
                  onPressed: isResolving ? null : onUseCurrent,
                  icon: const Icon(Icons.my_location_outlined),
                  label: const Text('Use current address'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressBookSection extends StatelessWidget {
  const _AddressBookSection({
    required this.addresses,
    required this.selectedAddressId,
    required this.error,
    required this.isLoading,
    required this.isUpdating,
    required this.onSelectAddress,
    required this.onSetDefaultAddress,
    required this.onDeleteAddress,
    this.onEditAddress,
  });

  final List<CustomerAddress> addresses;
  final String? selectedAddressId;
  final Object? error;
  final bool isLoading;
  final bool isUpdating;
  final ValueChanged<CustomerAddress> onSelectAddress;
  final ValueChanged<CustomerAddress> onSetDefaultAddress;
  final ValueChanged<CustomerAddress> onDeleteAddress;
  final ValueChanged<CustomerAddress>? onEditAddress;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Text(
        'Saved addresses failed to load: $error',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    if (isLoading) {
      return const LinearProgressIndicator();
    }

    if (addresses.isEmpty) {
      return Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.bookmark_add_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Text('Save this address for faster checkout next time.'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Saved addresses', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final address in addresses)
          _SavedAddressCard(
            address: address,
            isSelected: selectedAddressId == address.id,
            isUpdating: isUpdating,
            onSelect: () => onSelectAddress(address),
            onSetDefault: () => onSetDefaultAddress(address),
            onDelete: () => onDeleteAddress(address),
            onEdit:
                onEditAddress == null ? null : () => onEditAddress!(address),
          ),
      ],
    );
  }
}

class _SavedAddressCard extends StatelessWidget {
  const _SavedAddressCard({
    required this.address,
    required this.isSelected,
    required this.isUpdating,
    required this.onSelect,
    required this.onSetDefault,
    required this.onDelete,
    required this.onEdit,
  });

  final CustomerAddress address;
  final bool isSelected;
  final bool isUpdating;
  final VoidCallback onSelect;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPin = address.latitude != null && address.longitude != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: isUpdating ? null : onSelect,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: isSelected
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    child: Icon(
                      address.isDefault
                          ? Icons.bookmark_added
                          : Icons.location_on_outlined,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                address.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          address.address,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    avatar: Icon(
                      hasPin ? Icons.pin_drop_outlined : Icons.warning_amber,
                      size: 18,
                    ),
                    label: Text(hasPin ? 'Map pinned' : 'No map pin'),
                  ),
                  if (address.isDefault)
                    const Chip(
                      avatar: Icon(Icons.star, size: 18),
                      label: Text('Default'),
                    ),
                  IconButton.outlined(
                    tooltip: 'Edit address',
                    onPressed: isUpdating ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton.outlined(
                    tooltip: 'Make default',
                    onPressed:
                        isUpdating || address.isDefault ? null : onSetDefault,
                    icon: const Icon(Icons.star_outline),
                  ),
                  IconButton.outlined(
                    tooltip: 'Delete address',
                    onPressed: isUpdating ? null : onDelete,
                    icon: const Icon(Icons.delete_outline),
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

class _SaveAddressDialog extends StatefulWidget {
  const _SaveAddressDialog();

  @override
  State<_SaveAddressDialog> createState() => _SaveAddressDialogState();
}

class _SaveAddressDialogState extends State<_SaveAddressDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController(text: 'Home');

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(_labelController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save address'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _labelController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Label',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Required' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _AddressEditResult {
  const _AddressEditResult({
    required this.label,
    required this.address,
    required this.isDefault,
  });

  final String label;
  final String address;
  final bool isDefault;
}

class _EditAddressDialog extends StatefulWidget {
  const _EditAddressDialog({required this.address});

  final CustomerAddress address;

  @override
  State<_EditAddressDialog> createState() => _EditAddressDialogState();
}

class _EditAddressDialogState extends State<_EditAddressDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _labelController =
      TextEditingController(text: widget.address.label);
  late final _addressController =
      TextEditingController(text: widget.address.address);
  late var _isDefault = widget.address.isDefault;

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _AddressEditResult(
        label: _labelController.text.trim(),
        address: _addressController.text.trim(),
        isDefault: _isDefault,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit address'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _isDefault,
                onChanged: (value) =>
                    setState(() => _isDefault = value ?? false),
                title: const Text('Use as default address'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save changes'),
        ),
      ],
    );
  }
}

class _MapboxAddressResultsSheet extends StatelessWidget {
  const _MapboxAddressResultsSheet({required this.results});

  final List<MapboxAddressResult> results;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: results.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.travel_explore, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Choose address',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              );
            }
            final result = results[index - 1];
            return Card(
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.place_outlined,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(result.name),
                subtitle: Text(
                  result.address,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(result),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CheckoutPage extends StatefulWidget {
  const _CheckoutPage({
    required this.checkout,
    required this.orderId,
    required this.repository,
  });

  final MonnifyCheckout checkout;
  final String orderId;
  final PlatformRepository repository;

  @override
  State<_CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<_CheckoutPage> {
  late final MonnifyPaymentService _payments;
  Timer? _confirmTimer;
  StreamSubscription<OrderSummary?>? _orderSubscription;
  bool _isConfirming = false;
  bool _hasReturnedTerminalOrder = false;
  String? _lastConfirmError;
  String? _sdkStatusMessage;
  late final DateTime _checkoutStartedAt;

  @override
  void initState() {
    super.initState();
    _checkoutStartedAt = DateTime.now();
    _payments = MonnifyPaymentService(Supabase.instance.client);
    _orderSubscription =
        widget.repository.watchOrder(widget.orderId).listen(_handleOrderUpdate);
    _confirmTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _confirmPayment(silent: true);
    });
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    _orderSubscription?.cancel();
    super.dispose();
  }

  void _handleOrderUpdate(OrderSummary? order) {
    if (order == null || !_isTerminalPaymentStatus(order.paymentStatus)) {
      return;
    }
    if (_hasReturnedTerminalOrder || !mounted) {
      return;
    }

    _hasReturnedTerminalOrder = true;
    _confirmTimer?.cancel();
    Navigator.of(context).pop(order);
  }

  Future<void> _handleSdkComplete(Map<String, dynamic> response) async {
    setState(() {
      _sdkStatusMessage =
          _sdkStatusText(response, fallback: 'Payment finished');
    });
    await _confirmPayment(silent: false);
  }

  Future<void> _handleSdkClose(Map<String, dynamic> response) async {
    setState(() {
      _sdkStatusMessage = _sdkStatusText(response, fallback: 'Checkout closed');
    });
    await _confirmPayment(silent: true);
  }

  Future<void> _confirmPayment({bool silent = false}) async {
    if (_isConfirming) {
      return;
    }

    setState(() {
      _isConfirming = true;
      _lastConfirmError = null;
    });

    try {
      final confirmation = await _payments.confirmPayment(
        orderId: widget.orderId,
        paymentReference: widget.checkout.paymentReference,
      );
      if (!mounted) {
        return;
      }
      if (!silent && confirmation.paymentStatus == 'pending') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmation.providerStatus == null
                  ? 'Payment is still pending. Keep this screen open or verify again from Orders.'
                  : 'Monnify status: ${confirmation.providerStatus}',
            ),
          ),
        );
      }
      if (_isTerminalPaymentStatus(confirmation.paymentStatus)) {
        _confirmTimer?.cancel();
        final order = await widget.repository.fetchOrder(widget.orderId);
        if (order != null) {
          _handleOrderUpdate(order);
        }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _lastConfirmError =
              'Monnify verification timed out. Use Verify again; if you were debited, the order can still update from the webhook.';
          final text = error.toString();
          if (!text.toLowerCase().contains('timeout') &&
              !text.toLowerCase().contains('timed out')) {
            _lastConfirmError = text;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isConfirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWaitedLong = DateTime.now().difference(_checkoutStartedAt) >
        const Duration(minutes: 2);
    return PopScope(
      canPop: !_isConfirming,
      child: Scaffold(
        backgroundColor: const Color(0xfff7f8fb),
        appBar: AppBar(
          backgroundColor: const Color(0xff303030),
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: const Text('Secure checkout'),
          actions: [
            TextButton.icon(
              onPressed:
                  _isConfirming ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ColoredBox(
                      color: Colors.white,
                      child: MonnifyCheckoutFrame(
                        checkout: widget.checkout,
                        onComplete: _handleSdkComplete,
                        onClose: _handleSdkClose,
                        onError: (message) =>
                            setState(() => _sdkStatusMessage = message),
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.white,
                elevation: 10,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StreamBuilder<OrderSummary?>(
                        stream: widget.repository.watchOrder(widget.orderId),
                        builder: (context, snapshot) {
                          final order = snapshot.data;
                          final statusText = order == null
                              ? 'Waiting for order status'
                              : order.paymentStatus == 'paid'
                                  ? 'Payment confirmed'
                                  : order.paymentStatus == 'failed' ||
                                          order.paymentStatus == 'expired'
                                      ? 'Payment not completed'
                                      : hasWaitedLong
                                          ? 'Still waiting. Verify again or retry from Orders if Monnify timed out.'
                                          : 'Waiting for Monnify confirmation';
                          final icon = order?.paymentStatus == 'paid'
                              ? Icons.check_circle
                              : order?.paymentStatus == 'failed' ||
                                      order?.paymentStatus == 'expired'
                                  ? Icons.error_outline
                                  : Icons.lock_clock_outlined;
                          final color = order?.paymentStatus == 'paid'
                              ? Colors.green.shade700
                              : order?.paymentStatus == 'failed' ||
                                      order?.paymentStatus == 'expired'
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary;

                          return Row(
                            children: [
                              Icon(icon, color: color),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  statusText,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              TextButton.icon(
                                onPressed:
                                    _isConfirming ? null : _confirmPayment,
                                icon: _isConfirming
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.verified_outlined),
                                label: const Text('Verify'),
                              ),
                            ],
                          );
                        },
                      ),
                      if (_sdkStatusMessage != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _sdkStatusMessage!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      if (_lastConfirmError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _lastConfirmError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        'Reference: ${widget.checkout.paymentReference}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _sdkStatusText(
  Map<String, dynamic> response, {
  required String fallback,
}) {
  final status = response['paymentStatus'] ?? response['status'];
  final message = response['responseMessage'] ?? response['message'];
  return [
    fallback,
    if (status != null) 'Status: $status',
    if (message != null) '$message',
  ].join(' | ');
}
