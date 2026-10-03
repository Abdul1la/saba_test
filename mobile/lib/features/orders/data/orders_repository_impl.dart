import '../../../core/config/api_endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/result.dart';
import '../../../core/location/governorate.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/json_reader.dart';
import '../domain/entities.dart';
import '../domain/orders_repository.dart';

class OrderMappers {
  const OrderMappers._();

  static OrderSummary summary(Map<String, dynamic> json) => OrderSummary(
    id: Json.str(json, const ['id', 'orderId']),
    orderNumber: Json.str(json, const ['orderNumber', 'number', 'reference']),
    placedAt:
        Json.date(json, const ['placedAt', 'createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    status: OrderStatus.fromApi(json['status'] ?? json['orderStatus']),
    paymentStatus: PaymentStatus.fromApi(json['paymentStatus']),
    total: Json.number(json, const ['total', 'grandTotal']),
    currencyCode: Json.str(json, const [
      'currencyCode',
      'currency',
    ], fallback: AppConfig.fallbackCurrencyCode),
    itemCount: Json.integer(json, const ['itemCount', 'itemsCount']),
    previewImageUrl: Json.strOrNull(json, const [
      'previewImageUrl',
      'imageUrl',
      'thumbnail',
    ]),
    merchantNames: Json.strings(json, const ['merchantNames', 'merchants']),
    isCashOnDelivery: _isCashOnDelivery(json),
  );

  static bool _isCashOnDelivery(Map<String, dynamic> json) =>
      switch (Json.strOrNull(json, const [
        'paymentMethodType',
        'paymentType',
      ])?.toUpperCase()) {
        'COD' || 'CASH_ON_DELIVERY' => true,
        _ => false,
      };

  static Order order(Map<String, dynamic> json) {
    final addressJson = Json.objectOrNull(json, const [
      'shippingAddress',
      'address',
    ]);

    return Order(
      id: Json.str(json, const ['id', 'orderId']),
      orderNumber: Json.str(json, const ['orderNumber', 'number', 'reference']),
      placedAt:
          Json.date(json, const ['placedAt', 'createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: OrderStatus.fromApi(json['status'] ?? json['orderStatus']),
      paymentStatus: PaymentStatus.fromApi(json['paymentStatus']),
      items: Json.mapList(
        Json.objects(json, const ['items', 'orderItems']),
        item,
      ),
      subtotal: Json.number(json, const ['subtotal', 'itemsTotal']),
      total: Json.number(json, const ['total', 'grandTotal']),
      currencyCode: Json.str(json, const [
        'currencyCode',
        'currency',
      ], fallback: AppConfig.fallbackCurrencyCode),
      discount: Json.number(json, const ['discount', 'discountTotal']),
      shipping: Json.number(json, const ['shipping', 'shippingTotal']),
      tax: Json.number(json, const ['tax', 'taxTotal']),
      shippingAddress: addressJson == null ? null : address(addressJson),
      paymentMethodLabel: Json.strOrNull(json, const [
        'paymentMethodLabel',
        'paymentMethod',
      ]),
      estimatedDelivery: Json.strOrNull(json, const [
        'estimatedDelivery',
        'deliveryEstimate',
      ]),
      timeline: Json.mapList(
        Json.objects(json, const ['timeline', 'statusHistory', 'history']),
        timelineEntry,
      ),
      invoiceUrl: Json.strOrNull(json, const ['invoiceUrl']),
      canCancel: Json.boolean(json, const ['canCancel', 'cancellable']),
      canReturn: Json.boolean(json, const ['canReturn', 'returnable']),
      isCashOnDelivery: _isCashOnDelivery(json),
      parts: <String, OrderStorePart>{
        for (final part in Json.objects(json, const ['storeParts']))
          Json.str(part, const ['merchantId']): OrderStorePart(
            amountDue: Json.number(part, const ['amountDue']),
            courierName: Json.strOrNull(part, const ['courierName']),
            courierPhone: Json.strOrNull(part, const ['courierPhone']),
            received: part['received'] as bool?,
            deliveryTime: Json.strOrNull(part, const ['deliveryTime']),
          ),
      },
    );
  }

  static OrderItem item(Map<String, dynamic> json) => OrderItem(
    id: Json.str(json, const ['id', 'orderItemId']),
    // The snapshot field wins over any live product name.
    productName: Json.str(json, const [
      'productName',
      'nameSnapshot',
      'name',
      'title',
    ]),
    quantity: Json.integer(json, const ['quantity', 'qty'], fallback: 1),
    unitPrice: Json.number(json, const ['unitPrice', 'price']),
    paidUnitPrice: Json.numberOrNull(json, const ['paidUnitPrice']),
    lineTotal: Json.number(json, const ['lineTotal', 'total', 'subtotal']),
    currencyCode: Json.str(json, const [
      'currencyCode',
      'currency',
    ], fallback: AppConfig.fallbackCurrencyCode),
    productId: Json.strOrNull(json, const ['productId']),
    sku: Json.strOrNull(json, const ['sku', 'skuSnapshot']),
    variantLabel: Json.strOrNull(json, const [
      'variantLabel',
      'variantName',
      'variant',
    ]),
    imageUrl: Json.strOrNull(json, const ['imageUrl', 'image', 'thumbnail']),
    merchantId: Json.strOrNull(json, const ['merchantId']),
    merchantName: Json.strOrNull(json, const ['merchantName', 'storeName']),
    discount: Json.number(json, const ['discount']),
    tax: Json.number(json, const ['tax']),
    status: OrderStatus.fromApi(json['status'] ?? json['itemStatus']),
    canReturn: Json.boolean(json, const ['canReturn', 'returnable']),
  );

  static OrderTimelineEntry timelineEntry(Map<String, dynamic> json) =>
      OrderTimelineEntry(
        status: OrderStatus.fromApi(json['status']),
        occurredAt:
            Json.date(json, const ['occurredAt', 'createdAt', 'at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        noteCode: Json.strOrNull(json, const ['noteCode']),
        storeName: Json.strOrNull(json, const ['store', 'storeName']),
        reasonCode: Json.strOrNull(json, const ['reasonCode', 'reason']),
        note: Json.strOrNull(json, const ['note', 'comment', 'description']),
      );

  static InvoiceLine invoiceLine(Map<String, dynamic> json) => InvoiceLine(
    description: Json.str(json, const ['description', 'name', 'title']),
    quantity: Json.integer(json, const ['quantity', 'qty']),
    unitPrice: Json.number(json, const ['unitPrice', 'price']),
    total: Json.number(json, const ['total', 'lineTotal', 'amount']),
    merchantName: Json.strOrNull(json, const ['merchantName', 'storeName']),
  );

  static Invoice invoice(Map<String, dynamic> json) {
    final billedTo = Json.objectOrNull(json, const [
      'billedTo',
      'billingAddress',
      'shippingAddress',
      'address',
    ]);

    return Invoice(
      orderId: Json.str(json, const ['orderId', 'order', 'id']),
      orderNumber: Json.str(json, const ['orderNumber', 'number', 'reference']),
      invoiceNumber: Json.strOrNull(json, const ['invoiceNumber', 'invoiceNo']),
      issuedAt:
          Json.date(json, const ['issuedAt', 'createdAt', 'date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lines: Json.mapList(
        Json.objects(json, const ['lines', 'items', 'orderItems']),
        invoiceLine,
      ),
      subtotal: Json.number(json, const ['subtotal', 'itemsTotal']),
      total: Json.number(json, const ['total', 'grandTotal']),
      currencyCode: Json.str(json, const [
        'currencyCode',
        'currency',
      ], fallback: AppConfig.fallbackCurrencyCode),
      discount: Json.number(json, const ['discount', 'discountTotal']),
      shipping: Json.number(json, const ['shipping', 'shippingTotal']),
      tax: Json.number(json, const ['tax', 'taxTotal']),
      paymentMethodLabel: Json.strOrNull(json, const [
        'paymentMethodLabel',
        'paymentMethod',
      ]),
      paymentStatus: PaymentStatus.fromApi(json['paymentStatus']),
      billedTo: billedTo == null ? null : address(billedTo),
      sellerName: Json.strOrNull(json, const ['sellerName', 'merchantName']),
      downloadUrl: Json.strOrNull(json, const ['downloadUrl', 'pdfUrl', 'url']),
    );
  }

  static OrderAddress address(Map<String, dynamic> json) => OrderAddress(
    fullName: Json.str(json, const ['fullName', 'name', 'recipientName']),
    phone: Json.strOrNull(json, const ['phone', 'phoneNumber']),
    governorate: Governorate.fromApi(json['governorate'] ?? json['city']),
    area: Json.strOrNull(json, const ['area', 'district']),
    street: Json.strOrNull(json, const ['street', 'addressLine', 'line1']),
    landmark: Json.strOrNull(json, const ['landmark', 'nearestLandmark']),
    instructions: Json.strOrNull(json, const [
      'instructions',
      'deliveryInstructions',
    ]),
  );
}

class OrdersRepositoryImpl implements OrdersRepository {
  const OrdersRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<PaginatedList<OrderSummary>>> fetchOrders({
    OrderStatus? status,
    int page = 1,
  }) {
    return client.getPage<OrderSummary>(
      ApiEndpoints.orders,
      page: page,
      queryParameters: <String, dynamic>{
        if (status != null && status != OrderStatus.unknown)
          'status': status.apiValue,
      },
      itemDecoder: OrderMappers.summary,
    );
  }

  @override
  Future<Result<Order>> fetchOrder(String id) {
    return client.get<Order>(
      ApiEndpoints.order(id),
      decoder: (envelope) => OrderMappers.order(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<Invoice>> fetchInvoice(String orderId) {
    return client.get<Invoice>(
      ApiEndpoints.orderInvoice(orderId),
      decoder: (envelope) => OrderMappers.invoice(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<Order>> cancelOrder({
    required String orderId,
    required String reason,
    String? note,
  }) {
    return client.post<Order>(
      ApiEndpoints.cancelOrder(orderId),
      data: <String, dynamic>{'reason': reason, 'note': ?note},
      decoder: (envelope) => OrderMappers.order(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<Order>> confirmReceived({
    required String orderId,
    required String merchantId,
    required bool received,
  }) {
    return client.post<Order>(
      ApiEndpoints.orderReceived(orderId),
      data: <String, dynamic>{'merchantId': merchantId, 'received': received},
      decoder: (envelope) => OrderMappers.order(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<void>> requestReturn({
    required String orderId,
    required List<ReturnLine> lines,
    required String reason,
    String? description,
  }) {
    return client.command(
      ApiEndpoints.returns,
      data: <String, dynamic>{
        'orderId': orderId,
        'reason': reason,
        'description': ?description,
        'items': [
          for (final line in lines)
            <String, dynamic>{
              'orderItemId': line.orderItemId,
              'quantity': line.quantity,
            },
        ],
      },
    );
  }
}
