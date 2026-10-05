import 'package:flutter/foundation.dart';

import '../../../core/location/governorate.dart';
import '../../orders/domain/entities.dart' show OrderAddress;
import '../../returns/domain/entities.dart' show ReturnDetail, ReturnSummary;

/// One point on a sales chart.
@immutable
class SalesPoint {
  const SalesPoint({
    required this.label,
    required this.value,
    this.from,
    this.unit,
  });

  /// The server's own name for it, for when [from] is missing.
  final String label;
  final num value;

  /// When the stretch starts, and whether it is a `DAY`, `WEEK` or
  /// `MONTH`: the app names it in the reader's language.
  final DateTime? from;
  final String? unit;
}

/// A product row in the merchant's own catalogue.
@immutable
class MerchantProductRow {
  const MerchantProductRow({
    required this.id,
    required this.name,
    required this.price,
    required this.currencyCode,
    required this.status,
    this.imageUrl,
    this.sku,
    this.stock = 0,
    this.isActive = true,
    this.rejectionReason,
    this.takenDown = false,
    this.takenDownReason,
    this.lowStockThreshold,
    this.originalPrice,
    this.saleEndsAt,
    this.hasVariants = false,
  });

  final String id;
  final String name;

  /// Sold in options: its stock is set per option, never for the whole.
  final bool hasVariants;

  /// What it sells for now: during a flash sale, the sale price.
  final num price;
  final String currencyCode;

  /// The price before a flash sale, or the one a store shows struck through.
  final num? originalPrice;

  /// When its flash sale ends; null without one.
  final DateTime? saleEndsAt;

  bool get isOnFlashSale => saleEndsAt != null;

  /// What a flash sale takes its price down from.
  num get priceBeforeSale => isOnFlashSale ? originalPrice ?? price : price;

  /// DRAFT | PENDING | APPROVED | REJECTED
  final String status;

  final String? imageUrl;
  final String? sku;
  final int stock;
  final bool isActive;
  final String? rejectionReason;

  /// Saba took it down (API_CONTRACT.md 6.8): out of the shop whatever
  /// [isActive] says, and the store cannot put it back.
  final bool takenDown;
  final String? takenDownReason;

  /// Below this the row is "running low". Without it the screen would have to
  /// invent a number, and a merchant selling by the pallet and one selling
  /// wedding dresses do not agree on what low means.
  final int? lowStockThreshold;

  bool get isOutOfStock => stock <= 0;

  bool get isLowStock =>
      lowStockThreshold != null && stock > 0 && stock <= lowStockThreshold!;

  bool get isDraft => status.toUpperCase() == 'DRAFT';
  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isApproved => status.toUpperCase() == 'APPROVED';
  bool get isRejected => status.toUpperCase() == 'REJECTED';
}

/// A stock-keeping row: one product or one variant (specification section 25).
@immutable
class InventoryRow {
  const InventoryRow({
    required this.id,
    required this.productId,
    required this.name,
    required this.available,
    this.variantLabel,
    this.sku,
    this.imageUrl,
    this.reserved = 0,
    this.sold = 0,
    this.lowStockThreshold,
  });

  final String id;
  final String productId;
  final String name;
  final int available;
  final String? variantLabel;
  final String? sku;
  final String? imageUrl;

  /// Held for orders that are placed but not yet fulfilled.
  final int reserved;

  final int sold;
  final int? lowStockThreshold;

  bool get isOutOfStock => available <= 0;
  bool get isLowStock =>
      lowStockThreshold != null &&
      available > 0 &&
      available <= lowStockThreshold!;
}

/// Everything the merchant dashboard shows (specification section 23).
@immutable
class MerchantDashboard {
  const MerchantDashboard({
    required this.currencyCode,
    this.todaySales = 0,
    this.totalSales = 0,
    this.revenue = 0,
    this.orderCount = 0,
    this.productCount = 0,
    this.customerCount = 0,
    this.pendingOrders = 0,
    this.lowStockCount = 0,
    this.outOfStockCount = 0,
    this.rejectedCount = 0,
    this.returnCount = 0,
    this.refundTotal = 0,
    this.salesSeries = const <SalesPoint>[],
    this.topProducts = const <MerchantProductRow>[],
    this.previousRevenue,
    this.comparisonDays,
    this.oldestPendingHours,
    this.orderCountDelta,
    this.rating,
    this.ratingCount,
    this.isOpen = true,
  });

  final String currencyCode;
  final num todaySales;
  final num totalSales;
  final num revenue;
  final int orderCount;
  final int productCount;
  final int customerCount;
  final int pendingOrders;
  final int lowStockCount;
  final int outOfStockCount;

  /// Products Saba did not approve, waiting for the store to change them.
  final int rejectedCount;
  final int returnCount;
  final num refundTotal;
  final List<SalesPoint> salesSeries;
  final List<MerchantProductRow> topProducts;

  // Everything below is nullable on purpose. A merchant reading "+0%" cannot
  // tell a flat month from a figure the server never sent, so a field the
  // backend has not answered is absent rather than zero, and the screen says
  // nothing rather than something untrue.

  /// The same span of the previous period, so "up 12%" compares like with
  /// like — nineteen days against nineteen days, not against a whole month.
  final num? previousRevenue;
  final int? comparisonDays;

  /// How long the oldest unconfirmed order has waited. This is the difference
  /// between "7 orders" and "7 orders, one of them since Tuesday".
  final int? oldestPendingHours;

  final int? orderCountDelta;
  final num? rating;
  final int? ratingCount;

  /// Whether the owner has the store open for orders.
  final bool isOpen;
}

/// Merchant-scoped view of an order: only their own lines (section 26).
@immutable
class MerchantOrderRow {
  const MerchantOrderRow({
    required this.id,
    required this.orderNumber,
    required this.placedAt,
    required this.status,
    required this.total,
    required this.currencyCode,
    required this.itemCount,
    this.customerName,
    this.previewImageUrl,
    this.customerArea,
    this.customerGovernorate,
    this.customerPhone,
    this.paymentMethodLabel,
    this.items = const <MerchantOrderItem>[],
    this.autoDeliverAt,
  });

  final String id;
  final String orderNumber;
  final DateTime placedAt;

  /// PENDING | CONFIRMED | PROCESSING | SHIPPED | DELIVERED | CANCELLED
  final String status;

  final num total;
  final String currencyCode;
  final int itemCount;
  final String? customerName;
  final String? previewImageUrl;

  /// The district, which is how an Iraqi address is actually located.
  final String? customerArea;

  /// The customer's city: whether this goes out at the in-city fee.
  final Governorate? customerGovernorate;

  /// Called before confirming: the order and the address, checked by voice.
  final String? customerPhone;

  /// "Cash on delivery", the one way to pay in v1. A merchant decides how
  /// carefully to pack partly on whether the money is already theirs.
  final String? paymentMethodLabel;

  /// The lines, so the card can say what is in the order. A count alone tells
  /// a merchant nothing they can act on.
  final List<MerchantOrderItem> items;

  /// On its way: when Saba marks it delivered if the store has not, five
  /// days after it was sent. Null at every other step.
  final DateTime? autoDeliverAt;
}

/// One of the store's returns, with the order it belongs to: the order's
/// screen is where the store answers it.
@immutable
class MerchantReturnRow {
  const MerchantReturnRow({
    required this.request,
    required this.storeOrderId,
    this.customerName,
  });

  final ReturnSummary request;

  /// The store's order (its part of the shopper's order) the return is on.
  final String storeOrderId;
  final String? customerName;
}

/// One line of a merchant order.
@immutable
class MerchantOrderItem {
  const MerchantOrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
    this.productId,
    this.sku,
    this.imageUrl,
  });

  final String id;
  final String name;
  final int quantity;
  final num price;
  final String? productId;
  final String? sku;
  final String? imageUrl;
}

/// Everything a merchant needs to actually fulfil one order.
///
/// The list row is kept whole rather than re-declared, so the card and the
/// detail screen can never disagree about the status or the total.
@immutable
class MerchantOrderDetail {
  const MerchantOrderDetail({
    required this.row,
    this.items = const <MerchantOrderItem>[],
    this.subtotal = 0,
    this.shipping = 0,
    this.discount = 0,
    this.shippingAddress,
    this.customerPhone,
    this.courier,
    this.returns = const <ReturnDetail>[],
  });

  final MerchantOrderRow row;
  final List<MerchantOrderItem> items;
  final num subtotal;
  final num shipping;

  /// What this store's own coupon took off.
  final num discount;

  /// The shopper's address, in parts: the driver needs the landmark.
  final OrderAddress? shippingAddress;
  final String? customerPhone;

  /// Who took it out, once it has shipped.
  final Courier? courier;

  /// What the shopper asked to send back from this part.
  final List<ReturnDetail> returns;
}

/// Who delivers a store's parcel: its own driver. v1 has no delivery
/// companies and no tracking numbers; the store names its driver when it
/// ships, and the shopper calls them.
@immutable
class Courier {
  const Courier({required this.name, required this.phone});

  final String name;
  final String phone;

  static Courier? fromJson(Map<String, dynamic> json) {
    final name = json['courierName'];
    final phone = json['courierPhone'];
    if (name is! String || phone is! String) return null;
    return Courier(name: name, phone: phone);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'courierType': 'DRIVER',
    'courierName': name,
    'courierPhone': phone,
  };
}

/// Merchant analytics (specification section 28).
@immutable
class MerchantAnalytics {
  const MerchantAnalytics({
    required this.currencyCode,
    this.revenue = 0,
    this.orderCount = 0,
    this.productsSold = 0,
    this.averageOrderValue = 0,
    this.refundTotal = 0,
    this.cancellationCount = 0,
    this.series = const <SalesPoint>[],
    this.topProducts = const <MerchantProductRow>[],
    this.previousRevenue,
  });

  final String currencyCode;
  final num revenue;
  final int orderCount;
  final int productsSold;
  final num averageOrderValue;
  final num refundTotal;
  final int cancellationCount;
  final List<SalesPoint> series;
  final List<MerchantProductRow> topProducts;

  /// The same stretch one period earlier, when the backend sends it. Null
  /// means no comparison is drawn rather than one invented.
  final num? previousRevenue;
}

/// One month of what a store owes Saba: one rate on what it delivered,
/// less the cash it handed back on returns.
@immutable
class SabaBill {
  const SabaBill({
    required this.month,
    this.orderCount = 0,
    this.sales = 0,
    this.returned = 0,
    this.owed = 0,
    this.isDue = false,
    this.paidAt,
  });

  /// The first day of the month.
  final DateTime month;
  final int orderCount;
  final num sales;
  final num returned;
  final num owed;

  /// A past month not yet paid. This month is still adding up.
  final bool isDue;

  /// When Saba marked it paid; null until then.
  final DateTime? paidAt;
}

/// A store owner's request to delete their account (Apple 5.1.1(v), Google
/// Play: closing alone is not enough). The store is closed from the moment
/// it is asked; the account is deleted once none of these is left.
@immutable
class StoreDeletion {
  const StoreDeletion({
    required this.currencyCode,
    this.requestedAt,
    this.openOrders = 0,
    this.openReturns = 0,
    this.owed = 0,
    this.returnsOpenUntil,
  });

  final String currencyCode;

  /// When it was asked for; null when it has not been.
  final DateTime? requestedAt;

  /// Orders not yet delivered or called off.
  final int openOrders;

  /// Returns the store has still to settle.
  final int openReturns;

  /// What the store owes Saba: this month so far and every month still due.
  final num owed;

  /// The last day a shopper can ask for a return; null when none can.
  final DateTime? returnsOpenUntil;

  bool get nothingLeft =>
      openOrders == 0 &&
      openReturns == 0 &&
      owed <= 0 &&
      returnsOpenUntil == null;
}

/// This month so far, and the months before it (the server works it out).
@immutable
class SabaBills {
  const SabaBills({
    required this.currencyCode,
    required this.ratePercent,
    required this.current,
    this.past = const <SabaBill>[],
  });

  final String currencyCode;
  final num ratePercent;
  final SabaBill current;
  final List<SabaBill> past;
}

/// One row of the merchant's variant matrix (specification section 10).
///
/// [options] maps an option name to the chosen value, e.g.
/// `{'Color': 'Red', 'Storage': '128GB'}`. The combination is what makes the
/// row unique; the server assigns the real variant id.
@immutable
class ProductVariantDraft {
  const ProductVariantDraft({
    required this.options,
    this.id,
    this.sku,
    this.price,
    this.stock = 0,
    this.stockBefore,
  });

  final Map<String, String> options;
  final String? id;
  final String? sku;

  /// `null` means "inherit the product price".
  final num? price;
  final int stock;

  /// The stock the form showed for an option already saved; null for a new
  /// one. The server changes a stock only when [stock] differs from it, and
  /// refuses when the stock moved meanwhile, so units sold while the form
  /// was open are not put back (the reviewer).
  final int? stockBefore;

  /// Stable key for the option combination, independent of map ordering.
  String get signature {
    final keys = options.keys.toList()..sort();
    return keys.map((k) => '$k=${options[k]}').join('|');
  }

  /// "Red / 128GB" — what the merchant sees on the row.
  String get label => options.values.join(' / ');

  ProductVariantDraft copyWith({String? sku, num? price, int? stock}) =>
      ProductVariantDraft(
        options: options,
        id: id,
        sku: sku ?? this.sku,
        price: price ?? this.price,
        stock: stock ?? this.stock,
        stockBefore: stockBefore,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': ?id,
    'sku': ?sku,
    'price': ?price,
    'stock': stock,
    'stockBefore': ?stockBefore,
    'options': [
      for (final entry in options.entries)
        <String, dynamic>{'name': entry.key, 'value': entry.value},
    ],
  };
}

/// Draft payload for creating or editing a product.
@immutable
class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.nameAr,
    required this.categoryId,
    this.description,
    required this.price,
    this.id,
    this.brandId,
    this.brandName,
    this.clearBrand = false,
    this.sku,
    this.barcode,
    this.originalPrice,
    this.stock = 0,
    this.stockBefore,
    this.lowStockThreshold,
    this.warranty,
    this.returnPolicy,
    this.imageUrls = const <String>[],
    this.variants = const <ProductVariantDraft>[],
  });

  /// In English; optional, so it may be empty.
  final String name;

  /// In Arabic; every product has one.
  final String nameAr;

  /// Null means "leave whatever the product already has".
  ///
  /// The edit screen is handed a [MerchantProductRow], which carries no
  /// description, so it cannot show the current one. Sending an empty string
  /// from that blank field overwrote the real description on every save —
  /// omitting the key instead makes a blank field mean "unchanged".
  final String? description;
  final String categoryId;
  final num price;
  final String? id;

  /// The brand: [brandId] for one picked from the list, [brandName] for a
  /// name typed that is not on it (the server finds it whatever the case,
  /// in either language, or adds one that Saba checks with the product).
  /// Neither keeps the product's own; [clearBrand] takes it off.
  final String? brandId;
  final String? brandName;
  final bool clearBrand;
  final String? sku;
  final String? barcode;
  final num? originalPrice;
  final int stock;

  /// The stock the form showed, for a product saved before; see
  /// [ProductVariantDraft.stockBefore].
  final int? stockBefore;
  final int? lowStockThreshold;
  final String? warranty;
  final String? returnPolicy;

  /// Ordered: the first image is the product's main image.
  final List<String> imageUrls;
  final List<ProductVariantDraft> variants;

  bool get isNew => id == null || id!.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'nameAr': nameAr,
    'description': ?description,
    'categoryId': categoryId,
    'price': price,
    if (clearBrand) 'brandId': null else 'brandId': ?brandId,
    'brandName': ?brandName,
    'sku': ?sku,
    'barcode': ?barcode,
    'originalPrice': ?originalPrice,
    'stock': stock,
    'stockBefore': ?stockBefore,
    'lowStockThreshold': ?lowStockThreshold,
    'warranty': ?warranty,
    'returnPolicy': ?returnPolicy,
    if (imageUrls.isNotEmpty) 'images': imageUrls,
    if (variants.isNotEmpty) 'variants': [for (final v in variants) v.toJson()],
  };
}

/// Where a store's coupon stands today.
enum CouponStatus { active, scheduled, paused, ended, usedUp }

/// A discount code a store made for its own customers (specification
/// sections 27 and 39). It takes money off what is bought from that store
/// only, and the server is what enforces every rule written here.
@immutable
class MerchantCoupon {
  const MerchantCoupon({
    required this.id,
    required this.code,
    required this.isPercentage,
    required this.value,
    required this.startsAt,
    this.endsAt,
    this.minOrderAmount,
    this.usageLimit,
    this.usedCount = 0,
    this.isActive = true,
    this.currencyCode = 'IQD',
  });

  /// Empty for a coupon not saved yet.
  final String id;
  final String code;
  final bool isPercentage;
  final num value;
  final DateTime startsAt;

  /// Null means it runs until the store stops it.
  final DateTime? endsAt;

  /// On what is bought from this store, not the whole cart.
  final num? minOrderAmount;

  /// Null means no limit.
  final int? usageLimit;
  final int usedCount;

  /// False when the store has paused it.
  final bool isActive;
  final String currencyCode;

  CouponStatus statusAt(DateTime now) {
    if (endsAt != null && !now.isBefore(endsAt!)) return CouponStatus.ended;
    if (usageLimit != null && usedCount >= usageLimit!) {
      return CouponStatus.usedUp;
    }
    if (!isActive) return CouponStatus.paused;
    if (now.isBefore(startsAt)) return CouponStatus.scheduled;
    return CouponStatus.active;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'discountType': isPercentage ? 'PERCENTAGE' : 'FIXED',
    'value': value,
    'minOrderAmount': minOrderAmount,
    'startsAt': startsAt.toIso8601String(),
    'endsAt': endsAt?.toIso8601String(),
    'usageLimit': usageLimit,
    'isActive': isActive,
  };
}
