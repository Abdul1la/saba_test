// The critical and money bugs from BUGS.md, each held down by a check.
//
// 15: the cart total counted a store that cannot deliver to the address.
// 46: a product its store hid, or Saba never approved, was still on sale.
// 65: an unknown product answered with nothing, and the page priced it in $.
// 66: checkout counted lines, so two of one phone read "1 item".
// 47: an option with no original price wore the product's "−20%".
// 25, 27: a cancelled order's invoice still said the money was to come.
// 45: Arabic digits typed into a number field were dropped.
// 20: with +964 in front, the number still started with 0.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/utils/iraqi_phone.dart';
import 'package:saba_marketplace/core/utils/western_digits_formatter.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/widgets/iraqi_phone_field.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/catalog/domain/product_query.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DioFactory.mockBackend.resetForTesting());
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  Future<ProviderContainer> as(String email) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    (await c
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1'))
        .unwrap();
    return c;
  }

  test('15: a store that cannot deliver is left out of the total', () async {
    final c = await as('shopper@saba.app');
    final cart = c.read(cartRepositoryProvider);
    // Nova delivers to Amina's Baghdad; Zakho Mobile does not.
    (await cart.addItem(productId: 'p-11', quantity: 1)).unwrap();
    final priced = (await cart.addItem(
      productId: 'p-16',
      quantity: 1,
    )).unwrap();

    final nova = priced.groups.singleWhere((g) => g.merchantId == 'm-1');
    final zakho = priced.groups.singleWhere((g) => g.merchantId == 'm-3');
    expect(nova.deliversHere, isTrue);
    expect(zakho.deliversHere, isFalse);
    expect(
      priced.totals.total,
      nova.subtotal + nova.shippingFee!,
      reason: 'the total counts what nobody can bring',
    );

    // ...and nobody is told to hand its driver cash.
    final review =
        (await c
                .read(checkoutRepositoryProvider)
                .review(
                  const CheckoutSelection(
                    addressId: 'addr-1',
                    paymentMethodId: 'pm-cod',
                  ),
                ))
            .unwrap();
    final due = {for (final g in review.groups) g.merchantId: g.amountDue};
    expect(due['m-3'], isNull, reason: 'cash to a driver who is not coming');
    expect(due['m-1'], review.total);
  });

  test('46: hidden and unapproved products are not for sale', () async {
    final c = await as('shopper@saba.app');
    final catalog = c.read(catalogRepositoryProvider);
    // Nova's shelf: p-50 waiting, p-42 draft, p-41 rejected, p-51 hidden.
    final shop = (await catalog.fetchProducts(
      query: const ProductQuery(merchantId: 'm-1'),
    )).unwrap().items.map((p) => p.id);
    expect(shop, contains('p-1'));
    for (final id in ['p-50', 'p-42', 'p-41', 'p-51']) {
      expect(shop, isNot(contains(id)), reason: '$id is on sale');
      expect(
        (await catalog.fetchProduct(id)).isErr,
        isTrue,
        reason: '$id opens as a product',
      );
    }
    final search = (await catalog.fetchProducts(
      query: const ProductQuery(search: 'Nova Tab 11'),
    )).unwrap();
    expect(search.items, isEmpty, reason: 'a hidden product is searchable');

    // The store's shelf says the same thing the shop does.
    final store = await as('merchant@saba.app');
    final shelf =
        (await store.read(merchantRepositoryProvider).products(page: 1))
            .unwrap()
            .items;
    expect(shelf.firstWhere((row) => row.id == 'p-51').isActive, isFalse);
    expect(shelf.firstWhere((row) => row.id == 'p-50').status, 'PENDING');
    // ...and its owner can still preview it.
    expect(
      (await store.read(catalogRepositoryProvider).fetchProduct('p-51')).isOk,
      isTrue,
    );
  });

  test('46: a store hides its own product, and shows it again', () async {
    final store = await as('merchant@saba.app');
    final repo = store.read(merchantRepositoryProvider);
    (await repo.setProductShown('p-1', shown: false)).unwrap();
    Future<bool> onShelfShown() async => (await repo.products(
      page: 1,
    )).unwrap().items.firstWhere((row) => row.id == 'p-1').isActive;
    expect(await onShelfShown(), isFalse, reason: 'the store cannot hide it');

    final shopper = await as('shopper@saba.app');
    final catalog = shopper.read(catalogRepositoryProvider);
    expect((await catalog.fetchProduct('p-1')).isErr, isTrue);

    await as('merchant@saba.app');
    (await repo.setProductShown('p-1', shown: true)).unwrap();
    expect(await onShelfShown(), isTrue);
    await as('shopper@saba.app');
    expect((await catalog.fetchProduct('p-1')).isOk, isTrue);
  });

  test('65: an unknown product is not found, not a blank page', () async {
    final c = await as('shopper@saba.app');
    final result = await c.read(catalogRepositoryProvider).fetchProduct('p1');
    expect(result.isErr, isTrue);
    result.fold(
      ok: (_) {},
      err: (failure) => expect(failure, isA<NotFoundFailure>()),
    );
  });

  test('66: checkout counts units, not lines', () async {
    final c = await as('shopper@saba.app');
    (await c
            .read(cartRepositoryProvider)
            .addItem(productId: 'p-11', quantity: 2))
        .unwrap();
    final summary =
        (await c
                .read(checkoutRepositoryProvider)
                .review(
                  const CheckoutSelection(
                    addressId: 'addr-1',
                    paymentMethodId: 'pm-cod',
                  ),
                ))
            .unwrap();
    expect(summary.groups.single.itemCount, 2, reason: 'read "1 item"');
  });

  test("47: an option's discount is its own", () async {
    final c = await as('shopper@saba.app');
    final catalog = c.read(catalogRepositoryProvider);
    final onSale = (await catalog.fetchProduct('p-1')).unwrap();
    for (final option in onSale.variants) {
      expect(option.originalPrice, greaterThan(option.price));
    }
    final notOnSale = (await catalog.fetchProduct('p-2')).unwrap();
    for (final option in notOnSale.variants) {
      expect(
        option.originalPrice,
        isNull,
        reason: 'a discount it does not have',
      );
    }
  });

  test(
    '25, 27: a cancelled order owes nothing, and its invoice says so',
    () async {
      final c = await as('shopper@saba.app');
      final placed =
          (await c
                  .read(checkoutRepositoryProvider)
                  .placeOrder(
                    selection: const CheckoutSelection(
                      addressId: 'addr-1',
                      paymentMethodId: 'pm-cod',
                      buyNow: BuyNowLine(productId: 'p-11'),
                    ),
                    idempotencyKey: 'cancel-me',
                  ))
              .unwrap();
      final orders = c.read(ordersRepositoryProvider);
      final cancelled = (await orders.cancelOrder(
        orderId: placed.orderId,
        reason: 'CHANGED_MIND',
      )).unwrap();
      expect(cancelled.paymentStatus, PaymentStatus.cancelled);
      final invoice = (await orders.fetchInvoice(placed.orderId)).unwrap();
      expect(
        invoice.paymentStatus,
        PaymentStatus.cancelled,
        reason: 'the invoice still said the money was to come',
      );
    },
  );

  test('45: Arabic and Persian digits are digits', () {
    const formatter = WesternDigitsFormatter();
    final typed = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '٠٧٧٠ ۱۲۳'),
    );
    expect(typed.text, '0770 123');
    expect(IraqiPhone.normalize('٠٧٧٠١٢٣٤٥٦٧'), '+9647701234567');
  });

  testWidgets('20 and 45: after +964, no 0, and Arabic digits count', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(body: IraqiPhoneField(controller: controller)),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '07701234567');
    expect(controller.text, '7701234567');
    await tester.enterText(find.byType(TextFormField), '٠٧٧٠١٢٣٤٥٦٧');
    expect(controller.text, '7701234567');
    expect(IraqiPhone.local('+9647701234567'), '7701234567');
  });

  // The tester: "429,000 + 8,000 = Total 403,750" - the coupon was charged
  // and its line was missing.
  test('checkout shows the coupon it takes off', () async {
    final c = await as('shopper@saba.app');
    final client = c.read(apiClientProvider);
    (await client.command(
      '/cart/items',
      data: {'productId': 'p-5', 'quantity': 1},
    )).unwrap();
    (await client.command('/cart/coupon', data: {'code': 'NOVA10'})).unwrap();
    final summary =
        (await c
                .read(checkoutRepositoryProvider)
                .review(
                  const CheckoutSelection(
                    addressId: 'addr-1',
                    paymentMethodId: 'pm-cod',
                  ),
                ))
            .unwrap();
    expect(summary.discount, 14500, reason: 'no coupon line');
    expect(
      summary.subtotal - summary.discount + summary.shipping,
      summary.total,
      reason: 'the lines do not add up to the total',
    );
  });
}
