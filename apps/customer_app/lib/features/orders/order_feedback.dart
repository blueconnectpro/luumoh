part of '../../main.dart';

class _OrderIssueDraft {
  const _OrderIssueDraft({
    required this.category,
    required this.message,
  });

  final String category;
  final String message;
}

class _OrderReviewDraft {
  const _OrderReviewDraft({
    required this.rating,
    this.itemReviews = const [],
    this.comment,
  });

  final int rating;
  final List<_ItemReviewDraft> itemReviews;
  final String? comment;
}

class _ItemReviewDraft {
  const _ItemReviewDraft({
    required this.productId,
    required this.rating,
    this.comment,
  });

  final String productId;
  final int rating;
  final String? comment;
}

class _RiderReviewDraft {
  const _RiderReviewDraft({
    required this.rating,
    this.comment,
  });

  final int rating;
  final String? comment;
}

class _OrderReviewsList extends StatelessWidget {
  const _OrderReviewsList({
    required this.repository,
    required this.orderId,
  });

  final PlatformRepository repository;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderReviewSummary>>(
      stream: repository.watchOrderReviewsForOrder(orderId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text('Review failed: ${snapshot.error}'),
          );
        }

        final reviews = snapshot.data ?? const <OrderReviewSummary>[];
        if (reviews.isEmpty) {
          return const SizedBox.shrink();
        }

        final review = reviews.first;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_outline, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your review',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(_stars(review.rating)),
                ],
              ),
              if (review.comment != null && review.comment!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(review.comment!),
              ],
              const SizedBox(height: 4),
              Text(
                'Updated ${_formatDateTime(review.updatedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderIssuesList extends StatelessWidget {
  const _OrderIssuesList({
    required this.repository,
    required this.orderId,
  });

  final PlatformRepository repository;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderIssueSummary>>(
      stream: repository.watchOrderIssuesForOrder(orderId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text('Support issues failed: ${snapshot.error}'),
          );
        }

        final issues = snapshot.data ?? const <OrderIssueSummary>[];
        if (issues.isEmpty) {
          return const SizedBox.shrink();
        }

        final latest = issues.first;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.support_agent_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Support: ${_humanStatus(latest.status)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '${issues.length} issue${issues.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final issue in issues.take(3)) ...[
                Text(
                  '${_humanStatus(issue.category)} | ${_humanStatus(issue.status)}',
                ),
                Text(
                  issue.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (issue.adminNote != null && issue.adminNote!.isNotEmpty)
                  Text(
                    'Admin note: ${issue.adminNote}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Text(
                  _formatDateTime(issue.updatedAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (issue != issues.take(3).last) const Divider(),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReviewOrderDialog extends StatefulWidget {
  const _ReviewOrderDialog({
    required this.order,
    required this.items,
  });

  final OrderSummary order;
  final List<OrderLineItem> items;

  @override
  State<_ReviewOrderDialog> createState() => _ReviewOrderDialogState();
}

class _ReviewOrderDialogState extends State<_ReviewOrderDialog> {
  final _commentController = TextEditingController();
  final _itemCommentControllers = <String, TextEditingController>{};
  final _itemRatings = <String, int>{};
  var _rating = 5;

  @override
  void initState() {
    super.initState();
    for (final item in widget.items) {
      _itemRatings[item.productId] = 5;
      _itemCommentControllers[item.productId] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    for (final controller in _itemCommentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _OrderReviewDraft(
        rating: _rating,
        itemReviews: [
          for (final item in widget.items)
            _ItemReviewDraft(
              productId: item.productId,
              rating: _itemRatings[item.productId] ?? _rating,
              comment: _trimmedOrNull(
                _itemCommentControllers[item.productId]?.text,
              ),
            ),
        ],
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Review order #${_shortId(widget.order.id)}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.order.storeName),
              const SizedBox(height: 12),
              Text(
                'Store experience',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _RatingChoiceGroup(
                rating: _rating,
                onChanged: (rating) => setState(() => _rating = rating),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commentController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Store/order comment',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.items.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Items',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final item in widget.items) ...[
                  _ItemReviewTile(
                    item: item,
                    rating: _itemRatings[item.productId] ?? 5,
                    commentController: _itemCommentControllers[item.productId]!,
                    onRatingChanged: (rating) => setState(
                      () => _itemRatings[item.productId] = rating,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.star_outline),
          label: const Text('Submit'),
        ),
      ],
    );
  }
}

class _ReviewDeliveryDialog extends StatefulWidget {
  const _ReviewDeliveryDialog({required this.order});

  final OrderSummary order;

  @override
  State<_ReviewDeliveryDialog> createState() => _ReviewDeliveryDialogState();
}

class _ReviewDeliveryDialogState extends State<_ReviewDeliveryDialog> {
  final _commentController = TextEditingController();
  var _rating = 5;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _RiderReviewDraft(
        rating: _rating,
        comment: _trimmedOrNull(_commentController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final riderName = widget.order.riderName?.trim();
    return AlertDialog(
      title: const Text('Rate delivery'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      child: const Icon(Icons.delivery_dining),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        riderName == null || riderName.isEmpty
                            ? 'How was your delivery?'
                            : 'How was delivery by $riderName?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _RatingChoiceGroup(
              rating: _rating,
              onChanged: (rating) => setState(() => _rating = rating),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Delivery comment',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.star_outline),
          label: const Text('Save delivery rating'),
        ),
      ],
    );
  }
}

class _RatingChoiceGroup extends StatelessWidget {
  const _RatingChoiceGroup({
    required this.rating,
    required this.onChanged,
  });

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in const [1, 2, 3, 4, 5])
          ChoiceChip(
            label: Text(_stars(value)),
            selected: rating == value,
            onSelected: (_) => onChanged(value),
          ),
      ],
    );
  }
}

class _ItemReviewTile extends StatelessWidget {
  const _ItemReviewTile({
    required this.item,
    required this.rating,
    required this.commentController,
    required this.onRatingChanged,
  });

  final OrderLineItem item;
  final int rating;
  final TextEditingController commentController;
  final ValueChanged<int> onRatingChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${item.quantity} x ${item.productName}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            _RatingChoiceGroup(
              rating: rating,
              onChanged: onRatingChanged,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: commentController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Item comment',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class _ReportIssueDialog extends StatefulWidget {
  const _ReportIssueDialog({required this.order});

  final OrderSummary order;

  @override
  State<_ReportIssueDialog> createState() => _ReportIssueDialogState();
}

class _ReportIssueDialogState extends State<_ReportIssueDialog> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  var _category = 'delivery_delay';

  static const _categories = [
    ('delivery_delay', 'Delivery delay'),
    ('wrong_item', 'Wrong item'),
    ('missing_item', 'Missing item'),
    ('payment', 'Payment'),
    ('refund', 'Refund'),
    ('other', 'Other'),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      _OrderIssueDraft(
        category: _category,
        message: _messageController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report issue #${_shortId(widget.order.id)}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: [
                  for (final category in _categories)
                    DropdownMenuItem(
                      value: category.$1,
                      child: Text(category.$2),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? _category),
                decoration: const InputDecoration(
                  labelText: 'Issue type',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageController,
                minLines: 3,
                maxLines: 5,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'What happened?',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 5) {
                    return 'Tell us a little more';
                  }
                  return null;
                },
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
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.support_agent_outlined),
          label: const Text('Send'),
        ),
      ],
    );
  }
}

class _DeliveryEventRow extends StatelessWidget {
  const _DeliveryEventRow({required this.event});

  final DeliveryEvent event;

  @override
  Widget build(BuildContext context) {
    final note = event.note;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.radio_button_checked, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_humanStatus(event.status)}'
                  '${event.etaMinutes == null ? '' : ' | ETA ${event.etaMinutes}m'}',
                ),
                if (note != null && note.isNotEmpty)
                  Text(
                    note,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Text(
                  _formatDateTime(event.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({
    required this.title,
    required this.message,
    this.isLoading = false,
  });

  final String title;
  final String message;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
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
    );
  }
}

String _humanStatus(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _stars(int rating) {
  final safeRating = rating.clamp(0, 5);
  return '$safeRating/5';
}
