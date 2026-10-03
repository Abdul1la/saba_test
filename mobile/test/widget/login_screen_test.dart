import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/features/auth/domain/auth_repository.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/login_screen.dart';

const _customer = User(
  id: 'u1',
  fullName: 'Amina Saleh',
  email: 'amina@example.com',
  role: UserRole.customer,
  status: AccountStatus.active,
);

/// Minimal repository double: only what the sign-in screen exercises.
class _StubAuthRepository implements AuthRepository {
  _StubAuthRepository({this.loginResult = const Result<User>.ok(_customer)});

  Result<User> loginResult;
  String? lastEmail;
  String? lastPhone;
  int loginCalls = 0;

  @override
  Future<Result<User>> login({
    String? email,
    String? phone,
    required String password,
    String? code,
  }) async {
    loginCalls++;
    lastEmail = email;
    lastPhone = phone;
    return loginResult;
  }

  @override
  Future<bool> hasStoredSession() async => false;

  @override
  Future<Result<User>> fetchCurrentUser() async =>
      const Result<User>.err(AuthenticationFailure());

  @override
  Future<void> clearSession() async {}

  @override
  Future<Result<void>> logout() async => const Result<void>.ok(null);

  @override
  Future<Result<User>> registerCustomer(CustomerRegistration r) async =>
      const Result<User>.ok(_customer);

  @override
  Future<Result<User>> registerMerchant(MerchantRegistration r) async =>
      const Result<User>.ok(_customer);

  @override
  Future<Result<OtpChallenge>> sendOtp(
    String phone, {
    OtpPurpose purpose = OtpPurpose.other,
  }) async => const Result<OtpChallenge>.ok(OtpChallenge(expiresInSeconds: 60));

  @override
  Future<Result<String>> verifyOtp({
    required String phone,
    required String code,
  }) async => const Result<String>.ok('token');

  @override
  Future<Result<User>> updateProfile({
    String? fullName,
    String? governorate,
  }) async => const Result<User>.ok(_customer);

  @override
  Future<Result<void>> deleteAccount() async => const Result<void>.ok(null);

  @override
  Future<Result<void>> resetPassword({
    required String phone,
    required String code,
    required String password,
  }) async => const Result<void>.ok(null);
}

Widget _harness(_StubAuthRepository repository, {Locale? locale}) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    retry: (_, _) => null,
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LoginScreen(),
    ),
  );
}

/// The submit button sits below the fold in the default test viewport, so it
/// has to be scrolled into view before it can be tapped.
Future<void> _tapSignIn(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Sign in');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the sign-in form', (tester) async {
    await tester.pumpWidget(_harness(_StubAuthRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Saba'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('blocks submission and shows errors for empty fields', (
    tester,
  ) async {
    final repository = _StubAuthRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await _tapSignIn(tester);

    expect(find.text('This field is required'), findsNWidgets(2));
    // Client-side validation is a convenience, but it should still spare the
    // server a request that cannot succeed.
    expect(repository.loginCalls, 0);
  });

  testWidgets('signs in by phone, the default, in full international form', (
    tester,
  ) async {
    final repository = _StubAuthRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '07701234567');
    await tester.enterText(find.byType(TextFormField).last, 'Password1');
    await _tapSignIn(tester);

    expect(repository.loginCalls, 1);
    expect(repository.lastPhone, '+9647701234567');
    expect(repository.lastEmail, isNull);
  });

  testWidgets('refuses a number that is not an Iraqi mobile', (tester) async {
    final repository = _StubAuthRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '0612345678');
    await tester.enterText(find.byType(TextFormField).last, 'Password1');
    await _tapSignIn(tester);

    expect(find.text('Enter a valid phone number'), findsOneWidget);
    expect(repository.loginCalls, 0);
  });

  // By number only: v1 accounts have no email, so there is no way to it.
  testWidgets('there is no email way in', (tester) async {
    await tester.pumpWidget(_harness(_StubAuthRepository()));
    await tester.pumpAndSettle();
    expect(find.text('Use email instead'), findsNothing);
    expect(find.text('Email'), findsNothing);
  });

  testWidgets('shows a server field error on the field it belongs to', (
    tester,
  ) async {
    final repository = _StubAuthRepository(
      loginResult: const Result<User>.err(
        ValidationFailure(
          message: 'Validation failed',
          fieldErrors: [
            FieldError(field: 'phone', message: 'No account uses this number'),
          ],
        ),
      ),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '7701234567');
    await tester.enterText(find.byType(TextFormField).last, 'Password1');
    await _tapSignIn(tester);

    expect(find.text('No account uses this number'), findsOneWidget);
  });

  testWidgets('renders right-to-left in Arabic', (tester) async {
    await tester.pumpWidget(
      _harness(_StubAuthRepository(), locale: const Locale('ar')),
    );
    await tester.pumpAndSettle();

    expect(find.text('أهلاً بك في سبأ'), findsOneWidget);

    final direction = Directionality.of(
      tester.element(find.byType(LoginScreen)),
    );
    expect(direction, TextDirection.rtl);

    // +964 comes before the number, not after it.
    expect(
      tester.getCenter(find.text('+964')).dx,
      lessThan(tester.getCenter(find.byType(TextFormField).first).dx),
      reason: 'the dial code sits after the number in Arabic',
    );
  });

  testWidgets('a demo account fills its number without the 0', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(_StubAuthRepository()));
    await tester.pumpAndSettle();

    // Its whole name at 320 wide: "Nova Elec…".
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Nova Electronics'))
          .didExceedMaxLines,
      isFalse,
    );
    await tester.tap(find.text('Nova Electronics'));
    await tester.pumpAndSettle();
    expect(find.text('7711234567'), findsOneWidget);
    expect(find.text('07711234567'), findsOneWidget, reason: 'the chip');
  });
}
