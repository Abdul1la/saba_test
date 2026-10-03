import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/features/auth/domain/auth_repository.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';

/// Signing in must leave the sign-in screen.
///
/// The existing `login_screen_test.dart` mounts `LoginScreen` on its own, so it
/// proves the form calls the repository but can never prove the app navigates
/// afterwards — navigation is the router's job and the router is not in that
/// harness. This test mounts the real router instead.

const _customer = User(
  id: 'u1',
  fullName: 'Amina Saleh',
  email: 'amina@example.com',
  role: UserRole.customer,
  status: AccountStatus.active,
);

const _merchant = User(
  id: 'u2',
  fullName: 'Omar Al-Sayed',
  email: 'merchant@example.com',
  role: UserRole.merchant,
  status: AccountStatus.active,
);

/// Minimal repository double: only what sign-in exercises.
class _StubAuthRepository implements AuthRepository {
  _StubAuthRepository({this.loginResult = const Result<User>.ok(_customer)});

  Result<User> loginResult;

  @override
  Future<Result<User>> login({
    String? email,
    String? phone,
    required String password,
    String? code,
  }) async => loginResult;

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

/// Mounts the real app shell: the real router, with only auth stubbed.
Widget _harness(_StubAuthRepository repository, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) => MaterialApp.router(
        routerConfig: ref.watch(appRouterProvider),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );
}

/// Screens behind the redirect start timers and shimmers that never settle, so
/// `pumpAndSettle` would time out. Pump a bounded number of frames instead.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

Future<void> _signIn(WidgetTester tester, String phone) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), phone);
  await tester.enterText(fields.at(1), 'Password1');
  await tester.pump();

  final button = find.widgetWithText(FilledButton, 'Sign in');
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await _pumpFrames(tester);
}

void main() {
  late ProviderContainer container;
  late AppPreferences preferences;

  setUp(() async {
    // A returning user. The router's first-launch language gate reads this,
    // and these tests are about where sign-in lands, not about onboarding.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
    });
    preferences = await AppPreferences.create();

    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_StubAuthRepository()),
        appPreferencesProvider.overrideWithValue(preferences),
      ],
      retry: (_, _) => null,
    );
  });

  tearDown(() => container.dispose());

  testWidgets('a signed-in customer leaves the sign-in screen', (tester) async {
    await tester.pumpWidget(_harness(_StubAuthRepository(), container));
    await _pumpFrames(tester);

    final router = container.read(appRouterProvider);
    router.go(AppRoutes.login);
    await _pumpFrames(tester);
    expect(
      _location(router),
      AppRoutes.login,
      reason: 'test should start on the sign-in screen',
    );

    await _signIn(tester, '7701234567');

    expect(
      _location(router),
      isNot(AppRoutes.login),
      reason: 'signing in must navigate away from /login',
    );
    expect(_location(router), AppRoutes.home);
  });

  testWidgets('a signed-in merchant lands in the merchant shell', (
    tester,
  ) async {
    final repository = _StubAuthRepository(
      loginResult: const Result<User>.ok(_merchant),
    );
    final merchantContainer = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        appPreferencesProvider.overrideWithValue(preferences),
      ],
      retry: (_, _) => null,
    );
    addTearDown(merchantContainer.dispose);

    await tester.pumpWidget(_harness(repository, merchantContainer));
    await _pumpFrames(tester);

    final router = merchantContainer.read(appRouterProvider);
    router.go(AppRoutes.login);
    await _pumpFrames(tester);

    await _signIn(tester, '7711234567');

    expect(_location(router), AppRoutes.merchantDashboard);
  });
}
