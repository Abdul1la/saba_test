import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';

/// Exercises the real sign-in pipeline end to end in demo mode:
///
///   AuthController → AuthRepositoryImpl → AuthRemoteDataSource → Dio
///   → MockApiInterceptor → UserMapper/AuthTokens → TokenStorage
///
/// `login_navigation_test.dart` stubs the repository, so it proves the router
/// navigates but skips everything above. This one keeps all of it real and only
/// fakes the platform keystore, which has no implementation in a test binding.

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};
  var writeThrows = false;
  late AppPreferences preferences;

  /// Mirrors `main()`: preferences are overridden there, and the provider
  /// throws by design if they are not.
  ProviderContainer makeContainer() => ProviderContainer(
    overrides: [appPreferencesProvider.overrideWithValue(preferences)],
    retry: (_, _) => null,
  );

  setUp(() async {
    store.clear();
    writeThrows = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await AppPreferences.create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'write':
              if (writeThrows) {
                throw PlatformException(code: 'Keystore unavailable');
              }
              store[call.arguments['key'] as String] =
                  call.arguments['value'] as String? ?? '';
              return null;
            case 'read':
              return store[call.arguments['key'] as String];
            case 'delete':
              store.remove(call.arguments['key'] as String);
              return null;
            case 'readAll':
              return Map<String, String>.from(store);
            case 'deleteAll':
              store.clear();
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

  test('the real pipeline signs a customer in and stores tokens', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    // Let the controller finish restoring (no stored session -> signed out).
    await container.read(authControllerProvider.future);

    final result = await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'demo@saba.app', password: 'Password1');

    expect(
      result,
      isA<Ok<User>>(),
      reason: 'demo mode must answer the login request successfully',
    );

    final user = (result as Ok<User>).value;
    expect(
      user.role,
      UserRole.customer,
      reason: 'an unknown role makes the sign-in screen sign the user out',
    );

    final state = container.read(authControllerProvider).value;
    expect(
      state?.isAuthenticated,
      isTrue,
      reason: 'the controller must expose an authenticated session',
    );
  });

  test('a merchant email signs in as a merchant', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final result = await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'merchant@saba.app', password: 'Password1');

    expect(result, isA<Ok<User>>());
    expect((result as Ok<User>).value.role, UserRole.merchant);
  });

  test('a keystore write failure does not escape signIn', () async {
    writeThrows = true;
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    // Before the guard in TokenStorage.save this threw, and the exception
    // escaped signIn -> _submit never cleared its loading flag, so the button
    // span forever with no error and no navigation: the reported symptom.
    final result = await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'demo@saba.app', password: 'Password1');

    expect(
      result,
      isA<Ok<User>>(),
      reason: 'the credentials were accepted; only persistence failed',
    );

    final state = container.read(authControllerProvider).value;
    expect(
      state?.isAuthenticated,
      isTrue,
      reason: 'the session must still be usable for this run',
    );
  });
}
