// Fixes the store being read twice. The demo backend kept a store as the demo
// began it and as its owner last saved it; saving wrote the second, almost
// every reply read the first. A new logo reached the store page and nothing
// else, and a store that moved city stayed under its old one on Home.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

  Future<ProviderContainer> signedOut() async {
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    return container;
  }

  test('a store saved once reads the same everywhere', () async {
    final container = await signedOut();
    final auth = container.read(authControllerProvider.notifier);
    final client = container.read(apiClientProvider);
    Future<Map<String, dynamic>> one(String path) async =>
        (await client.get<Map<String, dynamic>>(
          path,
          decoder: (envelope) => envelope.dataAsMap,
        )).unwrap();
    Future<Set<String>> storesIn(String city) async => {
      for (final product in (await client.get<List<dynamic>>(
        ApiEndpoints.products,
        queryParameters: {'governorate': city, 'pageSize': 100},
        decoder: (envelope) => envelope.data as List<dynamic>,
      )).unwrap())
        '${((product as Map)['merchant'] as Map)['id']}',
    };

    // Nova, in Baghdad, saves a new logo and moves to Erbil.
    (await auth.signIn(
      email: 'merchant@saba.app',
      password: 'Password1',
    )).unwrap();
    const logo = 'data:image/png;base64,iVBORw0KGgo=';
    (await client.command(
      ApiEndpoints.merchantStoreSettings,
      method: 'PUT',
      data: <String, dynamic>{
        'storeName': 'Nova Electronics',
        'governorate': 'ERBIL',
        'logoUrl': logo,
      },
    )).unwrap();

    // Store settings open with it, and the store's own header shows it.
    expect((await one(ApiEndpoints.merchantStoreSettings))['logoUrl'], logo);
    await auth.refreshUser();
    expect(
      container.read(authControllerProvider).value!.user!.merchant!.logoUrl,
      logo,
    );

    // A shopper, later: the product page, and Home's city chips.
    (await auth.signIn(
      email: 'shopper@saba.app',
      password: 'Password1',
    )).unwrap();
    final seller = (await one(ApiEndpoints.product('p-1')))['merchant'] as Map;
    expect(seller['id'], 'm-1');
    expect(seller['logoUrl'], logo);
    expect(seller['governorate'], 'ERBIL');
    expect(await storesIn('ERBIL'), contains('m-1'));
    expect(await storesIn('BAGHDAD'), isNot(contains('m-1')));

    // Taking the logo away takes it away.
    (await auth.signIn(
      email: 'merchant@saba.app',
      password: 'Password1',
    )).unwrap();
    (await client.command(
      ApiEndpoints.merchantStoreSettings,
      method: 'PUT',
      data: <String, dynamic>{
        'storeName': 'Nova Electronics',
        'governorate': 'ERBIL',
        'logoUrl': null,
      },
    )).unwrap();
    expect(
      (await one(ApiEndpoints.product('p-1')))['merchant']['logoUrl'],
      isNull,
    );
  });

  // The tester: Nova moved to Basra; the product page said 6,000 IQD to
  // Baghdad and the cart charged 3,000, its old city's fee.
  test(
    'a store that moved charges one fee, on the page and in the cart',
    () async {
      final container = await signedOut();
      final auth = container.read(authControllerProvider.notifier);
      final client = container.read(apiClientProvider);

      (await auth.signIn(
        email: 'merchant@saba.app',
        password: 'Password1',
      )).unwrap();
      (await client.command(
        ApiEndpoints.merchantStoreSettings,
        method: 'PUT',
        data: <String, dynamic>{
          'storeName': 'Nova Electronics',
          'governorate': 'BASRA',
        },
      )).unwrap();

      // Amina, whose address is in Baghdad.
      (await auth.signIn(
        email: 'shopper@saba.app',
        password: 'Password1',
      )).unwrap();
      final plain =
          (await client.get<List<dynamic>>(
            ApiEndpoints.products,
            queryParameters: {'pageSize': 100},
            decoder: (envelope) => envelope.data as List<dynamic>,
          )).unwrap().cast<Map>().firstWhere(
            (p) =>
                (p['merchant'] as Map)['id'] == 'm-1' &&
                p['hasOptions'] != true,
          );
      final product =
          (await container
                  .read(catalogRepositoryProvider)
                  .fetchProduct('${plain['id']}'))
              .unwrap();
      final page = product.merchant!.delivery!.to(
        Governorate.baghdad,
        storeCity: product.merchant!.governorate,
      );
      expect(
        page?.$1,
        6000,
        reason: 'the page did not charge Basra to Baghdad',
      );

      (await client.command(
        ApiEndpoints.cartItems,
        data: <String, dynamic>{'productId': plain['id'], 'quantity': 1},
      )).unwrap();
      final cart = (await client.get<Map<String, dynamic>>(
        ApiEndpoints.cart,
        decoder: (envelope) => envelope.dataAsMap,
      )).unwrap();
      final nova = (cart['groups'] as List).cast<Map>().singleWhere(
        (g) => (g['merchant'] as Map)['id'] == 'm-1',
      );
      expect(nova['shippingFee'], page!.$1, reason: 'the cart charged another');
    },
  );
}
