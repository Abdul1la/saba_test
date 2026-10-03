import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/widgets/app_text_field.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/otp_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/phone_entry_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/register_customer_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/register_merchant_screen.dart';
import 'package:saba_marketplace/core/widgets/saba_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The way in, in order:
///
///   splash -> language (first launch) -> role -> phone -> code -> sign-up
///
/// Walked end to end rather than screen by screen, because every one of these
/// steps has worked on its own before while the chain between them did not:
/// the language screen existed and nothing routed to it, the role screen did
/// not exist and "Create account" jumped straight to the buyer form.
/// The platform keystore has no implementation in a test binding, and the
/// session check reads it on boot.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<ProviderContainer> boot({required bool returning}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (returning) 'saba.pref.onboarding_seen': true,
    });
    final preferences = await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget harness(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          routerConfig: ref.watch(appRouterProvider),
          locale: const Locale('en'),
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
  }

  /// pumpAndSettle cannot be used past the code screen: its resend countdown
  /// is a periodic timer, and settling waits for a timer that never stops.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  String where(ProviderContainer container) => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;

  /// Walks splash -> language -> role and stops on the role screen.
  /// Past the language, to the shopper's number step: the role screen is no
  /// longer on the way in.
  Future<void> toNumberStep(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(harness(c));
    await settle(tester);
    await tester.tap(find.text('English'));
    await settle(tester);
    // Sign-in comes first; a new person goes on from its link.
    await tester.ensureVisible(find.text('Create an account'));
    await tester.pump();
    await tester.tap(find.text('Create an account'));
    await settle(tester);
  }

  /// The demo backend prints the code on screen because it sends no SMS.
  /// Reading it back is also the assertion that the printed code is the one
  /// that actually works — a demo hint that lies is worse than none.
  String demoCodeOnScreen(WidgetTester tester) {
    final label = tester
        .widget<Text>(find.textContaining('Your code is'))
        .data!;
    return RegExp(r'(\d{6})').firstMatch(label)!.group(1)!;
  }

  testWidgets('a first launch is asked for a language before anything else', (
    tester,
  ) async {
    final container = await boot(returning: false);
    await tester.pumpWidget(harness(container));
    await settle(tester);

    expect(where(container), AppRoutes.language);

    // Both scripts on every option: a reader who cannot read the other
    // language still recognises their own word.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('الإنجليزية'), findsOneWidget);
    expect(find.text('Arabic'), findsOneWidget);
  });

  // The user: a first launch went straight into sign-up, and someone who
  // already had an account had to find their way out of it.
  testWidgets('choosing a language leads to sign-in, then the number step', (
    tester,
  ) async {
    final container = await boot(returning: false);
    await tester.pumpWidget(harness(container));
    await settle(tester);
    await tester.tap(find.text('English'));
    await settle(tester);
    expect(where(container), AppRoutes.login, reason: 'sign-up came first');
    // "Create an account" under the sign-in button.
    final signIn = tester.getRect(find.widgetWithText(FilledButton, 'Sign in'));
    final create = tester.getRect(find.text('Create an account'));
    expect(create.top, greaterThan(signIn.bottom));

    await tester.ensureVisible(find.text('Create an account'));
    await tester.pump();
    await tester.tap(find.text('Create an account'));
    await settle(tester);

    expect(find.byType(PhoneEntryScreen), findsOneWidget);
    expect(
      tester.widget<PhoneEntryScreen>(find.byType(PhoneEntryScreen)).isMerchant,
      isFalse,
      reason: 'shopping is the default',
    );
    // No drivers: in v1 stores deliver their own orders (BUGS.md 39).
    expect(find.textContaining('Driver'), findsNothing);
    // A returning user is never walled in by a screen meant for new ones.
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('a store is one tap from the shopper number step', (
    tester,
  ) async {
    final container = await boot(returning: false);
    await toNumberStep(tester, container);

    await tester.tap(find.text('Open a store on Saba'));
    await settle(tester);
    expect(
      tester
          .widget<PhoneEntryScreen>(find.byType(PhoneEntryScreen).last)
          .isMerchant,
      isTrue,
    );
    // The store's own number step does not offer to open a store again.
    expect(find.text('Open a store on Saba'), findsNothing);
  });

  testWidgets('a verified number opens the form it was started from', (
    tester,
  ) async {
    final container = await boot(returning: false);
    await toNumberStep(tester, container);

    await tester.enterText(find.byType(TextFormField).first, '7509876543');
    await tester.tap(find.text('Send code'));
    await settle(tester);

    expect(find.byType(OtpScreen), findsOneWidget);
    // International, not the local 07xx form, and shown the one way every
    // number is.
    expect(find.textContaining('+964 750 987 6543'), findsWidgets);

    await tester.enterText(
      find.byType(TextFormField).first,
      demoCodeOnScreen(tester),
    );
    await settle(tester);

    expect(find.byType(RegisterCustomerScreen), findsOneWidget);
    // The number carried over and is not asked for again, so an account can
    // never end up attached to a number nobody verified.
    expect(find.text('+9647509876543'), findsOneWidget);
    expect(find.text('Number verified'), findsOneWidget);

    // No email: the verified number is the way in.
    expect(find.textContaining('Email'), findsNothing);

    // A name stops at 50 letters, pasted or typed.
    final name = find.descendant(
      of: find.widgetWithText(AppTextField, 'Full name'),
      matching: find.byType(TextField),
    );
    await tester.enterText(name, 'A' * 140);
    await settle(tester);
    expect(tester.widget<TextField>(name).controller!.text, 'A' * 50);

    // Eight characters are enough: no upper case, lower case or digit rule,
    // which an Arabic keyboard could not easily give.
    final password = find.descendant(
      of: find.widgetWithText(AppTextField, 'Password'),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(password, 'كلمةسرطويلة');
    await settle(tester);
    expect(
      tester
          .widget<InputDecorator>(
            find.descendant(
              of: password,
              matching: find.byType(InputDecorator),
            ),
          )
          .decoration
          .errorText,
      isNull,
    );
  });

  testWidgets('the number step has the logo and no SMS note', (tester) async {
    final container = await boot(returning: false);
    await toNumberStep(tester, container);
    expect(find.byType(SabaLogo), findsOneWidget);
    expect(find.textContaining('SMS rates'), findsNothing);
  });

  // A number that already has an account is told so on the number step,
  // with the way to sign in, and no code is sent to sign up over it.
  testWidgets('a number with an account says so and offers sign in', (
    tester,
  ) async {
    final container = await boot(returning: false);
    await toNumberStep(tester, container);

    await tester.enterText(find.byType(TextFormField).first, '7701234567');
    await tester.tap(find.text('Send code'));
    await settle(tester);

    expect(find.byType(OtpScreen), findsNothing);
    expect(find.text('This number already has an account.'), findsOneWidget);
    await tester.tap(find.text('Sign in instead'));
    await settle(tester);
    expect(
      container
          .read(appRouterProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path,
      AppRoutes.login,
    );
    // With the number already in the field, not to be typed again.
    expect(find.text('7701234567'), findsOneWidget);
  });

  testWidgets('the merchant route ends on the merchant form', (tester) async {
    final container = await boot(returning: false);
    await toNumberStep(tester, container);
    await tester.tap(find.text('Open a store on Saba'));
    await settle(tester);

    await tester.enterText(find.byType(TextFormField).first, '7809876543');
    await tester.tap(find.text('Send code'));
    await settle(tester);

    await tester.enterText(
      find.byType(TextFormField).first,
      demoCodeOnScreen(tester),
    );
    await settle(tester);

    expect(find.byType(RegisterMerchantScreen), findsOneWidget);
  });

  testWidgets('a wrong code is refused and says so on the field', (
    tester,
  ) async {
    final container = await boot(returning: false);
    await toNumberStep(tester, container);

    await tester.enterText(find.byType(TextFormField).first, '7509876543');
    await tester.tap(find.text('Send code'));
    await settle(tester);

    final wrong = demoCodeOnScreen(tester) == '000000' ? '111111' : '000000';
    await tester.enterText(find.byType(TextFormField).first, wrong);
    await settle(tester);

    expect(find.byType(OtpScreen), findsOneWidget);
    expect(find.byType(RegisterCustomerScreen), findsNothing);
    expect(find.textContaining('not right'), findsOneWidget);
    // Cleared for the next try, with the focus still on the boxes.
    TextField field() => tester.widget<TextField>(find.byType(TextField).first);
    expect(field().controller!.text, isEmpty);
    expect(field().focusNode!.hasFocus, isTrue, reason: 'the boxes lost focus');

    // The right code typed a digit at a time, as a thumb does: every digit
    // lands, the focus stays, and the sixth goes through. A tester saw the
    // screen stop after "580" once, while this file was being edited.
    final code = demoCodeOnScreen(tester);
    for (var typed = 1; typed < code.length; typed++) {
      await tester.enterText(
        find.byType(TextField).first,
        code.substring(0, typed),
      );
      await tester.pump();
      expect(field().controller!.text, code.substring(0, typed));
      expect(field().focusNode!.hasFocus, isTrue);
    }
    await tester.enterText(find.byType(TextField).first, code);
    await settle(tester);
    expect(find.byType(RegisterCustomerScreen), findsOneWidget);
  });

  testWidgets('a returning launch is not asked again', (tester) async {
    final container = await boot(returning: true);
    await tester.pumpWidget(harness(container));
    await settle(tester);

    expect(where(container), isNot(AppRoutes.language));
  });

  // The user: the logo was centred over words at the start edge, which
  // looked unfinished, and "Send code" sat against the phone field.
  testWidgets('the logo lines up with the title; Send code has room', (
    tester,
  ) async {
    final container = await boot(returning: false);
    await tester.pumpWidget(harness(container));
    await settle(tester);
    await tester.tap(find.text('English'));
    await settle(tester);

    // Sign-in, then the number step: the logo starts where the title does.
    for (final title in ['Welcome to Saba', "What's your number?"]) {
      expect(
        tester.getTopLeft(find.byType(SabaLogo)).dx,
        tester.getTopLeft(find.text(title)).dx,
        reason: title,
      );
      if (title == 'Welcome to Saba') {
        await tester.ensureVisible(find.text('Create an account'));
        await tester.pump();
        await tester.tap(find.text('Create an account'));
        await settle(tester);
      }
    }
    final field = tester.getRect(find.byType(TextFormField).first);
    final send = tester.getRect(find.widgetWithText(FilledButton, 'Send code'));
    expect(send.top - field.bottom, greaterThanOrEqualTo(40));
  });

  // From the backend session: Resend asked for a code without saying it was
  // for sign-up, so a number that already has an account - refused on the
  // first send - got a code on the second.
  testWidgets('a resent code is still refused for a number with an account', (
    tester,
  ) async {
    final container = await boot(returning: true);
    await tester.pumpWidget(harness(container));
    await settle(tester);
    // The demo shopper's number, on the code step as if it had got through.
    container
        .read(appRouterProvider)
        .go(
          AppRoutes.registerOtpPath(merchant: false, phone: '+9647701234567'),
        );
    await settle(tester);
    expect(find.byType(OtpScreen), findsOneWidget);

    // Past the countdown, Resend.
    for (var i = 0; i < 62; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.tap(find.text('Resend code'));
    await settle(tester);

    expect(
      find.text('A new code is on its way.'),
      findsNothing,
      reason: 'a code was sent to a number that already has an account',
    );
    expect(find.byType(SnackBar), findsOneWidget, reason: 'refused silently');
  });
}
