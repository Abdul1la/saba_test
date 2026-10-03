import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';

/// The whole frontend, end to end, with nothing stubbed above the platform.
///
/// `SabaApp` is mounted exactly as `main()` mounts it, so this exercises the
/// real router, the real repositories, the real Dio stack, the real demo-mode
/// interceptor and the real mappers. Only the two platform channels that have
/// no implementation in a test binding are faked.
///
/// This is the check for the reported "tapping Sign in does nothing" bug.

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};
  var writeThrows = false;
  late AppPreferences preferences;

  setUp(() async {
    store.clear();
    writeThrows = false;
    SharedPreferences.setMockInitialValues(<String, Object>{
      // A returning user. Without this the first-launch language gate sends
      // every one of these tests to the language screen, which is the gate
      // working - but not what these tests are about.
      'saba.pref.onboarding_seen': true,
    });
    preferences = await AppPreferences.create();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (call) async {
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
        .setMockMethodCallHandler(_keystore, null);
  });

  /// Home and the merchant dashboard run shimmers and a flash-sale countdown
  /// that never go idle, so `pumpAndSettle` would time out. Pump a bounded
  /// number of frames instead, long enough to cover the mock's 350ms latency.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<ProviderContainer> launch(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );
    await settle(tester);
    return container;
  }

  Future<void> signIn(WidgetTester tester, String phone) async {
    final fields = find.byType(TextFormField);
    expect(
      fields,
      findsNWidgets(2),
      reason: 'the sign-in form must be showing',
    );
    await tester.enterText(fields.at(0), phone);
    await tester.enterText(fields.at(1), 'Password1');
    await tester.pump();

    final button = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await settle(tester);
  }

  String where(ProviderContainer c) =>
      c.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path;

  testWidgets('the app boots out of the splash screen', (tester) async {
    final container = await launch(tester);
    expect(
      where(container),
      isNot(AppRoutes.splash),
      reason: 'the splash must resolve once the session is known',
    );
  });

  testWidgets('tapping Sign in navigates a customer to home', (tester) async {
    final container = await launch(tester);

    container.read(appRouterProvider).go(AppRoutes.login);
    await settle(tester);
    expect(where(container), AppRoutes.login);

    await signIn(tester, '7701234567');

    expect(
      where(container),
      AppRoutes.home,
      reason: 'signing in must leave the sign-in screen',
    );
  });

  testWidgets('tapping Sign in navigates a merchant to their dashboard', (
    tester,
  ) async {
    final container = await launch(tester);

    container.read(appRouterProvider).go(AppRoutes.login);
    await settle(tester);

    await signIn(tester, '7711234567');

    expect(where(container), AppRoutes.merchantDashboard);
  });

  // The in-app admin is gone (Q12, BUGS 145): the web is Saba's admin, and
  // an admin signing in here is told so and signed back out.
  testWidgets("Saba's own staff are sent to the web panel", (tester) async {
    final container = await launch(tester);

    container.read(appRouterProvider).go(AppRoutes.login);
    await settle(tester);

    await signIn(tester, '7709999999');

    expect(where(container), AppRoutes.login);
    expect(container.read(isAuthenticatedProvider), isFalse);
    expect(
      find.text("Saba's staff sign in on the web panel, not in the app."),
      findsOneWidget,
    );
  });

  testWidgets('sign-in still navigates when the keystore refuses to write', (
    tester,
  ) async {
    writeThrows = true;
    final container = await launch(tester);

    container.read(appRouterProvider).go(AppRoutes.login);
    await settle(tester);

    await signIn(tester, '7701234567');

    // This is the regression: the keystore write happens after the credentials
    // are accepted. Before the guard in TokenStorage.save it threw, the loading
    // flag was never cleared, and the button span forever on /login.
    expect(
      where(container),
      AppRoutes.home,
      reason: 'a keystore failure must not strand the user on sign-in',
    );
  });
}
