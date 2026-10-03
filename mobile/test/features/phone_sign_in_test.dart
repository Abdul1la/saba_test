import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';

/// Signing in the way people in Iraq do - by phone - down to the demo
/// backend: an account needs no email, finds its way back by number, and a
/// forgotten password comes back by SMS.
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

  test('each demo account signs in by its phone number', () async {
    final container = await signedOut();
    final auth = container.read(authControllerProvider.notifier);

    final amina = (await auth.signIn(
      phone: '+9647701234567',
      password: 'Password1',
    )).unwrap();
    expect(amina.fullName, 'Amina Saleh');
    expect(amina.role.isMerchant, isFalse);

    final layla = (await auth.signIn(
      phone: '+9647801234567',
      password: 'Password1',
    )).unwrap();
    expect(layla.merchant?.storeName, 'Atlas Home');

    final omar = (await auth.signIn(
      phone: '+9647711234567',
      password: 'Password1',
    )).unwrap();
    expect(omar.merchant?.storeName, 'Nova Electronics');

    final nobody = await auth.signIn(
      phone: '+9647799999999',
      password: 'Password1',
    );
    expect(nobody.isOk, isFalse, reason: 'a number with no account got in');
    expect(nobody.failureOrNull?.fieldErrors.map((e) => e.field), ['phone']);
  });

  test('a shopper signs up with no email, and comes back by phone', () async {
    final container = await signedOut();
    final auth = container.read(authControllerProvider.notifier);

    final made = (await auth.registerCustomer(
      const CustomerRegistration(
        fullName: 'Zainab Ali',
        password: 'Demo1234!',
        phone: '+9647705550000',
        governorate: 'ERBIL',
      ),
    )).unwrap();
    expect(made.email, isEmpty, reason: 'an email was made up for her');
    expect(made.governorate, Governorate.erbil);

    await auth.signOut();
    final back = (await auth.signIn(
      phone: '+9647705550000',
      password: 'Demo1234!',
    )).unwrap();
    expect(back.fullName, 'Zainab Ali', reason: 'signed in as someone else');
    expect(back.governorate, Governorate.erbil);

    // Her city changes on her profile, from the same list.
    final moved = (await auth.updateProfile(governorate: 'BASRA')).unwrap();
    expect(moved.governorate, Governorate.basra);
    await auth.refreshUser();
    expect(
      container.read(currentUserProvider)?.governorate,
      Governorate.basra,
      reason: 'the new city was forgotten',
    );
  });
}
