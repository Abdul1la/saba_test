// The inbox has two kinds of card and used to draw them identically.
//
// A price drop opens the product; a flash-sale announcement opens nothing.
// Both rippled under a finger and only one went anywhere, so the only way to
// find out which was which was to press every one. The chevron and the
// destination are decided by the same function now, so they cannot drift.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/theme/saba_icons.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};

  setUp(() {
    store.clear();
    DioFactory.mockBackend.resetForTesting();
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
    DioFactory.mockBackend.resetForTesting();
  });

  Future<ProviderContainer> pumpInbox(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
    });
    final preferences = await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'demo@saba.app', password: 'Password1');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
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
      ),
    );
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    container.read(appRouterProvider).go(AppRoutes.notifications);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return container;
  }

  /// Whether the card carrying [title] draws the chevron that says it opens
  /// something.
  bool hasChevron(WidgetTester tester, String title) {
    final card = find
        .ancestor(of: find.text(title), matching: find.byType(InkWell))
        .first;
    return find
        .descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SabaIcon &&
                (widget.icon == SabaIcons.chevronRight ||
                    widget.icon == SabaIcons.chevronLeft),
          ),
        )
        .evaluate()
        .isNotEmpty;
  }

  testWidgets('a notification that leads somewhere says so, and goes', (
    tester,
  ) async {
    await pumpInbox(tester);

    // A saved item dropping in price is about a product, and opens it.
    final priceDrop = find.text('A saved item dropped in price');
    expect(priceDrop, findsWidgets);
    expect(hasChevron(tester, 'A saved item dropped in price'), isTrue);

    await tester.tap(priceDrop.first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(ProductDetailScreen), findsOneWidget);
  });

  testWidgets('an announcement is not dressed up as a door', (tester) async {
    await pumpInbox(tester);

    // An announcement with no product behind it is a message. Pressing it
    // still marks it read — that is worth a tap — but it must not promise a
    // screen.
    final promo = find.text('Welcome to Saba');
    expect(promo, findsWidgets);

    expect(hasChevron(tester, 'Welcome to Saba'), isFalse);

    await tester.tap(promo.first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Still in the inbox: nothing was opened.
    expect(find.text('Welcome to Saba'), findsWidgets);
    expect(find.byType(ProductDetailScreen), findsNothing);
  });
}
