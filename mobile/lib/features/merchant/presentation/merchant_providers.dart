import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/result.dart';
import '../../../core/location/governorate.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/paged_state.dart';
import '../../../core/utils/json_reader.dart';
import '../../catalog/data/catalog_mappers.dart';
import '../../catalog/domain/entities.dart' show Brand, Product;
import '../../orders/data/orders_repository_impl.dart' show OrderMappers;
import '../../returns/data/returns_repository_impl.dart' show ReturnMappers;
import '../../auth/presentation/auth_providers.dart';
import '../domain/entities.dart';
import '../../../core/network/live_updates.dart';

class MerchantMappers {
  static MerchantCoupon coupon(Map<String, dynamic> json) => MerchantCoupon(
    id: Json.str(json, const ['id', 'couponId']),
    code: Json.str(json, const ['code']),
    isPercentage:
        Json.str(json, const ['discountType', 'type']).toUpperCase() ==
        'PERCENTAGE',
    value: Json.number(json, const ['value', 'discountValue']),
    minOrderAmount: Json.numberOrNull(json, const [
      'minOrderAmount',
      'minimumOrder',
    ]),
    startsAt:
        Json.date(json, const ['startsAt', 'startDate']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    endsAt: Json.date(json, const ['endsAt', 'endDate']),
    usageLimit: Json.integerOrNull(json, const ['usageLimit', 'maxUses']),
    usedCount: Json.integer(json, const ['usedCount', 'timesUsed']),
    isActive: Json.boolean(json, const ['isActive', 'active'], fallback: true),
    currencyCode: Json.str(json, const [
      'currencyCode',
      'currency',
    ], fallback: AppConfig.fallbackCurrencyCode),
  );

  const MerchantMappers._();

  static String _currency(Map<String, dynamic> json) => Json.str(json, const [
    'currencyCode',
    'currency',
  ], fallback: AppConfig.fallbackCurrencyCode);

  static SalesPoint salesPoint(Map<String, dynamic> json) => SalesPoint(
    label: Json.str(json, const ['label', 'date', 'period', 'x']),
    value: Json.number(json, const ['value', 'total', 'amount', 'y']),
    from: Json.date(json, const ['from']),
    unit: Json.strOrNull(json, const ['unit']),
  );

  static MerchantProductRow productRow(
    Map<String, dynamic> json,
  ) => MerchantProductRow(
    id: Json.str(json, const ['id', 'productId']),
    name: Json.str(json, const ['name', 'title']),
    price: Json.number(json, const ['price']),
    currencyCode: _currency(json),
    status: Json.str(json, const ['status'], fallback: 'DRAFT'),
    imageUrl: Json.strOrNull(json, const ['imageUrl', 'thumbnail', 'image']),
    sku: Json.strOrNull(json, const ['sku']),
    stock: Json.integer(json, const ['stock', 'availableQuantity']),
    isActive: Json.boolean(json, const ['isActive', 'active'], fallback: true),
    rejectionReason: Json.strOrNull(json, const [
      'rejectionReason',
      'reviewNote',
    ]),
    takenDown: Json.boolean(json, const ['takenDown']),
    takenDownReason: Json.strOrNull(json, const ['takenDownReason']),
    lowStockThreshold: Json.integerOrNull(json, const [
      'lowStockThreshold',
      'threshold',
    ]),
    originalPrice: Json.numberOrNull(json, const ['originalPrice']),
    saleEndsAt: Json.date(json, const ['saleEndsAt']),
    hasVariants: Json.boolean(json, const ['hasVariants']),
  );

  static InventoryRow inventoryRow(Map<String, dynamic> json) => InventoryRow(
    id: Json.str(json, const ['id', 'inventoryId', 'variantId']),
    productId: Json.str(json, const ['productId']),
    name: Json.str(json, const ['name', 'productName', 'title']),
    available: Json.integer(json, const [
      'available',
      'availableQuantity',
      'stock',
    ]),
    variantLabel: Json.strOrNull(json, const ['variantLabel', 'variantName']),
    sku: Json.strOrNull(json, const ['sku']),
    imageUrl: Json.strOrNull(json, const ['imageUrl', 'thumbnail']),
    reserved: Json.integer(json, const ['reserved', 'reservedQuantity']),
    sold: Json.integer(json, const ['sold', 'soldQuantity']),
    lowStockThreshold: Json.integerOrNull(json, const [
      'lowStockThreshold',
      'threshold',
    ]),
  );

  static MerchantDashboard dashboard(
    Map<String, dynamic> json,
  ) => MerchantDashboard(
    currencyCode: _currency(json),
    todaySales: Json.number(json, const ['todaySales', 'salesToday']),
    totalSales: Json.number(json, const ['totalSales']),
    revenue: Json.number(json, const ['revenue']),
    orderCount: Json.integer(json, const ['orderCount', 'totalOrders']),
    productCount: Json.integer(json, const ['productCount', 'totalProducts']),
    customerCount: Json.integer(json, const ['customerCount', 'customers']),
    pendingOrders: Json.integer(json, const ['pendingOrders']),
    lowStockCount: Json.integer(json, const ['lowStockCount', 'lowStock']),
    outOfStockCount: Json.integer(json, const [
      'outOfStockCount',
      'outOfStock',
    ]),
    rejectedCount: Json.integer(json, const ['rejectedCount']),
    returnCount: Json.integer(json, const ['returnCount', 'returns']),
    refundTotal: Json.number(json, const ['refundTotal', 'refunds']),
    salesSeries: Json.mapList(
      Json.objects(json, const ['salesSeries', 'salesChart', 'chart']),
      salesPoint,
    ),
    topProducts: Json.mapList(
      Json.objects(json, const ['topProducts']),
      productRow,
    ),
    // Read as nullable, so "the backend did not answer" survives the
    // mapper instead of arriving on screen as a confident zero.
    previousRevenue: Json.numberOrNull(json, const [
      'previousRevenue',
      'lastPeriodRevenue',
    ]),
    comparisonDays: Json.integerOrNull(json, const ['comparisonDays']),
    oldestPendingHours: Json.integerOrNull(json, const ['oldestPendingHours']),
    orderCountDelta: Json.integerOrNull(json, const ['orderCountDelta']),
    rating: Json.numberOrNull(json, const ['rating', 'storeRating']),
    ratingCount: Json.integerOrNull(json, const ['ratingCount', 'reviewCount']),
    isOpen: Json.boolean(json, const ['isOpen'], fallback: true),
  );

  static MerchantOrderRow orderRow(Map<String, dynamic> json) =>
      MerchantOrderRow(
        id: Json.str(json, const ['id', 'orderId']),
        orderNumber: Json.str(json, const ['orderNumber', 'number']),
        placedAt:
            Json.date(json, const ['placedAt', 'createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        status: Json.str(json, const ['status'], fallback: 'PENDING'),
        total: Json.number(json, const ['total', 'merchantTotal']),
        currencyCode: _currency(json),
        itemCount: Json.integer(json, const ['itemCount', 'itemsCount']),
        customerName: Json.strOrNull(json, const ['customerName', 'customer']),
        previewImageUrl: Json.strOrNull(json, const [
          'previewImageUrl',
          'imageUrl',
        ]),
        customerArea: Json.strOrNull(json, const ['customerArea', 'area']),
        customerGovernorate: Governorate.fromApi(json['customerGovernorate']),
        customerPhone: Json.strOrNull(json, const ['customerPhone']),
        paymentMethodLabel: Json.strOrNull(json, const [
          'paymentMethodLabel',
          'paymentMethod',
        ]),
        items: Json.mapList(
          Json.objects(json, const ['items', 'lines']),
          orderItem,
        ),
        autoDeliverAt: Json.date(json, const ['autoDeliverAt']),
      );

  static MerchantReturnRow returnRow(Map<String, dynamic> json) =>
      MerchantReturnRow(
        request: ReturnMappers.summary(json),
        storeOrderId: Json.str(json, const ['storeOrderId']),
        customerName: Json.strOrNull(json, const ['customerName']),
      );

  static MerchantOrderItem orderItem(Map<String, dynamic> json) =>
      MerchantOrderItem(
        id: Json.str(json, const ['id', 'itemId']),
        name: Json.str(json, const ['name', 'title', 'productName']),
        quantity: Json.integer(json, const ['quantity', 'qty']),
        price: Json.number(json, const ['price', 'unitPrice']),
        productId: Json.strOrNull(json, const ['productId']),
        sku: Json.strOrNull(json, const ['sku']),
        imageUrl: Json.strOrNull(json, const ['imageUrl', 'thumbnail']),
      );

  static MerchantOrderDetail orderDetail(Map<String, dynamic> json) =>
      MerchantOrderDetail(
        row: orderRow(json),
        items: Json.mapList(
          Json.objects(json, const ['items', 'lines']),
          orderItem,
        ),
        subtotal: Json.number(json, const ['subtotal']),
        shipping: Json.number(json, const ['shipping', 'shippingTotal']),
        discount: Json.number(json, const ['discount']),
        shippingAddress: switch (json['shippingAddress']) {
          final Map<String, dynamic> address => OrderMappers.address(address),
          _ => null,
        },
        customerPhone: Json.strOrNull(json, const [
          'customerPhone',
          'phone',
          'customerContact',
        ]),
        courier: Courier.fromJson(json),
        returns: Json.mapList(
          Json.objects(json, const ['returns']),
          ReturnMappers.detail,
        ),
      );

  static MerchantAnalytics analytics(Map<String, dynamic> json) =>
      MerchantAnalytics(
        currencyCode: _currency(json),
        revenue: Json.number(json, const ['revenue']),
        orderCount: Json.integer(json, const ['orderCount', 'orders']),
        productsSold: Json.integer(json, const ['productsSold', 'unitsSold']),
        averageOrderValue: Json.number(json, const [
          'averageOrderValue',
          'aov',
        ]),
        refundTotal: Json.number(json, const ['refundTotal', 'refunds']),
        cancellationCount: Json.integer(json, const [
          'cancellationCount',
          'cancellations',
        ]),
        series: Json.mapList(
          Json.objects(json, const ['series', 'salesSeries', 'chart']),
          salesPoint,
        ),
        topProducts: Json.mapList(
          Json.objects(json, const ['topProducts']),
          productRow,
        ),
        previousRevenue: Json.numberOrNull(json, const [
          'previousRevenue',
          'revenuePrevious',
        ]),
      );

  static SabaBill bill(Map<String, dynamic> json) => SabaBill(
    month:
        Json.date(json, const ['month']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    orderCount: Json.integer(json, const ['orderCount']),
    sales: Json.number(json, const ['sales']),
    returned: Json.number(json, const ['returned']),
    owed: Json.number(json, const ['owed']),
    isDue: Json.str(json, const ['status']).toUpperCase() == 'DUE',
    paidAt: Json.date(json, const ['paidAt']),
  );

  static StoreDeletion deletion(Map<String, dynamic> json) => StoreDeletion(
    currencyCode: _currency(json),
    requestedAt: Json.date(json, const ['requestedAt']),
    openOrders: Json.integer(json, const ['openOrders']),
    openReturns: Json.integer(json, const ['openReturns']),
    owed: Json.number(json, const ['owed']),
    returnsOpenUntil: Json.date(json, const ['returnsOpenUntil']),
  );

  static SabaBills bills(Map<String, dynamic> json) => SabaBills(
    currencyCode: _currency(json),
    ratePercent: Json.number(json, const ['ratePercent']),
    current: bill(Json.objectOrNull(json, const ['current']) ?? const {}),
    past: Json.mapList(Json.objects(json, const ['past']), bill),
  );
}

/// Merchant-only API surface.
///
/// Every endpoint here is scoped to `/merchants/me`, so the server resolves the
/// store from the token. No merchant id is ever sent by the client, which is
/// what makes cross-merchant access impossible (specification section 51).
abstract interface class MerchantRepository {
  Future<Result<MerchantDashboard>> dashboard();

  Future<Result<PaginatedList<MerchantProductRow>>> products({
    String? status,
    String? filter,
    String? query,
    int page = 1,
  });

  /// One of the merchant's own products, in full.
  ///
  /// The shelf row is a summary — it has no description, no category, no
  /// variants and one image. The edit form needs the whole record, both to
  /// show the merchant what they are changing and so that saving does not
  /// send a shorter list of photographs than the product already has.
  Future<Result<Product>> product(String id);

  /// How many products sit behind each shelf filter.
  Future<Result<Map<String, int>>> productCounts();

  /// The product form's brands: Saba's checked ones, and those this store's
  /// own products use.
  Future<Result<List<Brand>>> brands();

  /// Sets stock outright, which is what the shelf's stepper and its Restock
  /// button both mean.
  Future<Result<void>> setProductStock({
    required String productId,
    required int stock,
  });

  Future<Result<void>> saveProduct(ProductDraft draft);

  Future<Result<void>> submitForApproval(String productId);

  /// Hides a product from shoppers, or shows it again.
  Future<Result<void>> setProductShown(String productId, {required bool shown});

  Future<Result<void>> deleteProduct(String productId);

  /// Puts a product on a flash sale at [salePrice] until [endsAt], or
  /// changes the one running. No review: the store owns its price.
  Future<Result<void>> startFlashSale({
    required String productId,
    required num salePrice,
    required DateTime endsAt,
  });

  /// Ends a product's flash sale now: its price is what it was before.
  Future<Result<void>> endFlashSale(String productId);

  Future<Result<PaginatedList<InventoryRow>>> inventory({int page = 1});

  Future<Result<void>> adjustStock({
    required String inventoryId,
    required int quantity,
    String? reason,
  });

  Future<Result<PaginatedList<MerchantOrderRow>>> orders({
    String? status,
    int page = 1,
  });

  Future<Result<MerchantOrderDetail>> order(String id);

  /// How many orders sit in each status, so a filter pill can carry its own
  /// number instead of the merchant tapping through to find out.
  Future<Result<Map<String, int>>> orderCounts();

  Future<Result<void>> updateOrderStatus({
    required String orderId,
    required String status,
    String? reason,
    Courier? courier,
  });

  /// The store's returns, newest first, each with the order it is on.
  Future<Result<PaginatedList<MerchantReturnRow>>> returns({int page = 1});

  /// APPROVED or REJECTED for a new return; REFUNDED once the item is back
  /// and the cash handed over.
  Future<Result<void>> answerReturn(
    String returnId,
    String status, {
    String? reason,
  });

  Future<Result<MerchantAnalytics>> analytics({String period = 'month'});

  /// What the store owes Saba, this month and before.
  Future<Result<SabaBills>> bills();

  /// Opens the store for orders, or closes it for now.
  Future<Result<void>> setOpen(bool isOpen);

  /// The owner's request to delete the store's account, and what it waits
  /// for.
  Future<Result<StoreDeletion>> deletion();

  /// Asks for it: the store closes at once.
  Future<Result<StoreDeletion>> requestDeletion();

  /// Takes the request back while it waits. The store stays closed.
  Future<Result<void>> cancelDeletion();

  Future<Result<List<MerchantCoupon>>> coupons();

  /// Creates it when its id is empty, otherwise saves the changes.
  Future<Result<void>> saveCoupon(MerchantCoupon coupon);

  Future<Result<void>> setCouponActive(String id, {required bool isActive});

  Future<Result<void>> deleteCoupon(String id);
}

class MerchantRepositoryImpl implements MerchantRepository {
  const MerchantRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<MerchantDashboard>> dashboard() {
    return client.get<MerchantDashboard>(
      ApiEndpoints.merchantDashboard,
      decoder: (envelope) => MerchantMappers.dashboard(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<PaginatedList<MerchantProductRow>>> products({
    String? status,
    String? filter,
    String? query,
    int page = 1,
  }) {
    return client.getPage<MerchantProductRow>(
      ApiEndpoints.merchantOwnProducts,
      page: page,
      queryParameters: <String, dynamic>{
        'status': ?status,
        'filter': ?filter,
        'q': ?query,
      },
      itemDecoder: MerchantMappers.productRow,
    );
  }

  @override
  Future<Result<Product>> product(String id) {
    return client.get<Product>(
      ApiEndpoints.merchantOwnProduct(id),
      // The same shape and the same mapper as the public product endpoint:
      // it is the same product, seen by its owner.
      decoder: (envelope) => CatalogMappers.product(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<Map<String, int>>> productCounts() {
    return client.get<Map<String, int>>(
      ApiEndpoints.merchantProductCounts,
      decoder: (envelope) => envelope.dataAsMap.map(
        (key, value) => MapEntry(
          key,
          Json.integer(<String, dynamic>{'v': value}, const ['v']),
        ),
      ),
    );
  }

  @override
  Future<Result<void>> setProductStock({
    required String productId,
    required int stock,
  }) {
    return client.command(
      ApiEndpoints.merchantProductStock(productId),
      method: 'PATCH',
      data: <String, dynamic>{'stock': stock},
    );
  }

  @override
  Future<Result<void>> saveProduct(ProductDraft draft) {
    if (draft.isNew) {
      return client.command(
        ApiEndpoints.merchantOwnProducts,
        data: draft.toJson(),
      );
    }
    return client.command(
      ApiEndpoints.merchantOwnProduct(draft.id!),
      method: 'PUT',
      data: draft.toJson(),
    );
  }

  @override
  Future<Result<void>> submitForApproval(String productId) =>
      client.command(ApiEndpoints.merchantProductSubmit(productId));

  @override
  Future<Result<void>> setProductShown(
    String productId, {
    required bool shown,
  }) => client.command(
    ApiEndpoints.merchantProductVisibility(productId),
    data: <String, dynamic>{'isActive': shown},
  );

  @override
  Future<Result<void>> deleteProduct(String productId) => client.command(
    ApiEndpoints.merchantOwnProduct(productId),
    method: 'DELETE',
  );

  @override
  Future<Result<void>> startFlashSale({
    required String productId,
    required num salePrice,
    required DateTime endsAt,
  }) => client.command(
    ApiEndpoints.merchantProductFlashSale(productId),
    data: <String, dynamic>{
      'salePrice': salePrice,
      'saleEndsAt': endsAt.toUtc().toIso8601String(),
    },
  );

  @override
  Future<Result<void>> endFlashSale(String productId) => client.command(
    ApiEndpoints.merchantProductFlashSale(productId),
    method: 'DELETE',
  );

  @override
  Future<Result<PaginatedList<InventoryRow>>> inventory({int page = 1}) {
    return client.getPage<InventoryRow>(
      ApiEndpoints.merchantInventory,
      page: page,
      itemDecoder: MerchantMappers.inventoryRow,
    );
  }

  @override
  Future<Result<void>> adjustStock({
    required String inventoryId,
    required int quantity,
    String? reason,
  }) {
    // The server records an inventory transaction and applies the change
    // atomically; the client only states the intent.
    return client.command(
      ApiEndpoints.merchantInventoryAdjust(inventoryId),
      data: <String, dynamic>{'quantity': quantity, 'reason': ?reason},
    );
  }

  @override
  Future<Result<PaginatedList<MerchantOrderRow>>> orders({
    String? status,
    int page = 1,
  }) {
    return client.getPage<MerchantOrderRow>(
      ApiEndpoints.merchantOrders,
      page: page,
      queryParameters: <String, dynamic>{'status': ?status},
      itemDecoder: MerchantMappers.orderRow,
    );
  }

  @override
  Future<Result<MerchantOrderDetail>> order(String id) {
    return client.get<MerchantOrderDetail>(
      ApiEndpoints.merchantOrder(id),
      decoder: (envelope) => MerchantMappers.orderDetail(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<Map<String, int>>> orderCounts() {
    return client.get<Map<String, int>>(
      ApiEndpoints.merchantOrderCounts,
      decoder: (envelope) => envelope.dataAsMap.map(
        (key, value) => MapEntry(
          key.toUpperCase(),
          Json.integer(<String, dynamic>{'v': value}, const ['v']),
        ),
      ),
    );
  }

  @override
  Future<Result<void>> updateOrderStatus({
    required String orderId,
    required String status,
    String? reason,
    Courier? courier,
  }) {
    return client.command(
      ApiEndpoints.merchantOrderStatus(orderId),
      method: 'PATCH',
      data: <String, dynamic>{
        'status': status,
        'reason': ?reason,
        ...?courier?.toJson(),
      },
    );
  }

  @override
  Future<Result<PaginatedList<MerchantReturnRow>>> returns({int page = 1}) {
    return client.getPage<MerchantReturnRow>(
      ApiEndpoints.merchantReturns,
      page: page,
      itemDecoder: MerchantMappers.returnRow,
    );
  }

  @override
  Future<Result<void>> answerReturn(
    String returnId,
    String status, {
    String? reason,
  }) => client.command(
    ApiEndpoints.merchantReturn(returnId),
    method: 'PATCH',
    data: <String, dynamic>{'status': status, 'reason': ?reason},
  );

  @override
  Future<Result<MerchantAnalytics>> analytics({String period = 'month'}) {
    return client.get<MerchantAnalytics>(
      ApiEndpoints.merchantAnalytics,
      queryParameters: <String, dynamic>{'period': period},
      decoder: (envelope) => MerchantMappers.analytics(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<SabaBills>> bills() {
    return client.get<SabaBills>(
      ApiEndpoints.merchantBills,
      decoder: (envelope) => MerchantMappers.bills(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<void>> setOpen(bool isOpen) => client.command(
    ApiEndpoints.merchantStoreOpen,
    method: 'PATCH',
    data: <String, dynamic>{'isOpen': isOpen},
  );

  @override
  Future<Result<StoreDeletion>> deletion() => client.get<StoreDeletion>(
    ApiEndpoints.merchantDeletion,
    decoder: (envelope) => MerchantMappers.deletion(envelope.dataAsMap),
  );

  @override
  Future<Result<StoreDeletion>> requestDeletion() => client.post<StoreDeletion>(
    ApiEndpoints.merchantDeletion,
    decoder: (envelope) => MerchantMappers.deletion(envelope.dataAsMap),
  );

  @override
  Future<Result<void>> cancelDeletion() =>
      client.command(ApiEndpoints.merchantDeletion, method: 'DELETE');

  @override
  Future<Result<List<Brand>>> brands() {
    return client.get<List<Brand>>(
      ApiEndpoints.merchantBrands,
      decoder: (envelope) =>
          Json.mapList(envelope.dataAsList, CatalogMappers.brand),
    );
  }

  @override
  Future<Result<List<MerchantCoupon>>> coupons() {
    return client.get<List<MerchantCoupon>>(
      ApiEndpoints.merchantCoupons,
      decoder: (envelope) =>
          Json.mapList(envelope.dataAsList, MerchantMappers.coupon),
    );
  }

  @override
  Future<Result<void>> saveCoupon(MerchantCoupon coupon) => client.command(
    coupon.id.isEmpty
        ? ApiEndpoints.merchantCoupons
        : ApiEndpoints.merchantCoupon(coupon.id),
    method: coupon.id.isEmpty ? 'POST' : 'PUT',
    data: coupon.toJson(),
  );

  @override
  Future<Result<void>> setCouponActive(String id, {required bool isActive}) =>
      client.command(
        ApiEndpoints.merchantCoupon(id),
        method: 'PATCH',
        data: <String, dynamic>{'isActive': isActive},
      );

  @override
  Future<Result<void>> deleteCoupon(String id) =>
      client.command(ApiEndpoints.merchantCoupon(id), method: 'DELETE');
}

final merchantRepositoryProvider = Provider<MerchantRepository>((ref) {
  ref.watch(accountIdProvider);
  return MerchantRepositoryImpl(ref.watch(apiClientProvider));
});

/// The brands the product form offers as the store types. The form reads
/// them again when it opens, so a brand Saba checked since is there.
final merchantBrandsProvider = FutureProvider<List<Brand>>((ref) async {
  return (await ref.watch(merchantRepositoryProvider).brands()).unwrap();
});

final merchantDashboardProvider = FutureProvider<MerchantDashboard>((
  ref,
) async {
  ref.watch(liveTopicProvider(LiveTopic.orders));
  ref.watch(_deletionAskedAt);
  return (await ref.watch(merchantRepositoryProvider).dashboard()).unwrap();
});

/// What the store's account deletion still waits for. Orders and returns
/// finishing change it.
final storeDeletionProvider = FutureProvider<StoreDeletion>((ref) async {
  ref.watch(liveTopicProvider(LiveTopic.orders));
  ref.watch(_deletionAskedAt);
  return (await ref.watch(merchantRepositoryProvider).deletion()).unwrap();
});

/// When the store's account deletion was asked for, from the account. Saba
/// can ask or take it back from the admin web: the app reads the account
/// again on Saba's notice, and what the deletion changes is read with it.
final _deletionAskedAt = Provider<DateTime?>(
  (ref) => ref.watch(
    currentUserProvider.select((user) => user?.merchant?.deletionRequestedAt),
  ),
);

/// What the shelf is currently showing: which filter, and what was typed.
///
/// A record rather than two families, so a search inside "Low stock" is one
/// list rather than the cross product of every filter and every search term.
typedef ProductShelf = ({String? filter, String? query});

class MerchantProductsNotifier extends PagedNotifier<MerchantProductRow> {
  MerchantProductsNotifier(this.shelf);

  final ProductShelf shelf;

  @override
  Future<PagedState<MerchantProductRow>> build() {
    ref.watch(accountIdProvider);
    return super.build();
  }

  @override
  Future<Result<PaginatedList<MerchantProductRow>>> fetchPage(int page) {
    return ref
        .read(merchantRepositoryProvider)
        .products(filter: shelf.filter, query: shelf.query, page: page);
  }
}

final merchantProductsProvider =
    AsyncNotifierProvider.family<
      MerchantProductsNotifier,
      PagedState<MerchantProductRow>,
      ProductShelf
    >(MerchantProductsNotifier.new);

final merchantProductCountsProvider = FutureProvider<Map<String, int>>((
  ref,
) async {
  return (await ref.watch(merchantRepositoryProvider).productCounts()).unwrap();
});

class MerchantInventoryNotifier extends PagedNotifier<InventoryRow> {
  @override
  Future<PagedState<InventoryRow>> build() {
    ref.watch(accountIdProvider);
    return super.build();
  }

  @override
  Future<Result<PaginatedList<InventoryRow>>> fetchPage(int page) =>
      ref.read(merchantRepositoryProvider).inventory(page: page);
}

final merchantInventoryProvider =
    AsyncNotifierProvider<MerchantInventoryNotifier, PagedState<InventoryRow>>(
      MerchantInventoryNotifier.new,
    );

class MerchantOrdersNotifier extends PagedNotifier<MerchantOrderRow> {
  MerchantOrdersNotifier(this.status);

  final String? status;

  @override
  Future<PagedState<MerchantOrderRow>> build() {
    ref.watch(accountIdProvider);
    ref.watch(liveTopicProvider(LiveTopic.orders));
    return super.build();
  }

  @override
  Future<Result<PaginatedList<MerchantOrderRow>>> fetchPage(int page) {
    return ref
        .read(merchantRepositoryProvider)
        .orders(status: status, page: page);
  }
}

/// The store's returns. A shopper asking for one, and each answer, arrive on
/// the orders topic, so the list follows without a pull.
class MerchantReturnsNotifier extends PagedNotifier<MerchantReturnRow> {
  @override
  Future<PagedState<MerchantReturnRow>> build() {
    ref.watch(accountIdProvider);
    ref.watch(liveTopicProvider(LiveTopic.orders));
    return super.build();
  }

  @override
  Future<Result<PaginatedList<MerchantReturnRow>>> fetchPage(int page) {
    return ref.read(merchantRepositoryProvider).returns(page: page);
  }
}

final merchantReturnsProvider =
    AsyncNotifierProvider<MerchantReturnsNotifier, PagedState<MerchantReturnRow>>(
      MerchantReturnsNotifier.new,
    );

final merchantOrderCountsProvider = FutureProvider<Map<String, int>>((
  ref,
) async {
  ref.watch(liveTopicProvider(LiveTopic.orders));
  return (await ref.watch(merchantRepositoryProvider).orderCounts()).unwrap();
});

final merchantOrderDetailProvider =
    FutureProvider.family<MerchantOrderDetail, String>((ref, id) async {
      ref.watch(liveTopicProvider(LiveTopic.orders));
      return (await ref.watch(merchantRepositoryProvider).order(id)).unwrap();
    });

final merchantOrdersProvider =
    AsyncNotifierProvider.family<
      MerchantOrdersNotifier,
      PagedState<MerchantOrderRow>,
      String?
    >(MerchantOrdersNotifier.new);

final merchantAnalyticsProvider =
    FutureProvider.family<MerchantAnalytics, String>((ref, period) async {
      return (await ref
              .watch(merchantRepositoryProvider)
              .analytics(period: period))
          .unwrap();
    });

final sabaBillsProvider = FutureProvider<SabaBills>((ref) async {
  return (await ref.watch(merchantRepositoryProvider).bills()).unwrap();
});

/// The signed-in store's coupons. Keyed to who is signed in, so a new store
/// never opens on the last store's codes.
final merchantCouponsProvider = FutureProvider<List<MerchantCoupon>>((
  ref,
) async {
  ref.watch(
    currentUserProvider.select(
      (user) => user == null ? null : (user.email, user.phone),
    ),
  );
  return (await ref.watch(merchantRepositoryProvider).coupons()).unwrap();
});
