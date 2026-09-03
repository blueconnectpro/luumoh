part of '../../main.dart';

class _CatalogStoreOption {
  const _CatalogStoreOption({
    required this.storeId,
    required this.storeName,
  });

  final String storeId;
  final String storeName;
}

class _RestaurantsPane extends StatefulWidget {
  const _RestaurantsPane({
    required this.ordersStream,
    required this.reviewsStream,
    required this.productReviewsStream,
    required this.promoCodesStream,
    required this.items,
    required this.isLoading,
    required this.error,
    required this.cart,
    required this.selectedAddress,
    required this.favoriteStoreIds,
    required this.onAdd,
    required this.onShowDetails,
    required this.onToggleFavoriteStore,
  });

  final Stream<List<OrderSummary>> ordersStream;
  final Stream<List<OrderReviewSummary>> reviewsStream;
  final Stream<List<ProductReviewSummary>> productReviewsStream;
  final Stream<List<PromoCodeSummary>> promoCodesStream;
  final List<CatalogItem> items;
  final bool isLoading;
  final Object? error;
  final Map<String, int> cart;
  final CustomerAddress? selectedAddress;
  final Set<String> favoriteStoreIds;
  final ValueChanged<CatalogItem> onAdd;
  final ValueChanged<CatalogItem> onShowDetails;
  final ValueChanged<String> onToggleFavoriteStore;

  @override
  State<_RestaurantsPane> createState() => _RestaurantsPaneState();
}

class _RestaurantsPaneState extends State<_RestaurantsPane> {
  final _searchController = TextEditingController();
  var _selectedCategory = 'all';
  var _sortMode = 'recommended';
  var _showRestaurants = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.error != null) {
      return _InlineState(
        title: 'Restaurants failed to load',
        message: widget.error.toString(),
      );
    }

    if (widget.isLoading) {
      return const _InlineState(
        title: 'Loading restaurants',
        message: 'Fetching stores and menus...',
        isLoading: true,
      );
    }

    final byStore = <String, List<CatalogItem>>{};
    for (final item in widget.items) {
      byStore.putIfAbsent(item.storeId, () => []).add(item);
    }
    final stores = byStore.entries.toList()
      ..sort(
        (a, b) => a.value.first.storeName.compareTo(b.value.first.storeName),
      );

    if (stores.isEmpty) {
      return const _InlineState(
        title: 'No restaurants yet',
        message: 'Stores with available inventory will appear here.',
      );
    }

    return StreamBuilder<List<OrderReviewSummary>>(
      stream: widget.reviewsStream,
      builder: (context, reviewSnapshot) {
        final reviews = reviewSnapshot.data ?? const <OrderReviewSummary>[];
        return StreamBuilder<List<ProductReviewSummary>>(
          stream: widget.productReviewsStream,
          builder: (context, productReviewSnapshot) {
            final productReviews =
                productReviewSnapshot.data ?? const <ProductReviewSummary>[];
            return StreamBuilder<List<OrderSummary>>(
              stream: widget.ordersStream,
              builder: (context, orderSnapshot) {
                final orders = orderSnapshot.data ?? const <OrderSummary>[];
                return StreamBuilder<List<PromoCodeSummary>>(
                  stream: widget.promoCodesStream,
                  builder: (context, promoSnapshot) {
                    final activePromos =
                        _activePromoCodes(promoSnapshot.data ?? const []);
                    final dealStoreIds = activePromos
                        .map((promo) => promo.storeId)
                        .whereType<String>()
                        .toSet();
                    final restaurantStores = stores
                        .where((store) => _isRestaurantStore(store.value))
                        .toList();
                    final marketStores = stores
                        .where((store) => !_isRestaurantStore(store.value))
                        .toList();
                    final sectionStores =
                        _showRestaurants ? restaurantStores : marketStores;
                    final visibleStores = _sortRestaurantStores(
                      sectionStores
                          .where(
                            (store) =>
                                _matchesRestaurantSearch(
                                  store.value,
                                  _searchController.text,
                                ) &&
                                _matchesRestaurantCategory(
                                  store.value,
                                  _selectedCategory,
                                  dealStoreIds.contains(store.key),
                                ),
                          )
                          .toList(),
                      _sortMode,
                      widget.selectedAddress,
                    );
                    final orderAgainStores = _orderAgainStores(
                      sectionStores,
                      orders,
                    ).take(10).toList();
                    final dealStores = sectionStores
                        .where((store) => dealStoreIds.contains(store.key))
                        .take(10)
                        .toList();
                    final sectionName =
                        _showRestaurants ? 'restaurants' : 'stores';

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        Text(
                          'Restaurants',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 14),
                        _RestaurantStoreTabSwitcher(
                          showRestaurants: _showRestaurants,
                          restaurantCount: restaurantStores.length,
                          storeCount: marketStores.length,
                          onChanged: (value) => setState(() {
                            _showRestaurants = value;
                            _selectedCategory = 'all';
                          }),
                        ),
                        const SizedBox(height: 14),
                        _RestaurantSearchField(
                          controller: _searchController,
                          hintText: _showRestaurants
                              ? 'Search restaurants'
                              : 'Search stores',
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 14),
                        _RestaurantCategoryScroller(
                          selectedCategory: _selectedCategory,
                          onSelected: (value) => setState(
                            () => _selectedCategory =
                                _selectedCategory == value ? 'all' : value,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _RestaurantControlsBar(
                          sortMode: _sortMode,
                          onSortChanged: (value) =>
                              setState(() => _sortMode = value),
                        ),
                        if (orderAgainStores.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          _RestaurantRailSection(
                            title:
                                _showRestaurants ? 'Order again' : 'Shop again',
                            stores: orderAgainStores,
                            selectedAddress: widget.selectedAddress,
                            reviews: reviews,
                            productReviews: productReviews,
                            cart: widget.cart,
                            favoriteStoreIds: widget.favoriteStoreIds,
                            promoCodes: activePromos,
                            onAdd: widget.onAdd,
                            onShowDetails: widget.onShowDetails,
                            onToggleFavoriteStore: widget.onToggleFavoriteStore,
                          ),
                        ],
                        if (dealStores.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          _RestaurantRailSection(
                            title: _showRestaurants
                                ? 'Best deals for you'
                                : 'Best store deals',
                            stores: dealStores,
                            selectedAddress: widget.selectedAddress,
                            reviews: reviews,
                            productReviews: productReviews,
                            cart: widget.cart,
                            favoriteStoreIds: widget.favoriteStoreIds,
                            promoCodes: activePromos,
                            onAdd: widget.onAdd,
                            onShowDetails: widget.onShowDetails,
                            onToggleFavoriteStore: widget.onToggleFavoriteStore,
                          ),
                        ],
                        const SizedBox(height: 24),
                        _RestaurantSectionHeader(
                          title: _showRestaurants
                              ? 'All restaurants'
                              : 'All stores',
                          trailing: '${visibleStores.length}',
                        ),
                        const SizedBox(height: 10),
                        if (visibleStores.isEmpty)
                          _InlineState(
                            title: 'No matching $sectionName',
                            message: 'Try another search, category, or sort.',
                          )
                        else
                          for (final store in visibleStores) ...[
                            _RestaurantStoreCard(
                              storeItems: store.value,
                              selectedAddress: widget.selectedAddress,
                              reviews: reviews,
                              productReviews: productReviews
                                  .where(
                                      (review) => review.storeId == store.key)
                                  .toList(),
                              cart: widget.cart,
                              favoriteStoreIds: widget.favoriteStoreIds,
                              promoCodes: activePromos
                                  .where((promo) => promo.storeId == store.key)
                                  .toList(),
                              onAdd: widget.onAdd,
                              onShowDetails: widget.onShowDetails,
                              onToggleFavoriteStore:
                                  widget.onToggleFavoriteStore,
                            ),
                            const SizedBox(height: 14),
                          ],
                      ],
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

class _HomeFavoriteRestaurantsSection extends StatelessWidget {
  const _HomeFavoriteRestaurantsSection({
    required this.reviewsStream,
    required this.productReviewsStream,
    required this.stores,
    required this.selectedAddress,
    required this.favoriteStoreIds,
    required this.cart,
    required this.onAdd,
    required this.onShowDetails,
    required this.onToggleFavoriteStore,
  });

  final Stream<List<OrderReviewSummary>> reviewsStream;
  final Stream<List<ProductReviewSummary>> productReviewsStream;
  final List<MapEntry<String, List<CatalogItem>>> stores;
  final CustomerAddress? selectedAddress;
  final Set<String> favoriteStoreIds;
  final Map<String, int> cart;
  final ValueChanged<CatalogItem> onAdd;
  final ValueChanged<CatalogItem> onShowDetails;
  final ValueChanged<String> onToggleFavoriteStore;

  @override
  Widget build(BuildContext context) {
    if (stores.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<OrderReviewSummary>>(
      stream: reviewsStream,
      builder: (context, reviewSnapshot) {
        final reviews = reviewSnapshot.data ?? const <OrderReviewSummary>[];
        return StreamBuilder<List<ProductReviewSummary>>(
          stream: productReviewsStream,
          builder: (context, productReviewSnapshot) {
            final productReviews =
                productReviewSnapshot.data ?? const <ProductReviewSummary>[];
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _RestaurantRailSection(
                title: 'Your favourites',
                stores: stores,
                selectedAddress: selectedAddress,
                reviews: reviews,
                productReviews: productReviews,
                cart: cart,
                favoriteStoreIds: favoriteStoreIds,
                promoCodes: const [],
                onAdd: onAdd,
                onShowDetails: onShowDetails,
                onToggleFavoriteStore: onToggleFavoriteStore,
              ),
            );
          },
        );
      },
    );
  }
}

class _RestaurantStoreTabSwitcher extends StatelessWidget {
  const _RestaurantStoreTabSwitcher({
    required this.showRestaurants,
    required this.restaurantCount,
    required this.storeCount,
    required this.onChanged,
  });

  final bool showRestaurants;
  final int restaurantCount;
  final int storeCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _RestaurantStoreTabButton(
                label: 'Restaurants',
                count: restaurantCount,
                selected: showRestaurants,
                onTap: () => onChanged(true),
              ),
            ),
            Expanded(
              child: _RestaurantStoreTabButton(
                label: 'Stores',
                count: storeCount,
                selected: !showRestaurants,
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
                  alignment: showRestaurants
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
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

class _RestaurantStoreTabButton extends StatelessWidget {
  const _RestaurantStoreTabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      color: color,
                    ),
              ),
            ),
            const SizedBox(width: 7),
            DecoratedBox(
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
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

class _RestaurantSearchField extends StatelessWidget {
  const _RestaurantSearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
                icon: const Icon(Icons.close),
              ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}

class _RestaurantCategoryScroller extends StatelessWidget {
  const _RestaurantCategoryScroller({
    required this.selectedCategory,
    required this.onSelected,
  });

  final String selectedCategory;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _restaurantCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final category = _restaurantCategories[index];
          final selected = selectedCategory == category.value;
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onSelected(category.value),
            child: SizedBox(
              width: 76,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      category.icon,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w900 : FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RestaurantControlsBar extends StatelessWidget {
  const _RestaurantControlsBar({
    required this.sortMode,
    required this.onSortChanged,
  });

  final String sortMode;
  final ValueChanged<String> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const _RestaurantControlChip(
            icon: Icons.local_offer_outlined,
            label: 'Promotions',
          ),
          const SizedBox(width: 8),
          const _RestaurantControlChip(
            icon: Icons.directions_walk,
            label: 'Pickup',
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            initialValue: sortMode,
            tooltip: 'Sort restaurants',
            onSelected: onSortChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'recommended',
                child: Text('Recommended'),
              ),
              PopupMenuItem(
                value: 'price',
                child: Text('Delivery price'),
              ),
              PopupMenuItem(
                value: 'distance',
                child: Text('Distance'),
              ),
            ],
            child: _RestaurantControlChip(
              icon: Icons.tune,
              label: 'Sort by ${_restaurantSortLabel(sortMode)}',
              trailingIcon: Icons.keyboard_arrow_down,
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantControlChip extends StatelessWidget {
  const _RestaurantControlChip({
    required this.icon,
    required this.label,
    this.trailingIcon,
  });

  final IconData icon;
  final String label;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 3),
              Icon(trailingIcon, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _RestaurantRailSection extends StatelessWidget {
  const _RestaurantRailSection({
    required this.title,
    required this.stores,
    required this.selectedAddress,
    required this.reviews,
    required this.productReviews,
    required this.cart,
    required this.favoriteStoreIds,
    required this.promoCodes,
    required this.onAdd,
    required this.onShowDetails,
    required this.onToggleFavoriteStore,
  });

  final String title;
  final List<MapEntry<String, List<CatalogItem>>> stores;
  final CustomerAddress? selectedAddress;
  final List<OrderReviewSummary> reviews;
  final List<ProductReviewSummary> productReviews;
  final Map<String, int> cart;
  final Set<String> favoriteStoreIds;
  final List<PromoCodeSummary> promoCodes;
  final ValueChanged<CatalogItem> onAdd;
  final ValueChanged<CatalogItem> onShowDetails;
  final ValueChanged<String> onToggleFavoriteStore;

  @override
  Widget build(BuildContext context) {
    if (stores.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RestaurantSectionHeader(title: title),
        const SizedBox(height: 10),
        SizedBox(
          height: 260,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stores.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final store = stores[index];
              return SizedBox(
                width: 300,
                child: _RestaurantStoreCard(
                  storeItems: store.value,
                  selectedAddress: selectedAddress,
                  reviews: reviews,
                  productReviews: productReviews
                      .where((review) => review.storeId == store.key)
                      .toList(),
                  cart: cart,
                  favoriteStoreIds: favoriteStoreIds,
                  promoCodes: promoCodes
                      .where((promo) => promo.storeId == store.key)
                      .toList(),
                  onAdd: onAdd,
                  onShowDetails: onShowDetails,
                  onToggleFavoriteStore: onToggleFavoriteStore,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RestaurantSectionHeader extends StatelessWidget {
  const _RestaurantSectionHeader({
    required this.title,
    this.trailing,
  });

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        if (trailing != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Text(
                trailing!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RestaurantStoreCard extends StatelessWidget {
  const _RestaurantStoreCard({
    required this.storeItems,
    required this.selectedAddress,
    required this.reviews,
    required this.productReviews,
    required this.cart,
    required this.favoriteStoreIds,
    required this.promoCodes,
    required this.onAdd,
    required this.onShowDetails,
    required this.onToggleFavoriteStore,
  });

  final List<CatalogItem> storeItems;
  final CustomerAddress? selectedAddress;
  final List<OrderReviewSummary> reviews;
  final List<ProductReviewSummary> productReviews;
  final Map<String, int> cart;
  final Set<String> favoriteStoreIds;
  final List<PromoCodeSummary> promoCodes;
  final ValueChanged<CatalogItem> onAdd;
  final ValueChanged<CatalogItem> onShowDetails;
  final ValueChanged<String> onToggleFavoriteStore;

  @override
  Widget build(BuildContext context) {
    final first = storeItems.first;
    final distanceKm = _storeDistanceFromAddress(first, selectedAddress);
    final deliveryCost =
        distanceKm == null ? null : _fuelDeliveryCost(distanceKm);
    final eta = distanceKm == null
        ? 'ETA after address'
        : '${math.max(12, (distanceKm * 4 + 12).ceil())}-${math.max(22, (distanceKm * 4 + 22).ceil())} min';
    final storeReviews = _reviewsForStore(first.storeId, reviews);
    final isFavorite = favoriteStoreIds.contains(first.storeId);
    final promoLabel =
        promoCodes.isEmpty ? null : _promoBadgeLabel(promoCodes.first);
    final ratingValue = _storeRatingValue(first.storeId, reviews);
    final reviewCount = storeReviews.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _RestaurantDetailPage(
                storeItems: storeItems,
                selectedAddress: selectedAddress,
                reviews: storeReviews,
                productReviews: productReviews,
                cart: cart,
                onAdd: onAdd,
                onShowDetails: onShowDetails,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2.12,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CatalogProductImage(imageUrl: first.imageUrl),
                  if (promoLabel != null)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _DealBadge(label: promoLabel),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          '${storeItems.length} items',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          first.storeName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: isFavorite
                            ? 'Remove from favourites'
                            : 'Add to favourites',
                        onPressed: () => onToggleFavoriteStore(first.storeId),
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite
                              ? const Color(0xffe11d48)
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _RestaurantMetric(
                        icon: Icons.thumb_up_alt_outlined,
                        label: ratingValue == null
                            ? 'New'
                            : '${(ratingValue * 20).round()}%',
                      ),
                      if (reviewCount > 0)
                        Text(
                          '($reviewCount)',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      Text(
                        '- $eta',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        '-',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      _DeliveryFeePill(
                        label: deliveryCost == null
                            ? 'Add address'
                            : deliveryCost <= 0
                                ? 'Free'
                                : _formatNaira(deliveryCost),
                      ),
                    ],
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

class _DealBadge extends StatelessWidget {
  const _DealBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xffe11d48),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    );
  }
}

class _RestaurantMetric extends StatelessWidget {
  const _RestaurantMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xff047857)),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _DeliveryFeePill extends StatelessWidget {
  const _DeliveryFeePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xffe11d48),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pedal_bike, color: Colors.white, size: 13),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _RestaurantDetailPage extends StatelessWidget {
  const _RestaurantDetailPage({
    required this.storeItems,
    required this.selectedAddress,
    required this.reviews,
    required this.productReviews,
    required this.cart,
    required this.onAdd,
    required this.onShowDetails,
  });

  final List<CatalogItem> storeItems;
  final CustomerAddress? selectedAddress;
  final List<OrderReviewSummary> reviews;
  final List<ProductReviewSummary> productReviews;
  final Map<String, int> cart;
  final ValueChanged<CatalogItem> onAdd;
  final ValueChanged<CatalogItem> onShowDetails;

  @override
  Widget build(BuildContext context) {
    final first = storeItems.first;
    final distanceKm = _storeDistanceFromAddress(first, selectedAddress);
    final deliveryCost =
        distanceKm == null ? null : _fuelDeliveryCost(distanceKm);
    final rating = _averageStoreRating(first.storeId, reviews);
    final eta = distanceKm == null
        ? 'ETA after address'
        : '${math.max(12, (distanceKm * 4 + 12).ceil())}-${math.max(22, (distanceKm * 4 + 22).ceil())} min';
    final categories = <String, List<CatalogItem>>{};
    for (final item in storeItems) {
      categories.putIfAbsent(item.category, () => []).add(item);
    }
    final categoryEntries = categories.entries.toList()
      ..sort((a, b) => _humanStatus(a.key).compareTo(_humanStatus(b.key)));

    return Scaffold(
      appBar: AppBar(title: Text(first.storeName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 190,
              child: _CatalogProductImage(imageUrl: first.imageUrl),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            first.storeName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniInfoChip(icon: Icons.star, label: rating),
              _MiniInfoChip(icon: Icons.schedule, label: eta),
              _MiniInfoChip(
                icon: Icons.local_shipping_outlined,
                label: deliveryCost == null
                    ? 'Add address'
                    : _formatNaira(deliveryCost),
              ),
              _MiniInfoChip(
                icon: Icons.restaurant_menu,
                label: '${storeItems.length} menu items',
              ),
            ],
          ),
          if (distanceKm != null) ...[
            const SizedBox(height: 10),
            Text(
              '${distanceKm.toStringAsFixed(1)} km from your selected address. Delivery cost is estimated from fuel usage at 0.067 L/km and NGN 1500/L.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          _RestaurantReviewsSection(reviews: reviews),
          const SizedBox(height: 20),
          Text(
            'Menu',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          for (final category in categoryEntries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(
                _humanStatus(category.key),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            for (final item in category.value)
              _RestaurantMenuItemCard(
                item: item,
                reviews: productReviews
                    .where((review) => review.productId == item.productId)
                    .toList(),
                cartQuantity: cart[item.productId] ?? 0,
                onAdd: onAdd,
                onShowDetails: onShowDetails,
              ),
          ],
        ],
      ),
    );
  }
}

class _RestaurantReviewsSection extends StatelessWidget {
  const _RestaurantReviewsSection({required this.reviews});

  final List<OrderReviewSummary> reviews;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
        );
    if (reviews.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Customer ratings', style: titleStyle),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('No customer ratings yet.'),
            ),
          ),
        ],
      );
    }

    final average = reviews.fold<int>(0, (sum, review) => sum + review.rating) /
        reviews.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Customer ratings', style: titleStyle)),
            Text(
              '${average.toStringAsFixed(1)}/5',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${reviews.length} review${reviews.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final review in reviews.take(4))
          _RestaurantReviewCard(review: review),
      ],
    );
  }
}

class _RestaurantMenuItemCard extends StatelessWidget {
  const _RestaurantMenuItemCard({
    required this.item,
    required this.reviews,
    required this.cartQuantity,
    required this.onAdd,
    required this.onShowDetails,
  });

  final CatalogItem item;
  final List<ProductReviewSummary> reviews;
  final int cartQuantity;
  final ValueChanged<CatalogItem> onAdd;
  final ValueChanged<CatalogItem> onShowDetails;

  @override
  Widget build(BuildContext context) {
    final canAdd = item.isAvailable && cartQuantity < item.quantityAvailable;
    final ratingLabel = _averageProductRating(reviews);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onShowDetails(item),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox.square(
                  dimension: 72,
                  child: _CatalogProductImage(imageUrl: item.imageUrl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (item.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          _formatNaira(item.price),
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        Text(
                          item.isAvailable ? 'Available' : 'Unavailable',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        if (ratingLabel != null)
                          _MiniInfoChip(
                            icon: Icons.star,
                            label: ratingLabel,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Add to cart',
                onPressed: canAdd ? () => onAdd(item) : null,
                icon: Icon(cartQuantity == 0 ? Icons.add : Icons.check),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestaurantReviewCard extends StatelessWidget {
  const _RestaurantReviewCard({required this.review});

  final OrderReviewSummary review;

  @override
  Widget build(BuildContext context) {
    final customerName = review.customerName?.trim();
    final comment = review.comment?.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    customerName == null || customerName.isEmpty
                        ? 'Customer'
                        : customerName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Text(_stars(review.rating)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatDateTime(review.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(comment),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountPane extends StatelessWidget {
  const _AccountPane({
    required this.userEmail,
    required this.selectedAddress,
    required this.onEditProfile,
    required this.onManageAddresses,
    required this.onOpenNotifications,
    required this.onSignOut,
  });

  final String userEmail;
  final CustomerAddress? selectedAddress;
  final VoidCallback onEditProfile;
  final VoidCallback onManageAddresses;
  final VoidCallback onOpenNotifications;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Account',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(userEmail),
            subtitle: const Text('Customer account'),
            trailing: TextButton(
              onPressed: onEditProfile,
              child: const Text('Edit'),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(selectedAddress?.label ?? 'Delivery address'),
            subtitle: Text(
              selectedAddress?.address ?? 'Add a saved address for checkout.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              onPressed: onManageAddresses,
              child: Text(selectedAddress == null ? 'Add' : 'Manage'),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Notifications'),
            subtitle: const Text('Order, payment, and rider updates'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenNotifications,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
