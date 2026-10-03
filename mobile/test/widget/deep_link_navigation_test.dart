import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/constants/app_constants.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';

/// Phase 6 — G15, through the real router.
///
/// `deep_links_test.dart` covers the parsing. This covers the part that was
/// actually broken: the redirect parks every location on the splash screen
/// while the session is still resolving, and a deep link always arrives during
/// exactly that window. Before `PendingDeepLink` the destination — and the
/// token in it — was replaced by the home screen and silently lost.
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};
  late AppPreferences preferences;

  setUp(() async {
    DioFactory.mockBackend.resetForTesting();
    store.clear();
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

  Uri location(ProviderContainer c) =>
      c.read(appRouterProvider).routerDelegate.currentConfiguration.uri;

  testWidgets('a link lands on the right screen with its query', (
    tester,
  ) async {
    final container = await launch(tester);
    expect(
      location(container).path,
      AppRoutes.home,
      reason: 'precondition: the app started normally',
    );

    container.read(appRouterProvider).go('/search?q=abc123');
    await settle(tester);

    expect(location(container).path, AppRoutes.search);
    expect(location(container).queryParameters['q'], 'abc123');
  });

  testWidgets('a link opened during the splash window is not lost', (
    tester,
  ) async {
    // THE regression. A stored token makes AuthController call the backend to
    // restore the session, so the app genuinely sits in its loading state for
    // the mock's round trip - exactly the window a cold start from an email
    // arrives in. Without a stored token the restore finishes immediately and
    // this test proves nothing.
    store[StorageKeys.accessToken] = 'demo-access-token';
    store[StorageKeys.refreshToken] = 'demo-refresh-token';

    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );
    await tester.pump();

    expect(
      container.read(authControllerProvider).isLoading,
      isTrue,
      reason: 'precondition: the session must still be resolving',
    );
    expect(location(container).path, AppRoutes.splash);

    container.read(appRouterProvider).go('/search?q=from-link');
    await settle(tester);

    expect(
      location(container).path,
      AppRoutes.search,
      reason: 'the splash must hand the destination back, not swallow it',
    );
    expect(location(container).queryParameters['q'], 'from-link');
  });

  // BUGS.md 84 and 100: a removed or unknown address said "You do not
  // have permission to do that" on a screen with no way back.
  testWidgets('a removed or unknown address lands on Home', (tester) async {
    final container = await launch(tester);
    // Signed out, an address the app does not know asks for sign-in first,
    // as any unlisted one does; signed in, it goes Home.
    await tester.runAsync(
      () => container
          .read(authControllerProvider.notifier)
          .signIn(email: 'demo@saba.app', password: 'Password1'),
    );
    await settle(tester);
    // The email check, too: Saba sends no email, and its screen called a
    // server route there is not.
    for (final gone in [
      '/compare',
      '/account/sessions',
      '/browse',
      '/verify-email?token=abc123',
    ]) {
      container.read(appRouterProvider).go(gone);
      await settle(tester);
      expect(location(container).path, AppRoutes.home, reason: gone);
    }
  });

  testWidgets('a deep link to a protected screen still asks for sign-in', (
    tester,
  ) async {
    // Access control is not bypassed by arriving via a link.
    final container = await launch(tester);
    container.read(appRouterProvider).go(AppRoutes.addresses);
    await settle(tester);

    expect(location(container).path, AppRoutes.login);
  });

  testWidgets('the pending link is consumed, not replayed', (tester) async {
    final container = await launch(tester);
    container.read(appRouterProvider).go('/search?q=abc123');
    await settle(tester);

    container.read(appRouterProvider).go(AppRoutes.home);
    await settle(tester);

    expect(
      location(container).path,
      AppRoutes.home,
      reason: 'a stale link must not hijack a later navigation',
    );
  });
}
