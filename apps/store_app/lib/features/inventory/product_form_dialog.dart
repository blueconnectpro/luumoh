part of '../../main.dart';

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({
    required this.repository,
    required this.storeId,
  });

  final PlatformRepository repository;
  final String storeId;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;
  late final TextEditingController _priceController;
  late final TextEditingController _initialStockController;
  late final TextEditingController _skuController;
  late final TextEditingController _reorderController;
  late final TextEditingController _imageUrlController;
  late bool _isAvailable;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _categoryController = TextEditingController(text: 'general');
    _priceController = TextEditingController();
    _initialStockController = TextEditingController(text: '10');
    _skuController = TextEditingController();
    _reorderController = TextEditingController(text: '5');
    _imageUrlController = TextEditingController();
    _isAvailable = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _initialStockController.dispose();
    _skuController.dispose();
    _reorderController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      _ProductDraft(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _categoryController.text.trim().isEmpty
            ? 'general'
            : _categoryController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        initialStock: int.parse(_initialStockController.text.trim()),
        reorderLevel: int.parse(_reorderController.text.trim()),
        sku: _skuController.text.trim().isEmpty
            ? null
            : _skuController.text.trim(),
        imageUrl: _primaryImageUrl(
          _imageUrlsFromController(_imageUrlController),
        ),
        imageUrls: _imageUrlsFromController(_imageUrlController),
        isAvailable: _isAvailable,
      ),
    );
  }

  Future<void> _uploadImages() async {
    final files = await _pickProductImages();
    if (files.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isUploadingImage = true);
    try {
      final uploadedUrls = <String>[];
      for (final file in files) {
        final imageUrl = await widget.repository.uploadProductImage(
          storeId: widget.storeId,
          fileName: file.name,
          bytes: file.bytes,
          contentType: _contentTypeForFile(file.name),
        );
        uploadedUrls.add(imageUrl);
      }
      final urls = {
        ..._imageUrlsFromController(_imageUrlController),
        ...uploadedUrls,
      }.toList(growable: false);
      _imageUrlController.text = urls.join('\n');
      messenger.showSnackBar(
        SnackBar(content: Text('${uploadedUrls.length} image(s) uploaded')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Image upload failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add product'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Product name',
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredText,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Detailed description',
                    helperText: 'Ingredients, sizes, prep notes, allergens',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 4,
                  maxLines: 8,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredText,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    border: OutlineInputBorder(),
                  ),
                  validator: _positiveNumber,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _initialStockController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Initial stock',
                          border: OutlineInputBorder(),
                        ),
                        validator: _positiveInteger,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _reorderController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Reorder level',
                          border: OutlineInputBorder(),
                        ),
                        validator: _positiveInteger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _skuController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'SKU',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _imageUrlController,
                  textInputAction: TextInputAction.done,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Gallery image URLs',
                    helperText: 'One URL per line. The first image is primary.',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                _ProductImagePreviewStrip(
                  imageUrls: _imageUrlsFromController(_imageUrlController),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isUploadingImage ? null : _uploadImages,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    _isUploadingImage
                        ? 'Uploading...'
                        : 'Upload product images',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available to customers'),
                  value: _isAvailable,
                  onChanged: (value) => setState(() => _isAvailable = value),
                ),
              ],
            ),
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
          child: const Text('Create product'),
        ),
      ],
    );
  }
}

class _ProductImagePreviewStrip extends StatelessWidget {
  const _ProductImagePreviewStrip({required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: imageUrls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final url = imageUrls[index];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 74,
                  height: 74,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 74,
                    height: 74,
                    color: const Color(0xfff3f4f6),
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              if (index == 0)
                Positioned(
                  left: 4,
                  top: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        'Primary',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductDraft {
  const _ProductDraft({
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.initialStock,
    required this.reorderLevel,
    required this.isAvailable,
    this.sku,
    this.imageUrl,
    this.imageUrls = const [],
  });

  final String name;
  final String description;
  final String category;
  final double price;
  final int initialStock;
  final int reorderLevel;
  final bool isAvailable;
  final String? sku;
  final String? imageUrl;
  final List<String> imageUrls;
}
