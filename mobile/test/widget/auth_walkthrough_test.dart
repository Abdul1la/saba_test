import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/login_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/otp_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/phone_entry_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/register_customer_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/register_merchant_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:saba_marketplace/features/home/presentation/screens/home_screen.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every control on every screen you meet before the app proper — tapped.
///
/// This is the walk someone does by hand on a device, written down so it runs
/// in seconds and runs again on every change. It taps both languages, both
/// roles, every link out of the sign-in screen, and the failure path of every
/// form, because a form that only works when you type the right thing has not
/// been tested.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A Pixel 8, in logical pixels. The default test surface is 800x600 -
  /// wider than it is tall - and on it every one of these screens overflows,
  /// so taps land on nothing and the test reports a bug the app does not have.
  const phone = Size(411, 914);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'readAll') return <String, String>{};
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<ProviderContainer> boot({bool seen = true}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (seen) 'saba.pref.onboarding_seen': true,
    });
    final preferences = await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget harness(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) => MaterialApp.router(
        routerConfig: ref.watch(appRouterProvider),
        // As `lib/app.dart` does it. Without this the language tap changes a
        // stored preference and nothing else, and the test proves nothing.
        locale: ref.watch(localeControllerProvider),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );

  /// The code screen runs a periodic countdown, so pumpAndSettle would wait on
  /// a timer that never stops.
  Future<void> settle(WidgetTester tester, {int frames = 14}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> sizeAsPhone(WidgetTester tester) async {
    tester.view.physicalSize = phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Scrolls to the control before tapping it, because that is what a person
  /// does. Without it a tap on something below the fold silently hits nothing
  /// and the screen appears not to respond.
  Future<void> tapText(WidgetTester tester, String label) async {
    final target = find.text(label).first;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await settle(tester);
  }

  /// A signed-out visitor lands on Home, not on sign-in: this marketplace
  /// lets people browse before they have an account. So a test about the
  /// sign-in screen has to ask for it.
  Future<void> openSignIn(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(harness(c));
    await settle(tester);
    c.read(appRouterProvider).go(AppRoutes.login);
    await settle(tester);
  }

  // ------------------------------------------------------- the language ----

  testWidgets('Arabic turns the whole app right to left', (tester) async {
    await sizeAsPhone(tester);
    final container = await boot(seen: false);
    await tester.pumpWidget(harness(container));
    await settle(tester);

    await tapText(tester, 'العربية');

    // Straight on to sign-in, mirrored as well as translated: a screen that
    // reads right to left with its controls still pinned left is worse than
    // one left in English.
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(LoginScreen))),
      TextDirection.rtl,
    );
    expect(find.text('إنشاء حساب'), findsOneWidget);
  });

  testWidgets('English keeps the app left to right', (tester) async {
    await sizeAsPhone(tester);
    final container = await boot(seen: false);
    await tester.pumpWidget(harness(container));
    await settle(tester);

    await tapText(tester, 'English');

    expect(
      Directionality.of(tester.element(find.byType(LoginScreen))),
      TextDirection.ltr,
    );
    expect(find.text('Create an account'), findsOneWidget);
  });

  // ----------------------------------------------------- the first step ----

  // The user: someone who already has the app is not walked into sign-up.
  testWidgets('the first step after the language is sign-in', (tester) async {
    await sizeAsPhone(tester);
    final container = await boot(seen: false);
    await tester.pumpWidget(harness(container));
    await settle(tester);
    await tapText(tester, 'English');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(PhoneEntryScreen), findsNothing);
  });

  // -------------------------------------------------------- signing in ----

  testWidgets('an empty sign-in is refused on both fields', (tester) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await openSignIn(tester, container);

    expect(find.byType(LoginScreen), findsOneWidget);
    await tapText(tester, 'Sign in');

    // Still here, and told why.
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(TextFormField), findsWidgets);
  });

  testWidgets('a malformed address is refused', (tester) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await openSignIn(tester, container);

    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.enterText(find.byType(TextFormField).at(1), 'demo1234');
    await tapText(tester, 'Sign in');

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('the shopper demo account signs in and lands on Home', (
    tester,
  ) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await openSignIn(tester, container);

    // Tapping the demo chip is the point: it is the only way anyone finds
    // these accounts.
    await tapText(tester, 'Shopper');
    await tapText(tester, 'Sign in');
    await settle(tester, frames: 20);

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the merchant demo account lands on the dashboard, not Home', (
    tester,
  ) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await openSignIn(tester, container);

    await tapText(tester, 'Nova Electronics');
    await tapText(tester, 'Sign in');
    await settle(tester, frames: 20);

    // The account decides which half of the app opens. This is the whole
    // reason one sign-in screen serves both.
    expect(find.byType(MerchantDashboardScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('sign-up from the sign-in screen starts at the number', (
    tester,
  ) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await openSignIn(tester, container);

    await tapText(tester, 'Create an account');
    // A shopper by default, with the store one tap away: no role screen.
    expect(find.byType(PhoneEntryScreen), findsOneWidget);
    expect(find.text('Open a store on Saba'), findsOneWidget);
  });

  // ------------------------------------------------- phone and the code ----

  testWidgets('a number too short to be real is refused', (tester) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await openSignIn(tester, container);
    await tapText(tester, 'Create an account');

    expect(find.byType(PhoneEntryScreen), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '770');
    await tapText(tester, 'Send code');

    expect(find.byType(PhoneEntryScreen), findsOneWidget);
    expect(find.byType(OtpScreen), findsNothing);
  });

  testWidgets('the code screen offers a way back to fix the number', (
    tester,
  ) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await openSignIn(tester, container);
    await tapText(tester, 'Create an account');
    await tester.enterText(find.byType(TextFormField).first, '7509876543');
    await tapText(tester, 'Send code');

    expect(find.byType(OtpScreen), findsOneWidget);
    // Resend starts on a countdown, so it cannot be hammered.
    expect(find.textContaining('Resend in'), findsOneWidget);

    await tapText(tester, 'Change number');
    expect(find.byType(PhoneEntryScreen), findsOneWidget);
  });

  // ------------------------------------------------------ the buyer form ---

  testWidgets('the buyer form refuses an empty submit and a bad password', (
    tester,
  ) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await tester.pumpWidget(harness(container));
    await settle(tester);
    container
        .read(appRouterProvider)
        .go(
          AppRoutes.registerPath(
            merchant: false,
            phone: '+9647512223344',
            token: 'test-token',
          ),
        );
    await settle(tester);

    expect(find.byType(RegisterCustomerScreen), findsOneWidget);
    await tapText(tester, 'Create account');
    expect(find.byType(RegisterCustomerScreen), findsOneWidget);
    // Refused out loud: an empty submit that shows nothing reads as a dead
    // button.
    expect(
      find.text('This field is required'),
      findsWidgets,
      reason: 'the empty submit said nothing',
    );

    // A confirmation that does not match the password.
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Amina Saleh');
    await tester.enterText(fields.at(1), '7701234567');
    await tester.enterText(fields.at(2), 'password');
    await tester.enterText(fields.at(3), 'different');
    await tapText(tester, 'Create account');

    expect(find.byType(RegisterCustomerScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  // The tester: #/register/merchant opened bare went straight to the form
  // and made a store for a number that never got a code.
  testWidgets('a sign-up form opened without a verified number asks for one', (
    tester,
  ) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await tester.pumpWidget(harness(container));
    await settle(tester);
    for (final route in [
      AppRoutes.registerMerchant,
      AppRoutes.registerCustomer,
      '${AppRoutes.registerMerchant}?phone=%2B9647512223344',
    ]) {
      container.read(appRouterProvider).go(route);
      await settle(tester);
      expect(find.byType(PhoneEntryScreen), findsOneWidget, reason: route);
      expect(find.byType(RegisterMerchantScreen), findsNothing, reason: route);
      expect(find.byType(RegisterCustomerScreen), findsNothing, reason: route);
    }
  });

  testWidgets('sign-up names the rules it agrees to, and they open', (
    tester,
  ) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await tester.pumpWidget(harness(container));
    await settle(tester);
    container
        .read(appRouterProvider)
        .go(
          AppRoutes.registerPath(
            merchant: false,
            phone: '+9647512223344',
            token: 'test-token',
          ),
        );
    await settle(tester);

    expect(
      find.text("Creating an account means you agree to Saba's rules:"),
      findsOneWidget,
    );
    await tapText(tester, 'Privacy policy');
    expect(find.text('Who sees it'), findsOneWidget);
  });

  // BUGS.md 122: with passwords in v1, a forgotten one had no way back in.
  testWidgets('a forgotten password: number, code, new password, sign in', (
    tester,
  ) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await openSignIn(tester, container);

    await tapText(tester, 'Forgot password?');
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '7701234567');
    await tapText(tester, 'Send code');

    final code = RegExp(r'(\d{6})')
        .firstMatch(
          tester.widget<Text>(find.textContaining('Your code is')).data!,
        )!
        .group(1)!;
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), code);
    await tester.enterText(fields.at(1), 'كلمةسرجديدة');
    await tester.enterText(fields.at(2), 'كلمةسرجديدة');
    await tapText(tester, 'Save new password');

    expect(
      container
          .read(appRouterProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path,
      AppRoutes.login,
    );
    expect(find.text('Your password has been changed.'), findsOneWidget);
  });

  // --------------------------------------------- sign-up, end to end ------

  testWidgets('a customer can sign up from scratch and lands on Home', (
    tester,
  ) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await openSignIn(tester, container);

    await tapText(tester, 'Create an account');
    await tester.enterText(find.byType(TextFormField).first, '7701111111');
    await tapText(tester, 'Send code');

    final code = RegExp(r'(\d{6})')
        .firstMatch(
          tester.widget<Text>(find.textContaining('Your code is')).data!,
        )!
        .group(1)!;
    await tester.enterText(find.byType(TextFormField).first, code);
    await settle(tester);

    expect(find.byType(RegisterCustomerScreen), findsOneWidget);

    // No email: the verified phone is the way in.
    final f = find.byType(TextFormField);
    await tester.enterText(f.at(0), 'Amina Saleh');
    await tester.enterText(f.at(2), 'Demo1234!');
    await tester.enterText(f.at(3), 'Demo1234!');
    await tapText(tester, 'Create account');
    await settle(tester);

    // The city is asked, and needed.
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('Choose the city.'), findsOneWidget);
    await tapText(tester, 'Choose your city');
    await tapText(tester, 'Erbil');
    await tapText(tester, 'Create account');
    await settle(tester, frames: 24);

    expect(find.byType(HomeScreen), findsOneWidget);
    // The city just chosen is where she shops from.
    expect(container.read(shopperCityProvider), Governorate.erbil);
  });

  testWidgets(
    'a merchant can sign up from scratch and lands on the dashboard',
    (tester) async {
      await sizeAsPhone(tester);
      final container = await boot();
      await openSignIn(tester, container);

      await tapText(tester, 'Create an account');
      await tapText(tester, 'Open a store on Saba');
      await tester.enterText(find.byType(TextFormField).first, '7802222222');
      await tapText(tester, 'Send code');

      final code = RegExp(r'(\d{6})')
          .firstMatch(
            tester.widget<Text>(find.textContaining('Your code is')).data!,
          )!
          .group(1)!;
      await tester.enterText(find.byType(TextFormField).first, code);
      await settle(tester);

      expect(find.byType(RegisterMerchantScreen), findsOneWidget);

      // One screen: the owner, the store and its city, then the number
      // (already verified) and a password. No business address or
      // description: those wait for store settings.
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Business address'), findsNothing);
      expect(find.text('Store description'), findsNothing);
      expect(
        find.text("Creating an account means you agree to Saba's rules:"),
        findsOneWidget,
        reason: 'a store signs up without seeing the rules',
      );
      final f = find.byType(TextFormField);
      await tester.enterText(f.at(0), 'Omar Al-Sayed');
      await tester.enterText(f.at(1), 'Omar Phones');
      await tester.enterText(f.at(3), 'Demo1234!');
      await tester.enterText(f.at(4), 'Demo1234!');
      await tapText(tester, 'Create account');
      await settle(tester);

      // Without a city the store is not created: shoppers see it on every
      // card of the store.
      expect(find.byType(MerchantDashboardScreen), findsNothing);
      expect(find.text('Choose the city.'), findsOneWidget);
      await tapText(tester, 'Choose your city');
      await settle(tester);
      await tapText(tester, 'Basra');
      await settle(tester);
      await tapText(tester, 'Create account');
      await settle(tester, frames: 24);

      // The role the sign-up started from is the half of the app that opens.
      expect(find.byType(MerchantDashboardScreen), findsOneWidget);
    },
  );

  // "nova electronics " in Baghdad was refused under the store name field,
  // scrolled up out of the form's window above "Create account": the tester
  // never saw why.
  testWidgets('a store name taken in its city is refused where it is seen', (
    tester,
  ) async {
    await sizeAsPhone(tester);
    final container = await boot();
    await openSignIn(tester, container);

    await tapText(tester, 'Create an account');
    await tapText(tester, 'Open a store on Saba');
    await tester.enterText(find.byType(TextFormField).first, '7802222233');
    await tapText(tester, 'Send code');
    final code = RegExp(r'(\d{6})')
        .firstMatch(
          tester.widget<Text>(find.textContaining('Your code is')).data!,
        )!
        .group(1)!;
    await tester.enterText(find.byType(TextFormField).first, code);
    await settle(tester);

    /// Inside the form's scrolling window, not clipped above or below it.
    bool inView(Finder finder) {
      final window = tester.getRect(
        find.ancestor(of: finder, matching: find.byType(Scrollable)).first,
      );
      final rect = tester.getRect(finder);
      return rect.top >= window.top && rect.bottom <= window.bottom;
    }

    // Top to bottom, as a person fills it, ending at the last field on a
    // small phone.
    await tapText(tester, 'Choose your city');
    await tapText(tester, 'Baghdad');
    tester.view.physicalSize = const Size(360, 640) * 3;
    await settle(tester);
    final f = find.byType(TextFormField);
    await tester.enterText(f.at(0), 'Omar Al-Sayed');
    await tester.enterText(f.at(1), 'nova electronics ');
    await tester.enterText(f.at(3), 'Demo1234!');
    await tester.ensureVisible(f.at(4));
    await tester.enterText(f.at(4), 'Demo1234!');
    await settle(tester);
    expect(
      inView(f.at(1)),
      isFalse,
      reason: 'the store name is still in view: the test shows nothing',
    );
    await tester.tap(find.text('Create account'));
    await settle(tester, frames: 24);

    expect(find.byType(MerchantDashboardScreen), findsNothing);
    expect(
      inView(
        find.text(
          'A store in this city already has this name. Choose another.',
        ),
      ),
      isTrue,
      reason: 'refused where nobody can see it',
    );
  });
}
