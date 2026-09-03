import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog_item.dart';
import '../models/checkout_quote.dart';
import '../models/customer_address.dart';
import '../models/delivery_event.dart';
import '../models/inventory_movement.dart';
import '../models/order_issue_summary.dart';
import '../models/order_line_item.dart';
import '../models/order_message_summary.dart';
import '../models/order_review_summary.dart';
import '../models/order_summary.dart';
import '../models/payment_summary.dart';
import '../models/payment_webhook_event_summary.dart';
import '../models/notification_delivery_summary.dart';
import '../models/platform_fee_settings.dart';
import '../models/product_review_summary.dart';
import '../models/promo_code_summary.dart';
import '../models/promo_quote.dart';
import '../models/rider_availability.dart';
import '../models/rider_location_update.dart';
import '../models/rider_pickup_estimate.dart';
import '../models/rider_settlement_summary.dart';
import '../models/store_employee_activity.dart';
import '../models/store_inventory_item.dart';
import '../models/store_member.dart';
import '../models/store_opening_hour.dart';
import '../models/store_staff_presence.dart';
import '../models/store_settlement_summary.dart';
import '../models/store_summary.dart';
import '../models/user_notification.dart';
import '../models/user_profile.dart';

class PlatformRepository {
  PlatformRepository(this._client);

  final SupabaseClient _client;

  Stream<List<StoreSummary>> watchStores({bool activeOnly = true}) {
    if (activeOnly) {
      return _client
          .from('stores')
          .stream(primaryKey: ['id'])
          .eq('is_active', true)
          .order('name')
          .map((rows) => rows.map(StoreSummary.fromMap).toList());
    }

    return _client
        .from('stores')
        .stream(primaryKey: ['id'])
        .order('name')
        .map((rows) => rows.map(StoreSummary.fromMap).toList());
  }

  Stream<StoreSummary?> watchStore(String storeId) {
    return _client
        .from('stores')
        .stream(primaryKey: ['id'])
        .eq('id', storeId)
        .limit(1)
        .map((rows) => rows.isEmpty ? null : StoreSummary.fromMap(rows.first));
  }

  Stream<List<StoreOpeningHour>> watchStoreOpeningHours(String storeId) {
    return _client
        .from('store_opening_hours')
        .stream(primaryKey: ['id'])
        .eq('store_id', storeId)
        .order('day_of_week')
        .map((rows) => rows.map(StoreOpeningHour.fromMap).toList());
  }

  Stream<List<StoreEmployeeActivity>> watchStoreEmployeeActivities({
    String? storeId,
    int limit = 50,
  }) {
    if (storeId != null) {
      return _client
          .from('store_employee_activity_summaries')
          .stream(primaryKey: ['id'])
          .eq('store_id', storeId)
          .order('created_at', ascending: false)
          .limit(limit)
          .map((rows) => rows.map(StoreEmployeeActivity.fromMap).toList());
    }

    return _client
        .from('store_employee_activity_summaries')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(StoreEmployeeActivity.fromMap).toList());
  }

  Stream<List<StoreStaffPresence>> watchStoreStaffPresence({
    String? storeId,
  }) {
    if (storeId != null) {
      return _client
          .from('store_staff_presence_summaries')
          .stream(primaryKey: ['store_id', 'user_id'])
          .eq('store_id', storeId)
          .order('last_seen_at', ascending: false)
          .map((rows) => rows.map(StoreStaffPresence.fromMap).toList());
    }

    return _client
        .from('store_staff_presence_summaries')
        .stream(primaryKey: ['store_id', 'user_id'])
        .order('last_seen_at', ascending: false)
        .map((rows) => rows.map(StoreStaffPresence.fromMap).toList());
  }

  Stream<List<UserProfile>> watchProfiles() {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .order('full_name')
        .map((rows) => rows.map(UserProfile.fromMap).toList());
  }

  Stream<UserProfile?> watchMyProfile() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream<UserProfile?>.empty();
    }

    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .limit(1)
        .map((rows) => rows.isEmpty ? null : UserProfile.fromMap(rows.first));
  }

  Future<UserProfile?> fetchMyProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

    final rows =
        await _client.from('profiles').select().eq('id', userId).limit(1);
    return rows.isEmpty ? null : UserProfile.fromMap(rows.first);
  }

  Stream<List<StoreMember>> watchStoreMembers() {
    return _client
        .from('store_members')
        .stream(primaryKey: ['store_id', 'user_id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(StoreMember.fromMap).toList());
  }

  Stream<List<StoreMember>> watchMyStoreMemberships() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream<List<StoreMember>>.empty();
    }

    return _client
        .from('store_members')
        .stream(primaryKey: ['store_id', 'user_id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(StoreMember.fromMap).toList());
  }

  Future<List<StoreMember>> fetchMyStoreMemberships() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const <StoreMember>[];
    }

    final rows = await _client
        .from('store_members')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.map(StoreMember.fromMap).toList();
  }

  Stream<List<CustomerAddress>> watchMyAddresses() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream<List<CustomerAddress>>.empty();
    }

    final controller = StreamController<List<CustomerAddress>>();
    RealtimeChannel? channel;
    Timer? debounce;
    var isClosed = false;

    Future<void> emitAddresses() async {
      try {
        final addresses = await fetchMyAddresses();
        if (!isClosed) {
          controller.add(addresses);
        }
      } on Object catch (error, stackTrace) {
        if (!isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    void scheduleRefresh() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 250), emitAddresses);
    }

    controller.onListen = () {
      emitAddresses();
      channel = _client
          .channel(
            'customer-addresses-$userId-${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'customer_addresses',
            callback: (_) => scheduleRefresh(),
          )
          .subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.channelError &&
            error != null &&
            !isClosed) {
          controller.addError(error);
        }
      });
    };

    controller.onCancel = () async {
      isClosed = true;
      debounce?.cancel();
      final activeChannel = channel;
      if (activeChannel != null) {
        await _client.removeChannel(activeChannel);
      }
    };

    return controller.stream;
  }

  Future<List<CustomerAddress>> fetchMyAddresses() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const <CustomerAddress>[];
    }

    final rows = await _client
        .from('customer_addresses')
        .select()
        .eq('customer_id', userId)
        .order('is_default', ascending: false)
        .order('updated_at', ascending: false);
    return rows.map(CustomerAddress.fromMap).toList();
  }

  Stream<List<CatalogItem>> watchCatalog({String? storeId}) {
    final controller = StreamController<List<CatalogItem>>();
    RealtimeChannel? channel;
    Timer? debounce;
    var isClosed = false;

    Future<List<CatalogItem>> loadCatalog() async {
      var query = _client.from('customer_catalog').select();
      if (storeId != null) {
        query = query.eq('store_id', storeId);
      }

      final rows = await query.order('store_name').order('name');
      return rows.map(CatalogItem.fromMap).toList();
    }

    Future<void> emitCatalog() async {
      try {
        if (!isClosed) {
          controller.add(await loadCatalog());
        }
      } on Object catch (error, stackTrace) {
        if (_isExpiredJwtError(error)) {
          try {
            await _client.auth.refreshSession();
            if (!isClosed) {
              controller.add(await loadCatalog());
            }
            return;
          } on Object catch (refreshError, refreshStackTrace) {
            await _client.auth.signOut();
            if (!isClosed) {
              controller.addError(refreshError, refreshStackTrace);
            }
            return;
          }
        }

        if (!isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    void scheduleRefresh() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 250), emitCatalog);
    }

    controller.onListen = () {
      emitCatalog();
      channel = _client
          .channel(
            'customer-catalog-${storeId ?? 'all'}-${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'stores',
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'products',
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'inventory_items',
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'inventory_reservations',
            callback: (_) => scheduleRefresh(),
          )
          .subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.channelError &&
            error != null &&
            !isClosed) {
          controller.addError(error);
        }
      });
    };

    controller.onCancel = () async {
      isClosed = true;
      debounce?.cancel();
      final activeChannel = channel;
      if (activeChannel != null) {
        await _client.removeChannel(activeChannel);
      }
    };

    return controller.stream;
  }

  Future<List<StoreInventoryItem>> fetchStoreInventory(String storeId) async {
    final rows = await _client
        .from('store_inventory')
        .select()
        .eq('store_id', storeId)
        .order('name');
    return rows.map(StoreInventoryItem.fromMap).toList();
  }

  Stream<List<StoreInventoryItem>> watchStoreInventory(String storeId) {
    final controller = StreamController<List<StoreInventoryItem>>();
    RealtimeChannel? channel;
    Timer? debounce;
    var isClosed = false;

    Future<void> emitInventory() async {
      try {
        final items = await fetchStoreInventory(storeId);
        if (!isClosed) {
          controller.add(items);
        }
      } on Object catch (error, stackTrace) {
        if (!isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    void scheduleRefresh() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 250), emitInventory);
    }

    controller.onListen = () {
      emitInventory();
      channel = _client
          .channel(
            'store-inventory-$storeId-${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'products',
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'inventory_items',
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'inventory_reservations',
            callback: (_) => scheduleRefresh(),
          )
          .subscribe();
    };

    controller.onCancel = () async {
      isClosed = true;
      debounce?.cancel();
      final activeChannel = channel;
      if (activeChannel != null) {
        await _client.removeChannel(activeChannel);
      }
    };

    return controller.stream;
  }

  Stream<List<InventoryMovement>> watchProductInventoryMovements(
    String productId,
  ) {
    return _client
        .from('inventory_movements')
        .stream(primaryKey: ['id'])
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .limit(20)
        .map((rows) => rows.map(InventoryMovement.fromMap).toList());
  }

  Stream<List<OrderSummary>> watchMyOrders() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream<List<OrderSummary>>.empty();
    }

    return _watchOrderSummaryList(
      () => _fetchOrderSummaries(customerId: userId),
      'my-orders-$userId',
    );
  }

  Stream<OrderSummary?> watchOrder(String orderId) {
    return _watchOrderSummaryList(
      () async {
        final order = await fetchOrder(orderId);
        return [if (order != null) order];
      },
      'order-$orderId',
    ).map((orders) => orders.isEmpty ? null : orders.first);
  }

  Future<OrderSummary?> fetchOrder(String orderId) async {
    final rows = await _client
        .from('order_summaries')
        .select()
        .eq('id', orderId)
        .limit(1);
    return rows.isEmpty ? null : OrderSummary.fromMap(rows.first);
  }

  Stream<List<OrderSummary>> watchAvailableRiderOrders() {
    return _watchOrderSummaryList(
      _fetchAvailableRiderOrderSummaries,
      'available-rider-orders',
    );
  }

  Future<List<OrderSummary>> _fetchAvailableRiderOrderSummaries() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const <OrderSummary>[];
    }

    final orders = await _fetchOrderSummaries(
      status: 'ready_for_pickup',
      orderBy: 'updated_at',
    );
    return orders
        .where(
          (order) =>
              order.paymentStatus == 'paid' &&
              (order.riderId == null || order.riderId == userId),
        )
        .toList();
  }

  Stream<RiderAvailability?> watchMyRiderAvailability() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream<RiderAvailability?>.empty();
    }

    return _client
        .from('rider_availability')
        .stream(primaryKey: ['rider_id'])
        .eq('rider_id', userId)
        .limit(1)
        .map(
          (rows) => rows.isEmpty ? null : RiderAvailability.fromMap(rows.first),
        );
  }

  Stream<List<RiderAvailability>> watchRiderAvailability() {
    return _client
        .from('rider_availability')
        .stream(primaryKey: ['rider_id'])
        .order('last_seen_at', ascending: false)
        .map((rows) => rows.map(RiderAvailability.fromMap).toList());
  }

  Future<RiderPickupEstimate?> fetchNearestRiderPickupEstimate(
    String storeId,
  ) async {
    final response = await _client.rpc<List<dynamic>>(
      'nearest_online_rider_pickup_estimate',
      params: {'p_store_id': storeId},
    );
    if (response.isEmpty) {
      return null;
    }
    return RiderPickupEstimate.fromMap(response.first as Map<String, dynamic>);
  }

  Stream<List<OrderSummary>> watchMyRiderOrders() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream<List<OrderSummary>>.empty();
    }

    return _watchOrderSummaryList(
      () => _fetchOrderSummaries(riderId: userId, orderBy: 'updated_at'),
      'my-rider-orders-$userId',
    );
  }

  Stream<List<OrderSummary>> watchStoreOrders(String storeId) {
    return _watchOrderSummaryList(
      () => _fetchStoreOrderSummaries(storeId),
      'store-orders-$storeId',
    );
  }

  Stream<List<OrderSummary>> watchAllOrders() {
    return _watchOrderSummaryList(
      _fetchOrderSummaries,
      'all-orders',
    );
  }

  Future<List<OrderSummary>> _fetchOrderSummaries({
    String? customerId,
    String? storeId,
    String? riderId,
    String? status,
    String orderBy = 'created_at',
  }) async {
    var query = _client.from('order_summaries').select();
    if (customerId != null) {
      query = query.eq('customer_id', customerId);
    }
    if (storeId != null) {
      query = query.eq('store_id', storeId);
    }
    if (riderId != null) {
      query = query.eq('rider_id', riderId);
    }
    if (status != null) {
      query = query.eq('status', status);
    }

    final rows = await query.order(orderBy, ascending: false);
    return rows.map(OrderSummary.fromMap).toList();
  }

  Future<List<OrderSummary>> _fetchStoreOrderSummaries(String storeId) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'store_order_summaries',
        params: {'p_store_id': storeId},
      );
      return rows
          .whereType<Map<String, dynamic>>()
          .map(OrderSummary.fromMap)
          .toList();
    } on Object catch (error) {
      if (_isMissingRpcSignature(error, 'store_order_summaries')) {
        return _fetchOrderSummaries(storeId: storeId);
      }
      rethrow;
    }
  }

  Stream<List<OrderSummary>> _watchOrderSummaryList(
    Future<List<OrderSummary>> Function() load,
    String channelName,
  ) {
    final controller = StreamController<List<OrderSummary>>();
    RealtimeChannel? channel;
    Timer? pollTimer;
    Timer? debounce;
    var isClosed = false;
    String? lastSignature;

    Future<void> emitOrders() async {
      try {
        final orders = await load();
        final signature = _orderListSignature(orders);
        if (!isClosed) {
          if (signature != lastSignature) {
            lastSignature = signature;
            controller.add(orders);
          }
        }
      } on Object catch (error, stackTrace) {
        if (!isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    void scheduleRefresh() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 250), emitOrders);
    }

    controller.onListen = () {
      emitOrders();
      pollTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => emitOrders(),
      );
      channel = _client
          .channel(
            '$channelName-${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_items',
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'payments',
            callback: (_) => scheduleRefresh(),
          )
          .subscribe((_, __) {});
    };

    controller.onCancel = () async {
      isClosed = true;
      debounce?.cancel();
      pollTimer?.cancel();
      final activeChannel = channel;
      if (activeChannel != null) {
        await _client.removeChannel(activeChannel);
      }
    };

    return controller.stream;
  }

  Stream<List<PaymentSummary>> watchPaymentSummaries() {
    return _pollList(
      () => _client
          .from('payment_summaries')
          .select()
          .order('created_at', ascending: false)
          .limit(500)
          .then((rows) => rows.map(PaymentSummary.fromMap).toList()),
      refreshInterval: const Duration(seconds: 45),
    );
  }

  Stream<List<PaymentWebhookEventSummary>> watchPaymentWebhookEvents() {
    return _pollList(
      () => _client
          .from('payment_webhook_event_summaries')
          .select()
          .order('created_at', ascending: false)
          .limit(50)
          .then(
              (rows) => rows.map(PaymentWebhookEventSummary.fromMap).toList()),
      refreshInterval: const Duration(seconds: 60),
    );
  }

  Stream<List<StoreSettlementSummary>> watchStoreSettlements({
    String? storeId,
  }) {
    if (storeId != null) {
      return _client
          .from('store_settlement_summaries')
          .stream(primaryKey: ['id'])
          .eq('store_id', storeId)
          .order('created_at', ascending: false)
          .map((rows) => rows.map(StoreSettlementSummary.fromMap).toList());
    }

    return _client
        .from('store_settlement_summaries')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(StoreSettlementSummary.fromMap).toList());
  }

  Stream<List<RiderSettlementSummary>> watchRiderSettlements({
    String? riderId,
  }) {
    if (riderId != null) {
      return _client
          .from('rider_settlement_summaries')
          .stream(primaryKey: ['id'])
          .eq('rider_id', riderId)
          .order('created_at', ascending: false)
          .map((rows) => rows.map(RiderSettlementSummary.fromMap).toList());
    }

    return _client
        .from('rider_settlement_summaries')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(RiderSettlementSummary.fromMap).toList());
  }

  Stream<PlatformFeeSettings?> watchPlatformFeeSettings() {
    return _pollValue(
      () => _client
          .from('platform_fee_settings')
          .select()
          .eq('id', true)
          .limit(1)
          .then(
            (rows) =>
                rows.isEmpty ? null : PlatformFeeSettings.fromMap(rows.first),
          ),
      refreshInterval: const Duration(seconds: 60),
    );
  }

  Stream<List<PromoCodeSummary>> watchPromoCodes({String? storeId}) {
    if (storeId != null) {
      return _client
          .from('promo_code_summaries')
          .stream(primaryKey: ['id'])
          .eq('store_id', storeId)
          .order('created_at', ascending: false)
          .map((rows) => rows.map(PromoCodeSummary.fromMap).toList());
    }

    return _client
        .from('promo_code_summaries')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(PromoCodeSummary.fromMap).toList());
  }

  Stream<List<UserNotification>> watchMyNotifications({
    int limit = 50,
    String? audience,
  }) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream<List<UserNotification>>.empty();
    }

    return _client
        .from('user_notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map(
          (rows) => rows
              .map(UserNotification.fromMap)
              .where(
                (notification) =>
                    _notificationMatchesAudience(notification, audience),
              )
              .toList(),
        );
  }

  Stream<int> watchUnreadNotificationCount({String? audience}) {
    return watchMyNotifications(audience: audience).map(
      (notifications) =>
          notifications.where((notification) => !notification.isRead).length,
    );
  }

  bool _notificationMatchesAudience(
    UserNotification notification,
    String? audience,
  ) {
    if (audience == null || audience.trim().isEmpty) {
      return true;
    }

    final expectedAudience = audience.trim().toLowerCase();
    final notificationAudience =
        notification.data['audience']?.toString().trim().toLowerCase();
    if (notificationAudience != null && notificationAudience.isNotEmpty) {
      if (notificationAudience == 'all') {
        return true;
      }
      return notificationAudience == expectedAudience &&
          _notificationTypeRelevantForAudience(
            notification.type,
            expectedAudience,
          );
    }

    final fallbackAudience = _fallbackNotificationAudience(notification.type);
    if (fallbackAudience == 'all') {
      return true;
    }
    return fallbackAudience == expectedAudience &&
        _notificationTypeRelevantForAudience(
          notification.type,
          expectedAudience,
        );
  }

  bool _notificationTypeRelevantForAudience(String type, String audience) {
    final normalized = type.trim().toLowerCase();
    final normalizedAudience = audience.trim().toLowerCase();

    if (normalized == 'general' ||
        normalized == 'order_message' ||
        normalized == 'support_issue_created' ||
        normalized == 'support_issue_updated') {
      return true;
    }

    if (normalizedAudience == 'admin') {
      return true;
    }
    if (normalizedAudience == 'customer') {
      return normalized.startsWith('payment_') ||
          normalized == 'eta_updated' ||
          normalized == 'order_status' ||
          normalized == 'rider_assigned';
    }
    if (normalizedAudience == 'store') {
      return normalized.startsWith('store_') ||
          normalized.startsWith('store_settlement_') ||
          normalized.startsWith('review_') ||
          normalized == 'order_paid' ||
          normalized == 'order_status' ||
          normalized == 'rider_assigned';
    }
    if (normalizedAudience == 'rider') {
      return normalized.startsWith('rider_') ||
          normalized.startsWith('delivery_') ||
          normalized.startsWith('rider_settlement_') ||
          normalized == 'ready_for_pickup' ||
          normalized == 'order_status';
    }

    return false;
  }

  String _fallbackNotificationAudience(String type) {
    final normalized = type.trim().toLowerCase();
    if (normalized.startsWith('payment_') ||
        normalized == 'order_status' ||
        normalized == 'rider_assigned' ||
        normalized == 'eta_updated') {
      return 'customer';
    }
    if (normalized.startsWith('store_') ||
        normalized == 'order_paid' ||
        normalized == 'store_assigned' ||
        normalized == 'store_permissions_updated') {
      return 'store';
    }
    if (normalized == 'delivery_assigned' || normalized == 'ready_for_pickup') {
      return 'rider';
    }
    if (normalized.startsWith('admin_') ||
        normalized.startsWith('settlement_')) {
      return 'admin';
    }
    return 'all';
  }

  Stream<List<NotificationDeliverySummary>> watchNotificationDeliveries({
    int limit = 50,
  }) {
    final controller = StreamController<List<NotificationDeliverySummary>>();
    Timer? timer;
    var isClosed = false;

    Future<void> emitDeliveries() async {
      try {
        final rows = await _client
            .from('notification_delivery_summaries')
            .select()
            .order('created_at', ascending: false)
            .limit(limit);
        if (!isClosed) {
          controller
              .add(rows.map(NotificationDeliverySummary.fromMap).toList());
        }
      } on Object catch (error, stackTrace) {
        if (!isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller.onListen = () {
      unawaited(emitDeliveries());
      timer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(emitDeliveries()),
      );
    };
    controller.onCancel = () {
      isClosed = true;
      timer?.cancel();
    };

    return controller.stream;
  }

  Stream<List<OrderIssueSummary>> watchOrderIssues() {
    return _client
        .from('order_issue_summaries')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(OrderIssueSummary.fromMap).toList());
  }

  Stream<List<OrderIssueSummary>> watchOrderIssuesForOrder(String orderId) {
    return _client
        .from('order_issue_summaries')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(OrderIssueSummary.fromMap).toList());
  }

  Stream<List<OrderMessageSummary>> watchOrderMessages(String orderId) {
    return _client
        .from('order_message_summaries')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('created_at')
        .map((rows) => rows.map(OrderMessageSummary.fromMap).toList());
  }

  Stream<List<OrderReviewSummary>> watchOrderReviews({String? storeId}) {
    if (storeId != null) {
      return _client
          .from('order_review_summaries')
          .stream(primaryKey: ['id'])
          .eq('store_id', storeId)
          .order('created_at', ascending: false)
          .map((rows) => rows.map(OrderReviewSummary.fromMap).toList());
    }

    return _client
        .from('order_review_summaries')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(OrderReviewSummary.fromMap).toList());
  }

  Stream<List<OrderReviewSummary>> watchOrderReviewsForOrder(String orderId) {
    return _client
        .from('order_review_summaries')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(OrderReviewSummary.fromMap).toList());
  }

  Stream<List<OrderReviewSummary>> watchPublicStoreReviews() {
    return _client
        .from('public_store_review_summaries')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(OrderReviewSummary.fromMap).toList());
  }

  Stream<List<ProductReviewSummary>> watchProductReviews(String productId) {
    return _client
        .from('product_review_summaries')
        .stream(primaryKey: ['id'])
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(ProductReviewSummary.fromMap).toList());
  }

  Stream<List<ProductReviewSummary>> watchStoreProductReviews(String storeId) {
    return _client
        .from('product_review_summaries')
        .stream(primaryKey: ['id'])
        .eq('store_id', storeId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(ProductReviewSummary.fromMap).toList());
  }

  Stream<List<ProductReviewSummary>> watchAllProductReviews() {
    return _client
        .from('product_review_summaries')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(ProductReviewSummary.fromMap).toList());
  }

  Stream<List<DeliveryEvent>> watchDeliveryEvents(String orderId) {
    return _client
        .from('delivery_events')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(DeliveryEvent.fromMap).toList());
  }

  Stream<List<RiderLocationUpdate>> watchRiderLocations(
    String orderId, {
    Duration refreshInterval = const Duration(seconds: 20),
  }) {
    return _pollList(
      () => _client
          .from('rider_location_summaries')
          .select()
          .eq('order_id', orderId)
          .order('created_at', ascending: false)
          .limit(20)
          .then((rows) => rows.map(RiderLocationUpdate.fromMap).toList()),
      refreshInterval: refreshInterval,
    );
  }

  Stream<List<RiderLocationUpdate>> watchAllRiderLocations({
    int limit = 200,
    Duration refreshInterval = const Duration(seconds: 30),
  }) {
    return _pollList(
      () => _client
          .from('rider_location_summaries')
          .select()
          .order('created_at', ascending: false)
          .limit(limit)
          .then((rows) => rows.map(RiderLocationUpdate.fromMap).toList()),
      refreshInterval: refreshInterval,
    );
  }

  Stream<List<OrderLineItem>> watchOrderItems(String orderId) {
    return _client
        .from('order_items')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('product_name')
        .map((rows) => rows.map(OrderLineItem.fromMap).toList());
  }

  Future<String> placeOrder({
    required String storeId,
    required String deliveryAddress,
    required List<Map<String, dynamic>> items,
    String? promoCode,
    String fulfillmentType = 'delivery',
    double? customerLatitude,
    double? customerLongitude,
  }) async {
    final orderId = await _client.rpc<String>(
      'place_order',
      params: {
        'p_store_id': storeId,
        'p_delivery_address': deliveryAddress,
        'p_items': items,
        'p_promo_code': promoCode,
        'p_fulfillment_type': fulfillmentType,
        'p_customer_latitude': customerLatitude,
        'p_customer_longitude': customerLongitude,
      },
    );
    return orderId;
  }

  Future<CheckoutQuote> quoteOrderTotals({
    required String storeId,
    required List<Map<String, dynamic>> items,
    String? promoCode,
    String fulfillmentType = 'delivery',
    double? customerLatitude,
    double? customerLongitude,
  }) async {
    final response = await _client.rpc<List<dynamic>>(
      'quote_order_totals',
      params: {
        'p_store_id': storeId,
        'p_items': items,
        'p_promo_code': promoCode,
        'p_fulfillment_type': fulfillmentType,
        'p_customer_latitude': customerLatitude,
        'p_customer_longitude': customerLongitude,
      },
    );
    return CheckoutQuote.fromMap(response.first as Map<String, dynamic>);
  }

  Future<void> cancelPendingOrder(String orderId) {
    return _client.rpc<void>(
      'customer_cancel_pending_order',
      params: {'p_order_id': orderId},
    );
  }

  Future<String> createOrderIssue({
    required String orderId,
    required String category,
    required String message,
  }) async {
    final issueId = await _client.rpc<String>(
      'customer_create_order_issue',
      params: {
        'p_order_id': orderId,
        'p_category': category,
        'p_message': message,
      },
    );
    return issueId;
  }

  Future<String> sendOrderMessage({
    required String orderId,
    required String message,
  }) async {
    final messageId = await _client.rpc<String>(
      'send_order_message',
      params: {
        'p_order_id': orderId,
        'p_message': message,
      },
    );
    return messageId;
  }

  Future<String> submitOrderReview({
    required String orderId,
    required int rating,
    String? comment,
  }) async {
    final reviewId = await _client.rpc<String>(
      'customer_upsert_order_review',
      params: {
        'p_order_id': orderId,
        'p_rating': rating,
        'p_comment': comment,
      },
    );
    return reviewId;
  }

  Future<String> submitProductReview({
    required String orderId,
    required String productId,
    required int rating,
    String? comment,
  }) async {
    final reviewId = await _client.rpc<String>(
      'customer_upsert_product_review',
      params: {
        'p_order_id': orderId,
        'p_product_id': productId,
        'p_rating': rating,
        'p_comment': comment,
      },
    );
    return reviewId;
  }

  Future<String> submitRiderReview({
    required String orderId,
    required int rating,
    String? comment,
  }) async {
    final reviewId = await _client.rpc<String>(
      'customer_upsert_rider_review',
      params: {
        'p_order_id': orderId,
        'p_rating': rating,
        'p_comment': comment,
      },
    );
    return reviewId;
  }

  Future<void> markOrderReceived(String orderId) {
    return _client.rpc<void>(
      'customer_mark_order_received',
      params: {'p_order_id': orderId},
    );
  }

  Future<PromoQuote> validatePromoCode({
    required String storeId,
    required String code,
    required double subtotal,
  }) async {
    final response = await _client.rpc<Map<String, dynamic>>(
      'validate_promo_code',
      params: {
        'p_store_id': storeId,
        'p_code': code,
        'p_subtotal': subtotal,
      },
    );
    return PromoQuote.fromMap(response);
  }

  Future<String> createPromoCode({
    required String code,
    required String discountType,
    required double discountValue,
    String? storeId,
    String description = '',
    double minOrderAmount = 0,
    int? maxRedemptions,
    bool isActive = true,
  }) async {
    final promoId = await _client.rpc<String>(
      'admin_create_promo_code',
      params: {
        'p_code': code,
        'p_discount_type': discountType,
        'p_discount_value': discountValue,
        'p_store_id': storeId,
        'p_description': description,
        'p_min_order_amount': minOrderAmount,
        'p_max_redemptions': maxRedemptions,
        'p_is_active': isActive,
      },
    );
    return promoId;
  }

  Future<String> createStorePromoCode({
    required String storeId,
    required String code,
    required String discountType,
    required double discountValue,
    String description = '',
    double minOrderAmount = 0,
    int? maxRedemptions,
    bool isActive = true,
  }) async {
    final params = {
      'p_store_id': storeId,
      'p_code': code,
      'p_discount_type': discountType,
      'p_discount_value': discountValue,
      'p_description': description,
      'p_min_order_amount': minOrderAmount,
      'p_max_redemptions': maxRedemptions,
      'p_is_active': isActive,
    };
    final promoId = await _rpcWithMigrationHint<String>(
      'store_create_promo_code',
      params: params,
      hint:
          'Store promo management is not available yet. Apply the latest Supabase migrations and reload the PostgREST schema cache.',
    );
    return promoId;
  }

  Future<void> updateStorePromoCode({
    required String promoId,
    required String code,
    required String discountType,
    required double discountValue,
    String description = '',
    double minOrderAmount = 0,
    int? maxRedemptions,
    bool isActive = true,
  }) {
    return _rpcWithMigrationHint<void>(
      'store_update_promo_code',
      params: {
        'p_promo_id': promoId,
        'p_code': code,
        'p_discount_type': discountType,
        'p_discount_value': discountValue,
        'p_description': description,
        'p_min_order_amount': minOrderAmount,
        'p_max_redemptions': maxRedemptions,
        'p_is_active': isActive,
      },
      hint:
          'Store promo management is not available yet. Apply the latest Supabase migrations and reload the PostgREST schema cache.',
    );
  }

  Future<void> deleteStorePromoCode(String promoId) {
    return _rpcWithMigrationHint<void>(
      'store_delete_promo_code',
      params: {'p_promo_id': promoId},
      hint:
          'Store promo management is not available yet. Apply the latest Supabase migrations and reload the PostgREST schema cache.',
    );
  }

  Future<void> markStoreSettlementPaid(String settlementId) {
    return _client.rpc<void>(
      'admin_mark_store_settlement_paid',
      params: {'p_settlement_id': settlementId},
    );
  }

  Future<void> markRiderSettlementPaid(String settlementId) {
    return _client.rpc<void>(
      'admin_mark_rider_settlement_paid',
      params: {'p_settlement_id': settlementId},
    );
  }

  Future<void> updatePlatformFeeSettings({
    required double deliveryFee,
    required double serviceFeePercent,
    required double serviceFeeFixed,
    required double riderDeliveryPayout,
    required double deliveryBaseKm,
    required double deliveryFeePerKm,
    required double minimumDeliveryFee,
    required bool isActive,
  }) {
    return _client.from('platform_fee_settings').update({
      'delivery_fee': deliveryFee,
      'service_fee_percent': serviceFeePercent,
      'service_fee_fixed': serviceFeeFixed,
      'rider_delivery_payout': riderDeliveryPayout,
      'delivery_base_km': deliveryBaseKm,
      'delivery_fee_per_km': deliveryFeePerKm,
      'minimum_delivery_fee': minimumDeliveryFee,
      'is_active': isActive,
    }).eq('id', true);
  }

  Future<void> markNotificationRead(String notificationId) {
    return _client.rpc<void>(
      'mark_notification_read',
      params: {'p_notification_id': notificationId},
    );
  }

  Future<void> markAllNotificationsRead() {
    return _client.rpc<void>('mark_all_notifications_read');
  }

  Future<void> deleteNotification(String notificationId) {
    return _client.rpc<void>(
      'delete_notification',
      params: {'p_notification_id': notificationId},
    );
  }

  Future<String> registerNotificationDevice({
    required String platform,
    required String provider,
    required String deviceToken,
    String? deviceName,
  }) async {
    final deviceId = await _client.rpc<String>(
      'register_notification_device',
      params: {
        'p_platform': platform,
        'p_provider': provider,
        'p_device_token': deviceToken,
        'p_device_name': deviceName,
      },
    );
    return deviceId;
  }

  Future<void> unregisterNotificationDevice(String deviceId) {
    return _client.rpc<void>(
      'unregister_notification_device',
      params: {'p_device_id': deviceId},
    );
  }

  Future<Map<String, dynamic>> dispatchPushNotifications({
    int limit = 25,
    bool retryFailed = false,
    int cleanupRetentionDays = 0,
  }) async {
    final response = await _client.functions.invoke(
      'send-push-notifications',
      body: {
        'limit': limit,
        'retryFailed': retryFailed,
        'cleanupRetentionDays': cleanupRetentionDays,
      },
    );

    final data = response.data;
    if (data is! Map) {
      throw StateError('Unexpected push dispatch response: $data');
    }

    final result = Map<String, dynamic>.from(data);
    final error = result['error'];
    if (error is String && error.isNotEmpty) {
      throw StateError(error);
    }

    return result;
  }

  Future<void> setRiderAvailability(bool isOnline) {
    return _client.rpc<void>(
      'rider_set_availability',
      params: {'p_is_online': isOnline},
    );
  }

  Future<String> saveCustomerAddress({
    required String label,
    required String address,
    bool isDefault = false,
    double? latitude,
    double? longitude,
  }) async {
    final params = {
      'p_label': label,
      'p_address': address,
      'p_is_default': isDefault,
      'p_latitude': latitude,
      'p_longitude': longitude,
    };
    String addressId;
    try {
      addressId = await _client.rpc<String>(
        'customer_save_address',
        params: params,
      );
    } on Object catch (error) {
      if (!_isMissingRpcSignature(error, 'customer_save_address')) {
        rethrow;
      }

      addressId = await _client.rpc<String>(
        'customer_save_address',
        params: {
          'p_label': label,
          'p_address': address,
          'p_is_default': isDefault,
        },
      );
    }
    return addressId;
  }

  Future<void> updateCustomerAddress({
    required String addressId,
    required String label,
    required String address,
    bool? isDefault,
    double? latitude,
    double? longitude,
  }) async {
    if (isDefault == true) {
      await setDefaultCustomerAddress(addressId);
    }

    final values = {
      'label': label,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      if (isDefault == true) 'is_default': true,
    };
    try {
      await _client.from('customer_addresses').update(values).eq(
            'id',
            addressId,
          );
    } on Object catch (error) {
      if (!_isMissingAddressCoordinateColumn(error)) {
        rethrow;
      }

      await _client.from('customer_addresses').update({
        'label': label,
        'address': address,
        if (isDefault == true) 'is_default': true,
      }).eq('id', addressId);
    }
  }

  Future<void> setDefaultCustomerAddress(String addressId) {
    return _client.rpc<void>(
      'customer_set_default_address',
      params: {'p_address_id': addressId},
    );
  }

  Future<void> deleteCustomerAddress(String addressId) {
    return _client.rpc<void>(
      'customer_delete_address',
      params: {'p_address_id': addressId},
    );
  }

  Future<String> uploadProductImage({
    required String storeId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final safeName = fileName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final objectPath =
        '$storeId/$timestamp-${safeName.isEmpty ? 'image' : safeName}';

    await _client.storage.from('product-images').uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    return _client.storage.from('product-images').getPublicUrl(objectPath);
  }

  Future<String> createStore({
    required String name,
    required String category,
    required String address,
    String? ownerId,
  }) async {
    final storeId = await _client.rpc<String>(
      'admin_create_store',
      params: {
        'p_name': name,
        'p_category': category,
        'p_address': address,
        'p_owner_id': ownerId,
      },
    );
    return storeId;
  }

  Future<void> setStoreOpen({
    required String storeId,
    required bool isOpen,
  }) {
    return _client.from('stores').update({'is_open': isOpen}).eq('id', storeId);
  }

  Future<void> updateStoreLocation({
    required String storeId,
    required String address,
    required double latitude,
    required double longitude,
  }) {
    return _client.from('stores').update({
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
    }).eq('id', storeId);
  }

  Future<void> setStoreAvailabilityStatus({
    required String storeId,
    required String mode,
  }) {
    return _client.rpc<void>(
      'store_set_availability_status',
      params: {
        'p_store_id': storeId,
        'p_mode': mode,
      },
    );
  }

  Future<void> registerStoreStaffPresence({
    required String storeId,
    required bool isActive,
  }) {
    return _client.rpc<void>(
      'register_store_staff_presence',
      params: {
        'p_store_id': storeId,
        'p_is_active': isActive,
      },
    );
  }

  Future<void> upsertStoreOpeningHour({
    required String storeId,
    required int dayOfWeek,
    required String opensAt,
    required String closesAt,
    required bool isClosed,
  }) {
    return _client.rpc<void>(
      'store_upsert_opening_hour',
      params: {
        'p_store_id': storeId,
        'p_day_of_week': dayOfWeek,
        'p_opens_at': opensAt,
        'p_closes_at': closesAt,
        'p_is_closed': isClosed,
      },
    );
  }

  Future<void> updateStoreStatus({
    required String storeId,
    bool? isOpen,
    bool? isActive,
  }) {
    return _client.rpc<void>(
      'admin_update_store_status',
      params: {
        'p_store_id': storeId,
        'p_is_open': isOpen,
        'p_is_active': isActive,
      },
    );
  }

  Future<void> setProfileRole({
    required String userId,
    required String role,
  }) {
    return _client.rpc<void>(
      'admin_set_profile_role',
      params: {
        'p_user_id': userId,
        'p_role': role,
      },
    );
  }

  Future<String> adminUpsertUser({
    required String email,
    required String password,
    required String role,
    required String fullName,
    String? phone,
    String? storeId,
    bool canManageInventory = true,
    bool canManageOrders = true,
  }) async {
    final response = await _client.functions.invoke(
      'admin-upsert-user',
      body: {
        'email': email,
        'password': password,
        'role': role,
        'fullName': fullName,
        'phone': phone,
        'storeId': storeId,
        'canManageInventory': canManageInventory,
        'canManageOrders': canManageOrders,
      },
    );

    final data = response.data;
    if (data is! Map) {
      throw StateError('Unexpected admin user response: $data');
    }

    final map = Map<String, dynamic>.from(data);
    final error = map['error'];
    if (error is String && error.isNotEmpty) {
      throw StateError(error);
    }

    final userId = map['userId'];
    if (userId is! String || userId.isEmpty) {
      throw StateError('Admin user response did not include a userId.');
    }

    return userId;
  }

  Future<void> adminDeleteUser({required String userId}) async {
    final response = await _client.functions.invoke(
      'admin-delete-user',
      body: {'userId': userId},
    );

    final data = response.data;
    if (data is Map) {
      final error = data['error'];
      if (error is String && error.isNotEmpty) {
        throw StateError(error);
      }
      return;
    }

    if (data != null) {
      throw StateError('Unexpected delete user response: $data');
    }
  }

  Future<void> updateMyProfile({
    required String fullName,
    String? phone,
  }) {
    return _client.rpc<void>(
      'update_my_profile',
      params: {
        'p_full_name': fullName,
        'p_phone': phone,
      },
    );
  }

  Future<void> updateProfileContact({
    required String userId,
    required String fullName,
    String? phone,
  }) {
    return _client.rpc<void>(
      'admin_update_profile_contact',
      params: {
        'p_user_id': userId,
        'p_full_name': fullName,
        'p_phone': phone,
      },
    );
  }

  Future<void> addStoreMember({
    required String storeId,
    required String userId,
    bool canManageInventory = true,
    bool canManageOrders = true,
  }) {
    return _client.rpc<void>(
      'admin_add_store_member',
      params: {
        'p_store_id': storeId,
        'p_user_id': userId,
        'p_can_manage_inventory': canManageInventory,
        'p_can_manage_orders': canManageOrders,
      },
    );
  }

  Future<void> removeStoreMember({
    required String storeId,
    required String userId,
  }) {
    return _client.rpc<void>(
      'admin_remove_store_member',
      params: {
        'p_store_id': storeId,
        'p_user_id': userId,
      },
    );
  }

  Future<String> createProduct({
    required String storeId,
    required String name,
    required String description,
    required double price,
    required int initialStock,
    String category = 'general',
    int reorderLevel = 5,
    String? sku,
    String? imageUrl,
    List<String> imageUrls = const [],
    bool isAvailable = true,
  }) async {
    final normalizedImageUrls = _normalizedImageUrls(imageUrl, imageUrls);
    final productId = await _client.rpc<String>(
      'admin_create_product',
      params: {
        'p_store_id': storeId,
        'p_name': name,
        'p_description': description,
        'p_price': price,
        'p_initial_stock': initialStock,
        'p_category': category,
        'p_reorder_level': reorderLevel,
        'p_sku': sku,
        'p_image_url':
            normalizedImageUrls.isEmpty ? null : normalizedImageUrls.first,
        'p_image_urls': normalizedImageUrls,
        'p_is_available': isAvailable,
      },
    );
    return productId;
  }

  Future<void> setProductAvailability({
    required String productId,
    required bool isAvailable,
  }) {
    return _client
        .from('products')
        .update({'is_available': isAvailable}).eq('id', productId);
  }

  Future<void> updateProduct({
    required String productId,
    required String name,
    required String description,
    required double price,
    required int reorderLevel,
    String category = 'general',
    String? sku,
    String? imageUrl,
    List<String> imageUrls = const [],
    bool isAvailable = true,
  }) {
    final normalizedImageUrls = _normalizedImageUrls(imageUrl, imageUrls);
    return _client.rpc<void>(
      'store_update_product',
      params: {
        'p_product_id': productId,
        'p_name': name,
        'p_description': description,
        'p_price': price,
        'p_category': category,
        'p_reorder_level': reorderLevel,
        'p_sku': sku,
        'p_image_url':
            normalizedImageUrls.isEmpty ? null : normalizedImageUrls.first,
        'p_image_urls': normalizedImageUrls,
        'p_is_available': isAvailable,
      },
    );
  }

  Future<void> adjustInventory({
    required String productId,
    required int delta,
    required String reason,
    String? note,
  }) {
    return _client.rpc<void>(
      'adjust_inventory',
      params: {
        'p_product_id': productId,
        'p_delta': delta,
        'p_reason': reason,
        'p_note': note,
      },
    );
  }

  Future<void> setProductUnavailability({
    required String productId,
    required String mode,
  }) {
    return _client.rpc<void>(
      'store_set_product_unavailability',
      params: {
        'p_product_id': productId,
        'p_mode': mode,
      },
    );
  }

  Future<void> acceptOrder({
    required String orderId,
    int? etaMinutes,
    String? note,
  }) {
    return _client.rpc<void>(
      'accept_rider_order',
      params: {
        'p_order_id': orderId,
        'p_eta_minutes': etaMinutes,
        'p_note': note,
      },
    );
  }

  Future<void> declineOrder({
    required String orderId,
    String? note,
  }) {
    return _client.rpc<void>(
      'decline_rider_order',
      params: {
        'p_order_id': orderId,
        'p_note': note,
      },
    );
  }

  Future<void> updateEta({
    required String orderId,
    required int etaMinutes,
    String? note,
  }) {
    return _client.rpc<void>(
      'update_rider_eta',
      params: {
        'p_order_id': orderId,
        'p_eta_minutes': etaMinutes,
        'p_note': note,
      },
    );
  }

  Future<String> updateRiderLocation({
    required String orderId,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    double? heading,
    double? speedMps,
    String? note,
  }) async {
    final locationId = await _client.rpc<String>(
      'rider_update_order_location',
      params: {
        'p_order_id': orderId,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_accuracy_meters': accuracyMeters,
        'p_heading': heading,
        'p_speed_mps': speedMps,
        'p_note': note,
      },
    );
    return locationId;
  }

  Future<void> assignOrderRider({
    required String orderId,
    required String riderId,
    int? etaMinutes,
    String? note,
  }) {
    return _client.rpc<void>(
      'admin_assign_order_rider',
      params: {
        'p_order_id': orderId,
        'p_rider_id': riderId,
        'p_eta_minutes': etaMinutes,
        'p_note': note,
      },
    );
  }

  Future<void> cancelOrderAsAdmin({
    required String orderId,
    String? note,
    bool restock = true,
  }) {
    return _client.rpc<void>(
      'admin_cancel_order',
      params: {
        'p_order_id': orderId,
        'p_note': note,
        'p_restock': restock,
      },
    );
  }

  Future<void> markOrderRefundedAsAdmin({
    required String orderId,
    String? note,
    bool restock = true,
  }) {
    return _client.rpc<void>(
      'admin_mark_order_refunded',
      params: {
        'p_order_id': orderId,
        'p_note': note,
        'p_restock': restock,
      },
    );
  }

  Future<void> updateOrderIssue({
    required String issueId,
    required String status,
    String? adminNote,
  }) {
    return _client.rpc<void>(
      'admin_update_order_issue',
      params: {
        'p_issue_id': issueId,
        'p_status': status,
        'p_admin_note': adminNote,
      },
    );
  }

  Future<void> updateRiderOrderStatus({
    required String orderId,
    required String status,
    String? note,
  }) {
    return _client.rpc<void>(
      'rider_update_order_status',
      params: {
        'p_order_id': orderId,
        'p_status': status,
        'p_note': note,
      },
    );
  }

  Future<void> updateStoreOrderStatus({
    required String orderId,
    required String status,
    String? note,
  }) {
    return _client.rpc<void>(
      'store_update_order_status',
      params: {
        'p_order_id': orderId,
        'p_status': status,
        'p_note': note,
      },
    );
  }

  Future<String?> markStoreOrderReadyAndDispatch({
    required String orderId,
    int? etaMinutes,
  }) async {
    final response = await _client.rpc<dynamic>(
      'store_mark_order_ready_and_dispatch',
      params: {
        'p_order_id': orderId,
        'p_eta_minutes': etaMinutes,
      },
    );
    return response is String && response.isNotEmpty ? response : null;
  }

  Future<void> updateStorePreparationTime({
    required String orderId,
    required int preparationMinutes,
  }) {
    return _client.rpc<void>(
      'store_update_preparation_time',
      params: {
        'p_order_id': orderId,
        'p_preparation_minutes': preparationMinutes,
      },
    );
  }

  Future<void> modifyStoreOrderItem({
    required String orderId,
    required String orderItemId,
    required String action,
    String? replacementProductId,
  }) {
    return _client.rpc<void>(
      'store_modify_order_item',
      params: {
        'p_order_id': orderId,
        'p_order_item_id': orderItemId,
        'p_action': action,
        'p_replacement_product_id': replacementProductId,
      },
    );
  }

  Stream<List<T>> _pollList<T>(
    Future<List<T>> Function() fetch, {
    required Duration refreshInterval,
  }) async* {
    var latest = <T>[];
    while (true) {
      try {
        latest = await fetch();
      } on Object {
        // Realtime cannot subscribe to some summary views. Keep the dashboard
        // usable and preserve the last known route telemetry when polling fails.
      }
      yield latest;
      await Future<void>.delayed(refreshInterval);
    }
  }

  Stream<T?> _pollValue<T>(
    Future<T?> Function() fetch, {
    required Duration refreshInterval,
  }) async* {
    T? latest;
    while (true) {
      try {
        latest = await fetch();
      } on Object {
        // Some admin summary views are not realtime-friendly. Keep the last
        // good dashboard value visible until the next successful poll.
      }
      yield latest;
      await Future<void>.delayed(refreshInterval);
    }
  }

  String _orderListSignature(List<OrderSummary> orders) {
    return orders
        .map(
          (order) => [
            order.id,
            order.status,
            order.paymentStatus,
            order.riderId ?? '',
            order.etaMinutes ?? '',
            order.preparationMinutes ?? '',
            order.totalAmount.toStringAsFixed(2),
            order.updatedAt.toIso8601String(),
          ].join(':'),
        )
        .join('|');
  }

  Future<T> _rpcWithMigrationHint<T>(
    String functionName, {
    required Map<String, dynamic> params,
    required String hint,
  }) async {
    try {
      return await _client.rpc<T>(functionName, params: params);
    } on Object catch (error) {
      if (_isMissingRpcSignature(error, functionName)) {
        throw StateError(hint);
      }
      rethrow;
    }
  }

  bool _isMissingRpcSignature(Object error, String functionName) {
    if (error is! PostgrestException) {
      return false;
    }
    final message = error.message.toLowerCase();
    return error.code == 'PGRST202' ||
        (message.contains('could not find') &&
            message.contains(functionName.toLowerCase()));
  }

  bool _isMissingAddressCoordinateColumn(Object error) {
    if (error is! PostgrestException) {
      return false;
    }
    final message = error.message.toLowerCase();
    return message.contains('schema cache') &&
        (message.contains('latitude') || message.contains('longitude'));
  }

  bool _isExpiredJwtError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('invalidjwttoken') &&
        message.contains('token has expired');
  }
}

List<String> _normalizedImageUrls(String? imageUrl, List<String> imageUrls) {
  final urls = <String>[
    ...imageUrls,
    if (imageUrl != null) imageUrl,
  ]
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toSet()
      .toList(growable: false);
  return urls;
}
