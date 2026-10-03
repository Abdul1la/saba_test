import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';

/// Checkout is one scroll, not a wizard.
///
/// The paged version validated at every "Next". With the whole commitment on
/// one screen, [CheckoutState.canPlaceOrder] is the only client-side gate
/// left, so it is worth pinning: an order placed without an address or a
/// payment method is an order the server will reject and the customer will
/// have to redo.
void main() {
  const summary = CheckoutSummary(
    groups: <CheckoutGroup>[],
    subtotal: 100000,
    shipping: 5000,
    tax: 0,
    discount: 0,
    total: 105000,
    currencyCode: 'IQD',
    paymentMethods: <PaymentMethodOption>[],
  );

  CheckoutState state({
    String? addressId,
    String? paymentMethodId,
    CheckoutSummary? priced = summary,
    bool isPricing = false,
    bool isPlacing = false,
  }) {
    return CheckoutState(
      step: CheckoutStep.address,
      selection: CheckoutSelection(
        addressId: addressId,
        paymentMethodId: paymentMethodId,
      ),
      summary: priced,
      isPricing: isPricing,
      isPlacing: isPlacing,
    );
  }

  test('ready when the address, the payment method and a price are all in', () {
    expect(
      state(addressId: 'a-1', paymentMethodId: 'cod').canPlaceOrder,
      isTrue,
    );
  });

  test('not ready without an address', () {
    expect(state(paymentMethodId: 'cod').canPlaceOrder, isFalse);
  });

  test('not ready without a payment method', () {
    expect(state(addressId: 'a-1').canPlaceOrder, isFalse);
  });

  test('not ready before the server has priced it', () {
    expect(
      state(
        addressId: 'a-1',
        paymentMethodId: 'cod',
        priced: null,
      ).canPlaceOrder,
      isFalse,
      reason: 'the button would show a total nobody has confirmed',
    );
  });

  test('not ready while re-pricing', () {
    // Changing the address re-prices. Tapping during that window would place
    // an order against the old total.
    expect(
      state(
        addressId: 'a-1',
        paymentMethodId: 'cod',
        isPricing: true,
      ).canPlaceOrder,
      isFalse,
    );
  });

  test('not ready while already placing, so it cannot be double-tapped', () {
    expect(
      state(
        addressId: 'a-1',
        paymentMethodId: 'cod',
        isPlacing: true,
      ).canPlaceOrder,
      isFalse,
    );
  });
}
