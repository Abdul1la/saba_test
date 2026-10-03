import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/location/store_delivery.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/utils/validators.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';

/// Each store delivers itself, so each says where it goes and what it asks:
/// one fee and time in its own city, one for the others. Checkout prices a
/// store's part by the address's city, and stops an order a store cannot
/// bring - through the real pipeline down to the demo backend.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _en = AppLocalizations(Locale('en'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keys = <String, String>{};
  late AppPreferences preferences;

  setUp(() async {
    DioFactory.mockBackend.resetForTesting();
    keys.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await AppPreferences.create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'write':
              keys[call.arguments['key'] as String] =
                  call.arguments['value'] as String? ?? '';
              return null;
            case 'read':
              return keys[call.arguments['key'] as String];
            case 'delete':
              keys.remove(call.arguments['key'] as String);
              return null;
            case 'readAll':
              return Map<String, String>.from(keys);
            case 'deleteAll':
              keys.clear();
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<ProviderContainer> signedIn(String email) async {
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    (await container
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1'))
        .unwrap();
    return container;
  }

  /// A cheap in-stock product with no options, from [merchantId].
  String productOf(String merchantId) =>
      MockData.products.firstWhere(
            (product) =>
                (product['merchant'] as Map)['id'] == merchantId &&
                product['variants'] == null &&
                product['stockStatus'] != 'OUT_OF_STOCK' &&
                (product['price'] as num) <= 300000,
          )['id']
          as String;

  /// A second address for the signed-in shopper, in [city]; its id.
  Future<String> addressIn(ProviderContainer container, String city) async =>
      ((await container
                  .read(apiClientProvider)
                  .post<Map<String, dynamic>>(
                    ApiEndpoints.addresses,
                    data: <String, dynamic>{
                      'fullName': 'Amina Saleh',
                      'phone': '+9647701234567',
                      'governorate': city,
                      'area': 'Ainkawa',
                      'landmark': 'Next to Ainkawa Mall',
                    },
                    decoder: (envelope) => envelope.dataAsMap,
                  ))
              .unwrap())['id']
          as String;

  test(
    "each store's part is priced by the address's city, or stopped",
    () async {
      final container = await signedIn('shopper@saba.app');
      final client = container.read(apiClientProvider);
      final checkout = container.read(checkoutRepositoryProvider);
      Future<CheckoutSummary> reviewFor(String addressId) async =>
          (await checkout.review(
            CheckoutSelection(addressId: addressId),
          )).unwrap();
      CheckoutGroup partOf(CheckoutSummary summary, String store) =>
          summary.groups.singleWhere((group) => group.merchantId == store);

      await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': productOf('m-1')},
      );
      await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': productOf('m-2')},
      );
      final erbil = await addressIn(container, 'ERBIL');

      // Home in Baghdad: Nova is in town, Atlas comes up from Basra.
      final baghdad = await reviewFor('addr-1');
      expect(partOf(baghdad, 'm-1').shippingFee, 3000);
      expect(partOf(baghdad, 'm-1').estimatedDelivery, '1–2 days');
      expect(partOf(baghdad, 'm-2').shippingFee, 5000);
      expect(partOf(baghdad, 'm-2').estimatedDelivery, '2–3 days');
      expect(baghdad.canPlaceOrder, isTrue);
      // And what each driver collects, and the total, carry those fees.
      expect(
        baghdad.shipping,
        3000 + 5000,
        reason: "the total does not carry the stores' own fees",
      );
      expect(
        partOf(baghdad, 'm-1').amountDue,
        partOf(baghdad, 'm-1').subtotal + 3000,
      );

      // To Erbil: Nova's other-city fee; Atlas does not go there at all.
      final toErbil = await reviewFor(erbil);
      expect(
        partOf(toErbil, 'm-1').shippingFee,
        6000,
        reason: "Nova's fee for another city was not used",
      );
      expect(partOf(toErbil, 'm-2').deliversHere, isFalse);
      expect(toErbil.canPlaceOrder, isFalse, reason: 'Atlas was let through');
      // Said on Atlas's own row, not in the box with the cash limit
      // (BUGS.md 17).
      expect(
        partOf(toErbil, 'm-2').estimatedDelivery,
        "Doesn't deliver to Erbil",
      );
      expect(toErbil.warnings, isEmpty);
      expect(
        (await checkout.placeOrder(
          selection: CheckoutSelection(
            addressId: erbil,
            paymentMethodId: 'pm-cod',
          ),
          idempotencyKey: 'to-erbil',
        )).isOk,
        isFalse,
        reason: 'the server took an order a store cannot deliver',
      );

      // Placed to Baghdad, Nova's order card says where the customer is.
      (await checkout.placeOrder(
        selection: const CheckoutSelection(
          addressId: 'addr-1',
          paymentMethodId: 'pm-cod',
        ),
        idempotencyKey: 'to-baghdad',
      )).unwrap();
      (await container
              .read(authControllerProvider.notifier)
              .signIn(email: 'merchant@saba.app', password: 'Password1'))
          .unwrap();
      final row =
          (await container
                  .read(merchantRepositoryProvider)
                  .orders(status: 'PENDING'))
              .unwrap()
              .items
              .first;
      expect(row.customerGovernorate, Governorate.baghdad);
    },
  );

  test('a store says where it delivers, and checkouts follow it', () async {
    final container = await signedIn(MockData.secondMerchantEmail);
    final client = container.read(apiClientProvider);

    Future<Map<String, dynamic>> settings() async =>
        (await client.get<Map<String, dynamic>>(
          ApiEndpoints.merchantStoreSettings,
          decoder: (envelope) => envelope.dataAsMap,
        )).unwrap();
    Future<bool> save(Map<String, dynamic> delivery) async =>
        (await client.command(
          ApiEndpoints.merchantStoreSettings,
          method: 'PUT',
          data: <String, dynamic>{
            'storeName': 'Atlas Home',
            'governorate': 'BASRA',
            'delivery': delivery,
          },
        )).isOk;

    final saved = StoreDelivery.fromJson((await settings())['delivery'])!;
    expect(saved.deliversTo(Governorate.basra), isTrue);
    expect(saved.deliversTo(Governorate.erbil), isFalse);

    // Money a driver cannot take in cash, and other cities with no fee.
    expect(
      await save(<String, dynamic>{
        'governorates': ['BASRA'],
        'feeInside': 2100,
        'timeInside': 'SAME_DAY',
      }),
      isFalse,
      reason: 'a fee cash cannot pay was saved',
    );
    expect(
      await save(<String, dynamic>{
        'governorates': ['BASRA', 'ERBIL'],
        'feeInside': 2000,
        'timeInside': 'SAME_DAY',
      }),
      isFalse,
      reason: 'other cities were saved with no fee or time',
    );

    // Now Atlas goes to Erbil too - its own Basra kept, though not sent.
    expect(
      await save(<String, dynamic>{
        'governorates': ['ERBIL'],
        'feeInside': 2000,
        'timeInside': 'SAME_DAY',
        'feeOutside': 7000,
        'timeOutside': '3_5_DAYS',
      }),
      isTrue,
    );
    final now = StoreDelivery.fromJson((await settings())['delivery'])!;
    expect(now.governorates, {Governorate.basra, Governorate.erbil});

    // The shopper's product page and checkout both follow it.
    (await container
            .read(authControllerProvider.notifier)
            .signIn(email: 'shopper@saba.app', password: 'Password1'))
        .unwrap();
    final product =
        (await container
                .read(catalogRepositoryProvider)
                .fetchProduct(productOf('m-2')))
            .unwrap();
    expect(product.merchant?.delivery?.deliversTo(Governorate.erbil), isTrue);

    await client.command(
      ApiEndpoints.cartItems,
      data: <String, dynamic>{'productId': productOf('m-2')},
    );
    final summary =
        (await container
                .read(checkoutRepositoryProvider)
                .review(
                  CheckoutSelection(
                    addressId: await addressIn(container, 'ERBIL'),
                  ),
                ))
            .unwrap();
    expect(summary.groups.single.deliversHere, isTrue);
    expect(summary.groups.single.shippingFee, 7000);
  });

  test('a delivery fee is 0 for free, or in steps of 250 IQD', () {
    expect(Validators.cashFee('0', _en), isNull, reason: 'free was refused');
    expect(Validators.cashFee('2000', _en), isNull);
    expect(Validators.cashFee('2100', _en), _en.iqdSteps);
    expect(Validators.cashFee('', _en), _en.validationRequired);
  });
}
