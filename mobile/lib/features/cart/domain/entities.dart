import 'package:flutter/foundation.dart';

import '../../catalog/domain/entities.dart';
import '../../../core/location/governorate.dart';

/// One line in the cart.
///
/// Prices are whatever the server says they are. The app never multiplies
/// quantity by price to produce a total it then trusts (section 13).
@immutable
class CartItem {
  const CartItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    required this.currencyCode,
    required this.stockStatus,
    this.variantId,
    this.variantLabel,
    this.imageUrl,
    this.originalUnitPrice,
    this.availableQuantity,
    this.isSavedForLater = false,
  });

  final String id;
  final String productId;
  final String name;
  final num unitPrice;
  final int quantity;

  /// Server-calculated line total, including any line-level discount.
  final num lineTotal;

  final String currencyCode;
  final StockStatus stockStatus;
  final String? variantId;

  /// Human-readable variant summary such as "Black · 256GB".
  final String? variantLabel;

  final String? imageUrl;
  final num? originalUnitPrice;

  /// Stock the server reports right now, used to cap the quantity stepper.
  final int? availableQuantity;

  final bool isSavedForLater;

  bool get isAvailable => stockStatus.isPurchasable;
  bool get isDiscounted =>
      originalUnitPrice != null && originalUnitPrice! > unitPrice;
}

/// Items grouped by the store that sells them (specification section 12).
@immutable
class CartMerchantGroup {
  const CartMerchantGroup({
    required this.merchantId,
    required this.merchantName,
    required this.items,
    required this.subtotal,
    required this.currencyCode,
    this.logoUrl,
    this.governorate,
    this.shippingFee,
    this.shippingMethodName,
    this.freeShippingThreshold,
    this.estimatedDelivery,
    this.deliversHere = true,
  });

  final String merchantId;
  final String merchantName;
  final List<CartItem> items;
  final num subtotal;
  final String currencyCode;
  final String? logoUrl;

  /// Where the store is, which is where each of its lines comes from.
  final Governorate? governorate;
  final num? shippingFee;
  final String? shippingMethodName;
  final num? freeShippingThreshold;
  final String? estimatedDelivery;

  /// False when the store does not bring this part to the address, or is
  /// closed: it is shown, and left out of the total.
  final bool deliversHere;

  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  bool get hasUnavailableItems => items.any((item) => !item.isAvailable);
}

/// The money summary, entirely computed by the backend.
@immutable
class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.total,
    required this.currencyCode,
    this.discount = 0,
    this.shipping = 0,
    this.tax = 0,
    this.couponDiscount = 0,
  });

  const CartTotals.empty()
    : subtotal = 0,
      total = 0,
      currencyCode = '',
      discount = 0,
      shipping = 0,
      tax = 0,
      couponDiscount = 0;

  final num subtotal;
  final num total;
  final String currencyCode;
  final num discount;
  final num shipping;
  final num tax;
  final num couponDiscount;

  bool get hasDiscount => discount > 0 || couponDiscount > 0;
}

@immutable
class AppliedCoupon {
  const AppliedCoupon({
    required this.code,
    required this.discountAmount,
    this.description,
    this.applies = true,
    this.minOrderAmount,
  });

  final String code;
  final num discountAmount;
  final String? description;

  /// On, but taking nothing off: the cart is under [minOrderAmount].
  final bool applies;
  final num? minOrderAmount;
}

/// A coupon this customer can use, offered where they would use it: under
/// the code field in the cart, and on Home.
///
/// Structured rather than a sentence from the server, so the device words it
/// in the reader's language - "10% off" and "خصم 10%" put the amount on
/// different sides.
@immutable
class CouponOffer {
  const CouponOffer({
    required this.code,
    required this.isPercentage,
    required this.value,
    this.currencyCode,
    this.minOrderAmount,
    this.firstOrderOnly = false,
    this.merchantId,
    this.merchantName,
  });

  final String code;

  /// Set for a store's own coupon, which takes money off that store's
  /// items only. Null for one from Saba, good on the whole order.
  final String? merchantId;
  final String? merchantName;

  /// A percentage off the order, or a fixed amount off it.
  final bool isPercentage;
  final num value;
  final String? currencyCode;
  final num? minOrderAmount;
  final bool firstOrderOnly;
}

/// The whole cart as the server sees it.
@immutable
class Cart {
  const Cart({
    required this.id,
    required this.groups,
    required this.totals,
    this.savedForLater = const <CartItem>[],
    this.coupon,
  });

  const Cart.empty()
    : id = '',
      groups = const <CartMerchantGroup>[],
      totals = const CartTotals.empty(),
      savedForLater = const <CartItem>[],
      coupon = null;

  final String id;
  final List<CartMerchantGroup> groups;
  final CartTotals totals;
  final List<CartItem> savedForLater;
  final AppliedCoupon? coupon;

  bool get isEmpty => groups.isEmpty;

  /// Total units across every store, for the bottom-navigation badge.
  int get itemCount =>
      groups.fold(0, (total, group) => total + group.itemCount);

  int get merchantCount => groups.length;

  List<CartItem> get allItems =>
      groups.expand((group) => group.items).toList(growable: false);

  /// Checkout is blocked while any line is out of stock, which mirrors the
  /// check the server performs inside the checkout transaction.
  bool get hasUnavailableItems =>
      groups.any((group) => group.hasUnavailableItems);

  bool get canCheckout => !isEmpty && !hasUnavailableItems;
}
