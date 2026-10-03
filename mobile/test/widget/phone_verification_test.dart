// Saba can switch SMS checks off at sign-up (PHONE_VERIFICATION=off) so it
// pays for no SMS at launch, and the app follows with no release of its own
// (the user's call, relayed by the backend 2026-10-01):
//   - checks off: sign-up gets a token and no code, and skips the code screen;
//   - checks on (the default): the code screen, as before;
//   - a number that signed up while checks were off is asked for a code at its
//     next sign-in once checks are back on (PHONE_NOT_VERIFIED).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/otp_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/register_customer_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/verify_phone_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  final backend = DioFactory.mockBackend;

  setUp(() {
    store.clear();
    backend.resetForTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (call) async {
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
  tearDown(backend.resetForTesting);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<ProviderContainer> makeContainer() async {
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pump(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );
    await settle(tester);
  }

  String where(ProviderContainer c) =>
      c.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path;

  Future<void> enterNumberAndSend(WidgetTester tester, String local) async {
    await tester.enterText(find.byType(TextFormField).first, local);
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'Send code');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await settle(tester);
  }

  group('sign-up follows the mode', () {
    testWidgets('checks off: no code screen, straight to the details form', (
      tester,
    ) async {
      backend.phoneChecks = false;
      final container = await makeContainer();
      await pump(tester, container);
      container
          .read(appRouterProvider)
          .go(AppRoutes.registerPhonePath(merchant: false));
      await settle(tester);

      await enterNumberAndSend(tester, '07705559999');

      expect(find.byType(RegisterCustomerScreen), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing, reason: 'no code was sent');
    });

    testWidgets('checks on: the code screen, as before', (tester) async {
      final container = await makeContainer();
      await pump(tester, container);
      container
          .read(appRouterProvider)
          .go(AppRoutes.registerPhonePath(merchant: false));
      await settle(tester);

      await enterNumberAndSend(tester, '07705559999');

      expect(find.byType(OtpScreen), findsOneWidget);
      expect(find.byType(RegisterCustomerScreen), findsNothing);
    });
  });

  group('verify at next sign-in', () {
    const phone = '+9647705559999';

    // An account that signed up while checks were off, then checks came on.
    Future<ProviderContainer> unverifiedAccount(WidgetTester tester) async {
      backend.phoneChecks = false;
      final container = await makeContainer();
      await tester.runAsync(() async {
        final auth = container.read(authControllerProvider.notifier);
        (await auth.registerCustomer(
          const CustomerRegistration(
            fullName: 'Huda Kareem',
            password: 'Password1',
            phone: phone,
            governorate: 'BAGHDAD',
          ),
        )).unwrap();
        await auth.signOut();
      });
      backend.phoneChecks = true;
      return container;
    }

    Future<void> signIn(WidgetTester tester, String code) async {
      await tester.enterText(find.byType(TextFormField).at(0), '07705559999');
      await tester.enterText(find.byType(TextFormField).at(1), 'Password1');
      await tester.pump();
      final button = find.widgetWithText(FilledButton, 'Sign in');
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await settle(tester);
    }

    String demoCode(WidgetTester tester) {
      final note = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((t) => t.contains('no SMS is sent'));
      return RegExp(r'(\d{6})').firstMatch(note)!.group(1)!;
    }

    testWidgets('a right code lets the unchecked number in', (tester) async {
      final container = await unverifiedAccount(tester);
      await pump(tester, container);
      container.read(appRouterProvider).go(AppRoutes.login);
      await settle(tester);

      await signIn(tester, '');
      expect(
        find.byType(VerifyPhoneScreen),
        findsOneWidget,
        reason: 'the number was never checked',
      );

      final code = demoCode(tester);
      await tester.enterText(find.byType(TextFormField), code);
      await settle(tester);

      expect(find.byType(VerifyPhoneScreen), findsNothing);
      expect(where(container), AppRoutes.home);
    });

    testWidgets('a wrong code is refused, and stays on the screen', (
      tester,
    ) async {
      final container = await unverifiedAccount(tester);
      await pump(tester, container);
      container.read(appRouterProvider).go(AppRoutes.login);
      await settle(tester);

      await signIn(tester, '');
      expect(find.byType(VerifyPhoneScreen), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '000000');
      await settle(tester);

      expect(find.byType(VerifyPhoneScreen), findsOneWidget);
      expect(where(container), isNot(AppRoutes.home));
      expect(find.text('That code is not right.'), findsOneWidget);
    });
  });
}
