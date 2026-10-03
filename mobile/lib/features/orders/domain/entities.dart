import 'package:flutter/foundation.dart';

import '../../../core/location/governorate.dart';

/// Delivery lifecycle of an order (specification sections 15 and 26).
enum OrderStatus {
  pending,
  confirmed,
  processing,
  shipped,
  delivered,
  cancelled,

  /// The shopper turned the parcel away at the door; nothing was paid.
  refused,
  returned,
  refunded,
  unknown;

  static OrderStatus fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'PENDING' || 'NEW' => OrderStatus.pending,
        'CONFIRMED' => OrderStatus.confirmed,
        'PROCESSING' => OrderStatus.processing,
        'SHIPPED' || 'IN_TRANSIT' => OrderStatus.shipped,
        'DELIVERED' || 'COMPLETED' => OrderStatus.delivered,
        'CANCELLED' || 'CANCELED' => OrderStatus.cancelled,
        'REFUSED' => OrderStatus.refused,
        'RETURNED' => OrderStatus.returned,
        'REFUNDED' => OrderStatus.refunded,
        _ => OrderStatus.unknown,
      };

  String get apiValue => switch (this) {
    OrderStatus.pending => 'PENDING',
    OrderStatus.confirmed => 'CONFIRMED',
    OrderStatus.processing => 'PROCESSING',
    OrderStatus.shipped => 'SHIPPED',
    OrderStatus.delivered => 'DELIVERED',
    OrderStatus.cancelled => 'CANCELLED',
    OrderStatus.refused => 'REFUSED',
    OrderStatus.returned => 'RETURNED',
    OrderStatus.refunded => 'REFUNDED',
    OrderStatus.unknown => '',
  };

  bool get isTerminal =>
      this == OrderStatus.delivered ||
      this == OrderStatus.cancelled ||
      this == OrderStatus.refused ||
      this == OrderStatus.returned ||
      this == OrderStatus.refunded;
}

/// Payment lifecycle (specification section 14).
enum PaymentStatus {
  pending,
  processing,
  paid,
  failed,
  cancelled,
  refunded,
  partiallyRefunded,
  unknown;

  static PaymentStatus fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'PENDING' => PaymentStatus.pending,
        'PROCESSING' => PaymentStatus.processing,
        'PAID' || 'CAPTURED' || 'SUCCEEDED' => PaymentStatus.paid,
        'FAILED' => PaymentStatus.failed,
        'CANCELLED' || 'CANCELED' => PaymentStatus.cancelled,
        'REFUNDED' => PaymentStatus.refunded,
        'PARTIALLY_REFUNDED' => PaymentStatus.partiallyRefunded,
        _ => PaymentStatus.unknown,
      };
}

/// A purchased line.
///
/// These fields are the snapshot the backend stored at purchase time. They are
/// deliberately not re-read from the live product, so editing or deleting a
/// product never rewrites history (specification section 16).
@immutable
class OrderItem {
  const OrderItem({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.currencyCode,
    this.productId,
    this.sku,
    this.variantLabel,
    this.imageUrl,
    this.merchantId,
    this.merchantName,
    this.discount = 0,
    this.tax = 0,
    this.status = OrderStatus.unknown,
    this.canReturn = false,
    num? paidUnitPrice,
  }) : paidUnitPrice = paidUnitPrice ?? unitPrice;

  final String id;
  final String productName;
  final int quantity;
  final num unitPrice;

  /// What one unit really cost after the store's coupon: what a return of
  /// it gives back.
  final num paidUnitPrice;
  final num lineTotal;
  final String currencyCode;

  /// May be null if the product was later removed; the snapshot still renders.
  final String? productId;

  final String? sku;
  final String? variantLabel;
  final String? imageUrl;
  final String? merchantId;
  final String? merchantName;
  final num discount;
  final num tax;

  /// Per-item status, since each merchant fulfils their own lines.
  final OrderStatus status;

  final bool canReturn;
}

/// A step in the order's history.
@immutable
class OrderTimelineEntry {
  const OrderTimelineEntry({
    required this.status,
    required this.occurredAt,
    this.noteCode,
    this.storeName,
    this.reasonCode,
    this.note,
  });

  final OrderStatus status;
  final DateTime occurredAt;

  /// What happened, as a code the app says in the reader's language.
  final String? noteCode;

  /// The store that moved its part of the order.
  final String? storeName;

  /// Why it was cancelled or declined, as a code.
  final String? reasonCode;

  /// Words someone typed, shown as typed.
  final String? note;
}

/// The delivery address as it was at purchase time: what the shopper sees
/// on the order, and what the store's driver goes by.
@immutable
class OrderAddress {
  const OrderAddress({
    required this.fullName,
    this.phone,
    this.governorate,
    this.area,
    this.street,
    this.landmark,
    this.instructions,
  });

  final String fullName;
  final String? phone;
  final Governorate? governorate;
  final String? area;
  final String? street;

  /// The nearest landmark, how the driver finds the door.
  final String? landmark;
  final String? instructions;

  /// Street, area, city, the city in [languageCode].
  String formattedIn(String languageCode) =>
      <String?>[street, area, governorate?.nameIn(languageCode)]
          .where((part) => part != null && part.trim().isNotEmpty)
          .join(
            // Arabic writes its own comma.
            languageCode == 'ar' ? '، ' : ', ',
          );
}

/// Row shape for the orders list.
@immutable
class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.orderNumber,
    required this.placedAt,
    required this.status,
    required this.paymentStatus,
    required this.total,
    required this.currencyCode,
    required this.itemCount,
    this.previewImageUrl,
    this.merchantNames = const <String>[],
    this.isCashOnDelivery = false,
  });

  final String id;
  final String orderNumber;
  final DateTime placedAt;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final num total;
  final String currencyCode;
  final int itemCount;
  final String? previewImageUrl;
  final List<String> merchantNames;

  /// Paid in cash to the driver, so "not paid yet" is the plan, not a fault.
  final bool isCashOnDelivery;
}

/// Full order detail.
@immutable
class Order {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.placedAt,
    required this.status,
    required this.paymentStatus,
    required this.items,
    required this.subtotal,
    required this.total,
    required this.currencyCode,
    this.discount = 0,
    this.shipping = 0,
    this.tax = 0,
    this.shippingAddress,
    this.paymentMethodLabel,
    this.estimatedDelivery,
    this.timeline = const <OrderTimelineEntry>[],
    this.invoiceUrl,
    this.canCancel = false,
    this.canReturn = false,
    this.isCashOnDelivery = false,
    this.parts = const <String, OrderStorePart>{},
  });

  final String id;
  final String orderNumber;
  final DateTime placedAt;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final List<OrderItem> items;

  /// Each store's part, by store id: what its driver collects, and who that
  /// driver is once it has shipped.
  final Map<String, OrderStorePart> parts;

  /// Store id to what its driver collects: each store delivers, and each
  /// driver is paid their own part in cash.
  Map<String, num> get dueByStore => {
    for (final MapEntry(:key, :value) in parts.entries) key: value.amountDue,
  };
  final num subtotal;
  final num total;
  final String currencyCode;
  final num discount;
  final num shipping;
  final num tax;
  final OrderAddress? shippingAddress;
  final String? paymentMethodLabel;
  final String? estimatedDelivery;
  final List<OrderTimelineEntry> timeline;
  final String? invoiceUrl;

  /// Whether the actions are offered. The backend decides for real; these only
  /// keep the UI from showing a button that would be rejected.
  final bool canCancel;
  final bool canReturn;

  /// Paid in cash to the driver, so "not paid yet" is the plan, not a fault.
  final bool isCashOnDelivery;

  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  /// Lines grouped by the store that fulfils them.
  Map<String, List<OrderItem>> get itemsByMerchant {
    final grouped = <String, List<OrderItem>>{};
    for (final item in items) {
      final key = item.merchantName ?? '';
      grouped.putIfAbsent(key, () => <OrderItem>[]).add(item);
    }
    return grouped;
  }
}

/// One store's part of an order, as the shopper sees it.
@immutable
class OrderStorePart {
  const OrderStorePart({
    required this.amountDue,
    this.courierName,
    this.courierPhone,
    this.received,
    this.deliveryTime,
  });

  /// What its driver collects at the door.
  final num amountDue;

  /// The store's driver bringing it, once it has shipped.
  final String? courierName;
  final String? courierPhone;

  /// The shopper's answer to "did you receive it?"; null until asked.
  final bool? received;

  /// How long the store takes, as its code (`1_2_DAYS`): "Expected: 1–2
  /// days" before it ships.
  final String? deliveryTime;
}

/// One priced line on an invoice.
@immutable
class InvoiceLine {
  const InvoiceLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.merchantName,
  });

  final String description;
  final int quantity;
  final num unitPrice;
  final num total;
  final String? merchantName;
}

/// The invoice for an order (specification section 15).
///
/// Rendered from the server's figures. The client never recomputes a total: a
/// historical invoice must keep saying what was actually charged, even after
/// prices change (specification section 16).
@immutable
class Invoice {
  const Invoice({
    required this.orderId,
    required this.orderNumber,
    required this.issuedAt,
    required this.lines,
    required this.subtotal,
    required this.total,
    required this.currencyCode,
    this.invoiceNumber,
    this.discount = 0,
    this.shipping = 0,
    this.tax = 0,
    this.paymentMethodLabel,
    this.paymentStatus = PaymentStatus.unknown,
    this.billedTo,
    this.sellerName,
    this.downloadUrl,
  });

  final String orderId;
  final String orderNumber;
  final DateTime issuedAt;
  final List<InvoiceLine> lines;
  final num subtotal;
  final num total;
  final String currencyCode;
  final String? invoiceNumber;
  final num discount;
  final num shipping;
  final num tax;
  final String? paymentMethodLabel;
  final PaymentStatus paymentStatus;
  final OrderAddress? billedTo;
  final String? sellerName;

  /// A server-rendered PDF, when the backend offers one.
  final String? downloadUrl;

  String get reference => invoiceNumber ?? orderNumber;

  /// The order was cancelled or refused: none of it will be charged.
  bool get isCancelled => paymentStatus == PaymentStatus.cancelled;
}
