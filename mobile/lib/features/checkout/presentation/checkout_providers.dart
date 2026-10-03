import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/json_reader.dart';
import '../../addresses/presentation/address_providers.dart';
import '../../cart/presentation/cart_providers.dart';
import '../domain/entities.dart';
import '../../auth/presentation/auth_providers.dart';

abstract interface class CheckoutRepository {
  /// Asks the server to price the current cart against these selections.
  Future<Result<CheckoutSummary>> review(CheckoutSelection selection);

  /// Places the order. [idempotencyKey] makes a retry safe: the backend
  /// returns the original order instead of creating a second one
  /// (specification section 55).
  Future<Result<PlacedOrder>> placeOrder({
    required CheckoutSelection selection,
    required String idempotencyKey,
  });
}

class CheckoutMappers {
  const CheckoutMappers._();

  static CheckoutSummary summary(Map<String, dynamic> json) {
    final totals = Json.objectOrNull(json, const ['totals', 'summary']) ?? json;
    return CheckoutSummary(
      groups: Json.mapList(
        Json.objects(json, const ['groups', 'merchantGroups']),
        group,
      ),
      subtotal: Json.number(totals, const ['subtotal', 'itemsTotal']),
      shipping: Json.number(totals, const ['shipping', 'shippingTotal']),
      tax: Json.number(totals, const ['tax', 'taxTotal']),
      // The coupon is `couponDiscount`; `discount` alone was always 0, so
      // checkout read "429,000 + 8,000 = 403,750" with no coupon line.
      discount:
          Json.number(totals, const ['discount', 'discountTotal']) +
          Json.number(totals, const ['couponDiscount']),
      total: Json.number(totals, const ['total', 'grandTotal']),
      currencyCode: Json.str(totals, const [
        'currencyCode',
        'currency',
      ], fallback: AppConfig.fallbackCurrencyCode),
      paymentMethods: Json.mapList(
        Json.objects(json, const ['paymentMethods', 'availablePaymentMethods']),
        paymentMethod,
      ),
      couponCode: Json.strOrNull(json, const ['couponCode']),
      warnings: Json.strings(json, const ['warnings', 'notices']),
      canPlaceOrder: Json.boolean(json, const [
        'canPlaceOrder',
      ], fallback: true),
    );
  }

  static CheckoutGroup group(Map<String, dynamic> json) => CheckoutGroup(
    merchantId: Json.str(json, const ['merchantId', 'id']),
    merchantName: Json.str(json, const ['merchantName', 'storeName', 'name']),
    itemCount: Json.integer(json, const ['itemCount', 'itemsCount']),
    subtotal: Json.number(json, const ['subtotal', 'itemsTotal']),
    currencyCode: Json.str(json, const [
      'currencyCode',
      'currency',
    ], fallback: AppConfig.fallbackCurrencyCode),
    shippingOptions: Json.mapList(
      Json.objects(json, const ['shippingOptions', 'shippingMethods']),
      shippingOption,
    ),
    selectedShippingOptionId: Json.strOrNull(json, const [
      'selectedShippingOptionId',
      'shippingOptionId',
    ]),
    shippingFee: Json.numberOrNull(json, const ['shippingFee', 'shipping']),
    estimatedDelivery: Json.strOrNull(json, const [
      'estimatedDelivery',
      'deliveryEstimate',
    ]),
    discount: Json.number(json, const ['discount']),
    amountDue: Json.numberOrNull(json, const ['amountDue', 'total']),
    deliversHere: Json.boolean(json, const ['deliversHere'], fallback: true),
    lines: [
      for (final line in Json.objects(json, const ['items', 'lines']))
        CheckoutLine(
          name: Json.str(line, const ['name', 'productName']),
          quantity: Json.integer(line, const ['quantity', 'qty'], fallback: 1),
          variantLabel: Json.strOrNull(line, const ['variantLabel']),
        ),
    ],
  );

  static ShippingOption shippingOption(Map<String, dynamic> json) =>
      ShippingOption(
        id: Json.str(json, const ['id', 'optionId', 'methodId']),
        name: Json.str(json, const ['name', 'label', 'method']),
        fee: Json.number(json, const ['fee', 'price', 'cost']),
        currencyCode: Json.str(json, const [
          'currencyCode',
          'currency',
        ], fallback: AppConfig.fallbackCurrencyCode),
        merchantId: Json.strOrNull(json, const ['merchantId']),
        description: Json.strOrNull(json, const ['description']),
        estimatedDelivery: Json.strOrNull(json, const [
          'estimatedDelivery',
          'deliveryEstimate',
          'eta',
        ]),
      );

  static PaymentMethodOption paymentMethod(Map<String, dynamic> json) =>
      PaymentMethodOption(
        id: Json.str(json, const ['id', 'methodId', 'code']),
        type: PaymentMethodType.fromApi(json['type'] ?? json['method']),
        label: Json.str(json, const ['label', 'name', 'title']),
        description: Json.strOrNull(json, const ['description']),
        isEnabled: Json.boolean(json, const [
          'isEnabled',
          'enabled',
          'available',
        ], fallback: true),
        disabledReason: Json.strOrNull(json, const [
          'disabledReason',
          'reason',
        ]),
      );

  static PlacedOrder placedOrder(Map<String, dynamic> json) {
    final order = Json.objectOrNull(json, const ['order']) ?? json;
    return PlacedOrder(
      orderId: Json.str(order, const ['id', 'orderId']),
      orderNumber: Json.str(order, const [
        'orderNumber',
        'number',
        'reference',
      ]),
    );
  }
}

class CheckoutRepositoryImpl implements CheckoutRepository {
  const CheckoutRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<CheckoutSummary>> review(CheckoutSelection selection) {
    return client.post<CheckoutSummary>(
      ApiEndpoints.checkoutReview,
      data: selection.toJson(),
      decoder: (envelope) => CheckoutMappers.summary(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<PlacedOrder>> placeOrder({
    required CheckoutSelection selection,
    required String idempotencyKey,
  }) {
    return client.post<PlacedOrder>(
      ApiEndpoints.checkoutPlaceOrder,
      data: selection.toJson(),
      idempotencyKey: idempotencyKey,
      decoder: (envelope) => CheckoutMappers.placedOrder(envelope.dataAsMap),
    );
  }
}

final checkoutRepositoryProvider = Provider<CheckoutRepository>((ref) {
  ref.watch(accountIdProvider);
  return CheckoutRepositoryImpl(ref.watch(apiClientProvider));
});

/// Which step of the checkout flow is on screen.
enum CheckoutStep { address, shipping, payment, review }

@immutable
class CheckoutState {
  const CheckoutState({
    required this.step,
    required this.selection,
    this.summary,
    this.isPricing = false,
    this.isPlacing = false,
    this.failure,
    this.placedOrder,
  });

  final CheckoutStep step;
  final CheckoutSelection selection;

  /// The server's pricing for the current selection.
  final CheckoutSummary? summary;

  final bool isPricing;
  final bool isPlacing;
  final Failure? failure;
  final PlacedOrder? placedOrder;

  /// Whether the order can be placed.
  ///
  /// The screen is one scroll rather than a wizard, so this is the only gate
  /// left on the client: without it a customer could tap Place order before
  /// choosing where it goes or how it is paid for. The server validates the
  /// same thing, which is what actually protects the order — this is what
  /// stops the button lying about being ready.
  bool get canPlaceOrder =>
      selection.addressId != null &&
      selection.paymentMethodId != null &&
      summary != null &&
      summary!.canPlaceOrder &&
      !isPricing &&
      !isPlacing;

  CheckoutState copyWith({
    CheckoutStep? step,
    CheckoutSelection? selection,
    CheckoutSummary? summary,
    bool? isPricing,
    bool? isPlacing,
    Failure? failure,
    PlacedOrder? placedOrder,
    bool clearFailure = false,
  }) {
    return CheckoutState(
      step: step ?? this.step,
      selection: selection ?? this.selection,
      summary: summary ?? this.summary,
      isPricing: isPricing ?? this.isPricing,
      isPlacing: isPlacing ?? this.isPlacing,
      failure: clearFailure ? null : (failure ?? this.failure),
      placedOrder: placedOrder ?? this.placedOrder,
    );
  }
}

/// Drives the checkout flow.
///
/// Holds the customer's choices, asks the server to re-price after every change
/// and places the order exactly once thanks to a per-attempt idempotency key.
class CheckoutController extends Notifier<CheckoutState> {
  static const Uuid _uuid = Uuid();

  /// Regenerated only when a new checkout attempt begins, so retrying a failed
  /// or timed-out placement cannot create a duplicate order.
  String _idempotencyKey = _uuid.v4();

  CheckoutRepository get _repository => ref.read(checkoutRepositoryProvider);

  /// The Buy now line this checkout is for, if it is one.
  ///
  /// Kept here and not only in the state, because [build] runs again when
  /// the address list arrives - a moment after the screen opens - and a
  /// fresh state forgot it: Buy now quietly turned back into the cart.
  BuyNowLine? _buyNow;

  @override
  CheckoutState build() {
    ref.watch(accountIdProvider);
    final defaultAddress = ref.watch(defaultAddressProvider);
    return CheckoutState(
      step: defaultAddress == null
          ? CheckoutStep.address
          : CheckoutStep.shipping,
      selection: CheckoutSelection(
        addressId: defaultAddress?.id,
        buyNow: _buyNow,
      ),
    );
  }

  void goTo(CheckoutStep step) => state = state.copyWith(step: step);

  /// A fresh checkout: the cart, or with [buyNow] that one product alone.
  ///
  /// The controller outlives the screen, so without this a "Buy now" would
  /// leave its product behind for the next checkout of the cart - and the
  /// cart's last totals would show for a moment under a Buy now.
  Future<void> begin({BuyNowLine? buyNow}) async {
    _buyNow = buyNow;
    state = CheckoutState(
      step: state.step,
      selection: CheckoutSelection(
        addressId: state.selection.addressId,
        paymentMethodId: state.selection.paymentMethodId,
        buyNow: buyNow,
      ),
    );
    await priceOrder();
  }

  Future<void> selectAddress(String addressId) async {
    state = state.copyWith(
      selection: state.selection.copyWith(addressId: addressId),
      clearFailure: true,
    );
    await priceOrder();
  }

  Future<void> selectShipping({
    required String merchantId,
    required String optionId,
  }) async {
    final updated = <String, String>{
      ...state.selection.shippingOptionIds,
      merchantId: optionId,
    };
    state = state.copyWith(
      selection: state.selection.copyWith(shippingOptionIds: updated),
      clearFailure: true,
    );
    await priceOrder();
  }

  void selectPaymentMethod(String methodId) {
    state = state.copyWith(
      selection: state.selection.copyWith(paymentMethodId: methodId),
      clearFailure: true,
    );
  }

  void setDeliveryInstructions(String? instructions) {
    state = state.copyWith(
      selection: state.selection.copyWith(deliveryInstructions: instructions),
    );
  }

  /// Asks the backend for the authoritative totals.
  Future<void> priceOrder() async {
    if (!state.selection.hasAddress) return;

    state = state.copyWith(isPricing: true, clearFailure: true);
    final result = await _repository.review(state.selection);

    state = result.fold(
      ok: (summary) => state.copyWith(
        summary: summary,
        isPricing: false,
        selection: _withServerDefaults(summary),
      ),
      err: (failure) => state.copyWith(isPricing: false, failure: failure),
    );
  }

  /// Adopts whatever the server defaulted to, so the review step and the
  /// server agree before the order is placed.
  ///
  /// Payment joined shipping here. Nothing chose a method on arrival, so a
  /// first-time customer met "Place order · 2,605,200 IQD" greyed out with
  /// nothing on screen saying why: the button was waiting on a tap it never
  /// asked for. The first method the server lists and allows is the server's
  /// own preference — the same reasoning shipping has always used. It can
  /// still be changed, the chosen row carries the selected border, and the
  /// line under the button always says which one is in force.
  CheckoutSelection _withServerDefaults(CheckoutSummary summary) {
    final selections = <String, String>{...state.selection.shippingOptionIds};
    for (final group in summary.groups) {
      final selected = group.selectedShippingOptionId;
      if (selected != null && !selections.containsKey(group.merchantId)) {
        selections[group.merchantId] = selected;
      }
    }

    var paymentMethodId = state.selection.paymentMethodId;
    if (paymentMethodId == null) {
      final enabled = summary.paymentMethods.where(
        (method) => method.isEnabled,
      );
      if (enabled.isNotEmpty) paymentMethodId = enabled.first.id;
    }

    return state.selection.copyWith(
      shippingOptionIds: selections,
      paymentMethodId: paymentMethodId,
    );
  }

  Future<Result<PlacedOrder>> placeOrder() async {
    state = state.copyWith(isPlacing: true, clearFailure: true);

    final result = await _repository.placeOrder(
      selection: state.selection,
      idempotencyKey: _idempotencyKey,
    );

    state = result.fold(
      ok: (order) => state.copyWith(isPlacing: false, placedOrder: order),
      err: (failure) => state.copyWith(isPlacing: false, failure: failure),
    );

    if (result case Ok<PlacedOrder>()) {
      // The server emptied the cart as part of the same transaction - unless
      // this was Buy now, which never touched it.
      if (state.selection.buyNow == null) {
        ref.read(cartControllerProvider.notifier).clearLocally();
      }
      // A first-order coupon is gone once there is a first order.
      ref.invalidate(availableCouponsProvider);
      _idempotencyKey = _uuid.v4();
    }

    return result;
  }
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);
