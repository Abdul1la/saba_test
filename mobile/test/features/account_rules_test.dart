// The rules an account is made under, held by the server as well as the
// forms (BUGS.md, the auth walk): a 140-letter name was accepted and
// squashed unreadably on Home.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_store_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};

  setUp(() {
    DioFactory.mockBackend.resetForTesting();
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final key = call.arguments is Map ? call.arguments['key'] : null;
          switch (call.method) {
            case 'write':
              store[key as String] = call.arguments['value'] as String? ?? '';
            case 'read':
              return store[key as String];
            case 'delete':
              store.remove(key as String);
            case 'readAll':
              return Map<String, String>.from(store);
            case 'deleteAll':
              store.clear();
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    DioFactory.mockBackend.resetForTesting();
  });

  Future<ProviderContainer> signedOut() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    return c;
  }

  String? fieldError(Result<Object?> result, String field) => result.fold(
    ok: (_) => null,
    err: (Failure failure) => failure.messageForField(field),
  );

  test('a person is at most 50 letters, a store 40', () async {
    final c = await signedOut();
    final auth = c.read(authControllerProvider.notifier);

    final tooLong = await auth.registerCustomer(
      CustomerRegistration(
        fullName: 'A' * 51,
        password: 'Demo1234',
        phone: '+9647509990011',
      ),
    );
    expect(fieldError(tooLong, 'fullName'), isNotNull);

    final store = await auth.registerMerchant(
      MerchantRegistration(
        fullName: 'Ali Kareem',
        password: 'Demo1234',
        phone: '+9647509990012',
        storeName: 'S' * 41,
        businessType: 'INDIVIDUAL',
        governorate: 'BAGHDAD',
      ),
    );
    expect(fieldError(store, 'storeName'), isNotNull);

    // Fifty is fine, and so is the profile until it goes over.
    (await auth.registerCustomer(
      CustomerRegistration(
        fullName: 'A' * 50,
        password: 'Demo1234',
        phone: '+9647509990013',
      ),
    )).unwrap();
    expect(
      fieldError(await auth.updateProfile(fullName: 'B' * 51), 'fullName'),
      isNotNull,
    );

    // A store renamed past 40 in its settings.
    (await auth.signIn(
      email: 'merchant@saba.app',
      password: 'Password1',
    )).unwrap();
    final renamed = await c
        .read(apiClientProvider)
        .put<Map<String, dynamic>>(
          ApiEndpoints.merchantStoreSettings,
          data: <String, dynamic>{'storeName': 'N' * 41},
          decoder: (envelope) => envelope.dataAsMap,
        );
    expect(fieldError(renamed, 'storeName'), isNotNull);
  });

  // Refused in the same city only: shop names repeat across Iraq.
  test('a store name is taken only in its own city', () async {
    final c = await signedOut();
    final auth = c.read(authControllerProvider.notifier);

    Future<Result<Object?>> openStore(String name, String city, String phone) =>
        auth.registerMerchant(
          MerchantRegistration(
            fullName: 'Ali Kareem',
            password: 'Demo1234',
            phone: phone,
            storeName: name,
            businessType: 'INDIVIDUAL',
            governorate: city,
          ),
        );

    // Nova Electronics is in Baghdad: case and spaces do not make it new,
    // and the answer is word for word the one the exact name gets.
    final exact = fieldError(
      await openStore('Nova Electronics', 'BAGHDAD', '+9647509990021'),
      'storeName',
    );
    expect(exact, isNotNull);
    for (final typed in ['  nova   ELECTRONICS ', 'nova electronics ']) {
      expect(
        fieldError(
          await openStore(typed, 'BAGHDAD', '+9647509990021'),
          'storeName',
        ),
        exact,
        reason: '"$typed" is not refused the way "Nova Electronics" is',
      );
    }
    // In Basra it is another shop.
    (await openStore('Nova Electronics', 'BASRA', '+9647509990022')).unwrap();

    // Atlas Home, in Basra, cannot rename itself to it now; Nova keeping its
    // own name is not a clash with itself.
    (await auth.signIn(
      email: 'merchant2@saba.app',
      password: 'Password1',
    )).unwrap();
    Future<Result<Map<String, dynamic>>> rename(String name) => c
        .read(apiClientProvider)
        .put<Map<String, dynamic>>(
          ApiEndpoints.merchantStoreSettings,
          data: <String, dynamic>{'storeName': name},
          decoder: (envelope) => envelope.dataAsMap,
        );
    expect(
      fieldError(await rename('Nova Electronics'), 'storeName'),
      isNotNull,
    );
    (await auth.signIn(
      email: 'merchant@saba.app',
      password: 'Password1',
    )).unwrap();
    expect((await rename('Nova Electronics')).isOk, isTrue);
  });

  // Store sign-up no longer asks for the business address: store settings
  // holds it, and gives it back.
  test('store settings keep the business address', () async {
    final c = await signedOut();
    (await c
            .read(authControllerProvider.notifier)
            .signIn(email: 'merchant@saba.app', password: 'Password1'))
        .unwrap();
    (await c
            .read(apiClientProvider)
            .command(
              ApiEndpoints.merchantStoreSettings,
              method: 'PUT',
              data: <String, dynamic>{
                'storeName': 'Nova Electronics',
                'businessAddress': 'Karrada, Street 10',
              },
            ))
        .unwrap();
    final settings = await c.read(storeSettingsProvider.future);
    expect(settings.businessAddress, 'Karrada, Street 10');
  });
}
