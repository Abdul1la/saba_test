import 'package:flutter/foundation.dart';

/// A shipping choice offered for one merchant's part of the order.
@immutable
class ShippingOption {
  const ShippingOption({
    required this.id,
    required this.name,
    required this.fee,
    required this.currencyCode,
    this.merchantId,
    this.description,
    this.estimatedDelivery,
  });

  final String id;
  final String name;
  final num fee;
  final String currencyCode;

  /// Null when the option applies to the whole order rather than one store.
  final String? merchantId;

  final String? description;
  final String? estimatedDelivery;

  bool get isFree => fee <= 0;
}

/// Payment instruments the backend is willing to accept for this order.
///
/// The app never holds card data. A card payment hands off to the provider's
/// own flow and the backend verifies the result (specification section 14).
enum PaymentMethodType {
  card,
  wallet,
  cashOnDelivery,
  bankTransfer,
  unknown;

  static PaymentMethodType fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'CARD' || 'CREDIT_CARD' || 'DEBIT_CARD' => PaymentMethodType.card,
        'WALLET' || 'DIGITAL_WALLET' => PaymentMethodType.wallet,
        'COD' || 'CASH_ON_DELIVERY' => PaymentMethodType.cashOnDelivery,
        'BANK_TRANSFER' || 'BANK' => PaymentMethodType.bankTransfer,
        _ => PaymentMethodType.unknown,
      };
}

@immutable
class PaymentMethodOption {
  const PaymentMethodOption({
    required this.id,
    required this.type,
    required this.label,
    this.description,
    this.isEnabled = true,
    this.disabledReason,
  });

  final String id;
  final PaymentMethodType type;
  final String label;
  final String? description;
  final bool isEnabled;

  /// Why the backend disabled it, for example "not available for this address".
  final String? disabledReason;
}

/// One line of the order, as the server priced it.
@immutable
class CheckoutLine {
  const CheckoutLine({
    required this.name,
    required this.quantity,
    this.variantLabel,
  });

  final String name;
  final int quantity;
  final String? variantLabel;
}

/// "Buy now": this one product, checked out on its own, the cart untouched.
@immutable
class BuyNowLine {
  const BuyNowLine({
    required this.productId,
    this.variantId,
    this.quantity = 1,
  });

  final String productId;
  final String? variantId;
  final int quantity;
}

/// One merchant's portion of the order being reviewed.
@immutable
class CheckoutGroup {
  const CheckoutGroup({
    required this.merchantId,
    required this.merchantName,
    required this.itemCount,
    required this.subtotal,
    required this.currencyCode,
    this.shippingOptions = const <ShippingOption>[],
    this.selectedShippingOptionId,
    this.shippingFee,
    this.estimatedDelivery,
    this.lines = const <CheckoutLine>[],
    this.discount = 0,
    this.amountDue,
    this.deliversHere = true,
  });

  final String merchantId;
  final String merchantName;
  final int itemCount;

  /// What is being bought from this store.
  final List<CheckoutLine> lines;
  final num subtotal;
  final String currencyCode;
  final List<ShippingOption> shippingOptions;
  final String? selectedShippingOptionId;
  final num? shippingFee;
  final String? estimatedDelivery;

  /// What this store's coupon takes off its own things.
  final num discount;

  /// What this store's driver collects at the door, as the server priced
  /// it: each store sends its own driver, and each is paid separately.
  final num? amountDue;

  /// False when the store does not deliver to the chosen address's city;
  /// the order cannot go until its items are out or the address changes.
  final bool deliversHere;
}

/// The authoritative money summary for the order about to be placed.
///
/// Recalculated by the server on every review call. The app displays it and
/// never derives its own total (specification section 13).
@immutable
class CheckoutSummary {
  const CheckoutSummary({
    required this.groups,
    required this.subtotal,
    required this.shipping,
    required this.tax,
    required this.discount,
    required this.total,
    required this.currencyCode,
    this.paymentMethods = const <PaymentMethodOption>[],
    this.couponCode,
    this.warnings = const <String>[],
    this.canPlaceOrder = true,
  });

  final List<CheckoutGroup> groups;
  final num subtotal;
  final num shipping;
  final num tax;
  final num discount;
  final num total;
  final String currencyCode;
  final List<PaymentMethodOption> paymentMethods;
  final String? couponCode;

  /// Server-side notices such as a price change since the cart was filled.
  final List<String> warnings;

  /// False when the server would refuse this order as it stands - over a
  /// new shopper's first-order limit - and [warnings] says why.
  final bool canPlaceOrder;

  int get itemCount =>
      groups.fold(0, (total, group) => total + group.itemCount);
}

/// What the backend returns after a successful checkout.
@immutable
class PlacedOrder {
  const PlacedOrder({required this.orderId, required this.orderNumber});

  final String orderId;
  final String orderNumber;
}

/// The customer's selections, sent to the server for pricing and placement.
///
/// Note what is absent: no prices, no totals, no merchant ids the client
/// invented. Only references the server can validate (specification section 20).
@immutable
class CheckoutSelection {
  const CheckoutSelection({
    this.addressId,
    this.shippingOptionIds = const <String, String>{},
    this.paymentMethodId,
    this.deliveryInstructions,
    this.buyNow,
  });

  final String? addressId;

  /// Set for "Buy now": the order is this line alone, not the cart.
  final BuyNowLine? buyNow;

  /// Merchant id to chosen shipping option id.
  final Map<String, String> shippingOptionIds;

  final String? paymentMethodId;
  final String? deliveryInstructions;

  bool get hasAddress => addressId != null && addressId!.isNotEmpty;
  bool get hasPaymentMethod =>
      paymentMethodId != null && paymentMethodId!.isNotEmpty;

  CheckoutSelection copyWith({
    String? addressId,
    Map<String, String>? shippingOptionIds,
    String? paymentMethodId,
    String? deliveryInstructions,
  }) {
    return CheckoutSelection(
      addressId: addressId ?? this.addressId,
      shippingOptionIds: shippingOptionIds ?? this.shippingOptionIds,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      deliveryInstructions: deliveryInstructions ?? this.deliveryInstructions,
      buyNow: buyNow,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'addressId': ?addressId,
    'paymentMethodId': ?paymentMethodId,
    'deliveryInstructions': ?deliveryInstructions,
    'shipping': [
      for (final entry in shippingOptionIds.entries)
        <String, dynamic>{
          'merchantId': entry.key,
          'shippingOptionId': entry.value,
        },
    ],
    if (buyNow case final line?)
      'items': [
        <String, dynamic>{
          'productId': line.productId,
          'variantId': ?line.variantId,
          'quantity': line.quantity,
        },
      ],
  };
}
