part of '../../main.dart';

class _InventoryMovementDialog extends StatelessWidget {
  const _InventoryMovementDialog({
    required this.repository,
    required this.product,
  });

  final PlatformRepository repository;
  final StoreInventoryItem product;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${product.name} history'),
      content: SizedBox(
        width: 520,
        child: StreamBuilder<List<InventoryMovement>>(
          stream: repository.watchProductInventoryMovements(product.productId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('History failed: ${snapshot.error}');
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final movements = snapshot.data ?? const <InventoryMovement>[];
            if (movements.isEmpty) {
              return const Text('No stock movement recorded yet.');
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final movement in movements)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        movement.quantityDelta >= 0
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                      ),
                      title: Text(
                        '${movement.quantityDelta > 0 ? '+' : ''}${movement.quantityDelta} '
                        '${_humanStatus(movement.reason)}',
                      ),
                      subtitle: Text(
                        [
                          _formatDateTime(movement.createdAt),
                          if (movement.note != null &&
                              movement.note!.trim().isNotEmpty)
                            movement.note!,
                        ].join(' | '),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _StockAdjustmentDialog extends StatefulWidget {
  const _StockAdjustmentDialog({required this.product});

  final StoreInventoryItem product;

  @override
  State<_StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<_StockAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  String _mode = 'stock_in';

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final quantity = int.parse(_quantityController.text.trim());
    final delta = _mode == 'stock_in' ? quantity : -quantity;
    Navigator.of(context).pop(
      _StockAdjustment(
        delta: delta,
        reason: _mode == 'stock_in' ? 'stock_in' : 'correction',
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Adjust ${widget.product.name}'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'stock_in',
                    icon: Icon(Icons.add),
                    label: Text('Stock in'),
                  ),
                  ButtonSegment(
                    value: 'correction',
                    icon: Icon(Icons.remove),
                    label: Text('Correction'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final quantity = int.tryParse(value?.trim() ?? '');
                  if (quantity == null || quantity <= 0) {
                    return 'Enter a quantity above zero';
                  }
                  if (_mode == 'correction' &&
                      quantity > widget.product.quantityOnHand) {
                    return 'Cannot reduce below zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                ),
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
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _StockAdjustment {
  const _StockAdjustment({
    required this.delta,
    required this.reason,
    this.note,
  });

  final int delta;
  final String reason;
  final String? note;
}
