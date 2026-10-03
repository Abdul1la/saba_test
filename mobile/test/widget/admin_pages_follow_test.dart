// Saba's admin pages for brands, categories and Home banners (the backend,
// 2026-10-01): the app follows them with no update of its own. A store types
// or picks a brand, and a typed one waits for Saba's check; a product in a
// category Saba hid keeps it, and one put there is refused on the field;
// Browse reads the categories again on its next reload; a banner opens what
// Saba linked it to.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/product_list_screen.dart';
import 'package:saba_marketplace/features/home/data/home_repository_impl.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _en = AppLocalizations(Locale('en'));

/// The demo server, noting what each save sent.
class _Recording extends MerchantRepositoryImpl {
  _Recording(super.client);

  final sent = <Map<String, dynamic>>[];

  @override
  Future<Result<void>> saveProduct(ProductDraft draft) {
    sent.add(draft.toJson());
    return super.saveProduct(draft);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  final backend = DioFactory.mockBackend;

  setUp(() {
    store.clear();
    backend.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, (call) async {
          final key = call.arguments is Map ? call.arguments['key'] : null;
          switch (call.method) {
            case 'write':
              store[key as String] = call.arguments['value'] as String? ?? '';
            case 'read':
              return store[key as String];
            case 'readAll':
              return Map<String, String>.from(store);
          }
          return null;
        });
  });
  tearDown(backend.resetForTesting);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// The app, signed in as [email]; the store's saves recorded.
  Future<(ProviderContainer, _Recording)> start(
    WidgetTester tester,
    String email,
  ) async {
    tester.view.physicalSize = const Size(411 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final preferences = await AppPreferences.create();
    late _Recording shelf;
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        merchantRepositoryProvider.overrideWith(
          (ref) => shelf = _Recording(ref.watch(apiClientProvider)),
        ),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      (await c
              .read(authControllerProvider.notifier)
              .signIn(email: email, password: 'Password1'))
          .unwrap();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const SabaApp()),
    );
    await settle(tester);
    // Made now, so [shelf] is there even where nothing has saved.
    c.read(merchantRepositoryProvider);
    return (c, shelf);
  }

  /// Nova's phone (p-1: brand Nova, in Smartphones) opened in the edit form.
  Future<void> pushPhone(WidgetTester tester, ProviderContainer c) async {
    late MerchantProductRow row;
    await tester.runAsync(() async {
      row = (await c.read(merchantRepositoryProvider).products())
          .unwrap()
          .items
          .firstWhere((r) => r.id == 'p-1');
    });
    c.read(appRouterProvider).push(AppRoutes.merchantProductForm, extra: row);
    await settle(tester);
  }

  /// The store signed in, its phone open in the edit form.
  Future<(ProviderContainer, _Recording)> openPhone(WidgetTester tester) async {
    final (c, shelf) = await start(tester, 'merchant@saba.app');
    await pushPhone(tester, c);
    return (c, shelf);
  }

  final brandBox = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == _en.brandHint,
  );

  Future<void> save(WidgetTester tester) async {
    final button = find.text('Save changes');
    await tester.ensureVisible(button.last);
    await tester.pump();
    await tester.tap(button.last);
    await settle(tester);
  }

  Future<String?> brandOfPhone(ProviderContainer c, WidgetTester tester) async {
    String? name;
    await tester.runAsync(() async {
      name = (await c.read(merchantRepositoryProvider).product('p-1'))
          .unwrap()
          .brand
          ?.name;
    });
    return name;
  }

  group('the brand box', () {
    testWidgets('a brand picked from the list is saved by its id', (
      tester,
    ) async {
      final (c, shelf) = await openPhone(tester);
      expect(
        tester.widget<TextField>(brandBox).controller!.text,
        'Nova',
        reason: 'the box does not show the brand the product has',
      );

      await tester.ensureVisible(brandBox);
      await tester.enterText(brandBox, 'lum');
      await settle(tester);
      await tester.tap(find.text('Lumen').last);
      await settle(tester);
      await save(tester);

      expect(shelf.sent.last['brandId'], 'b-lumen');
      expect(shelf.sent.last.containsKey('brandName'), isFalse);
      expect(await brandOfPhone(c, tester), 'Lumen');
    });

    testWidgets('a name not on the list is sent as typed, and waits for '
        "Saba's check", (tester) async {
      final (c, shelf) = await openPhone(tester);
      await tester.ensureVisible(brandBox);
      await tester.enterText(brandBox, 'Zeta Audio');
      await settle(tester);
      await save(tester);

      expect(shelf.sent.last['brandName'], 'Zeta Audio');
      expect(shelf.sent.last.containsKey('brandId'), isFalse);
      expect(await brandOfPhone(c, tester), 'Zeta Audio');
      // The store's own list has it; the shop's does not, until Saba checks.
      late List<String> own;
      late List<String> shop;
      await tester.runAsync(() async {
        own = [
          for (final b in (await c.read(merchantRepositoryProvider).brands())
              .unwrap())
            b.name,
        ];
        final client = c.read(apiClientProvider);
        shop = [
          for (final b
              in (await client.get<List<dynamic>>(
                '/brands',
                decoder: (envelope) => envelope.dataAsList,
              )).unwrap())
            '${(b as Map)['name']}',
        ];
      });
      expect(own, contains('Zeta Audio'));
      expect(shop, isNot(contains('Zeta Audio')));
    });

    testWidgets('a box left alone keeps the brand; an emptied one takes it '
        'off', (tester) async {
      final (c, shelf) = await openPhone(tester);
      await save(tester);
      expect(shelf.sent.last.containsKey('brandId'), isFalse);
      expect(shelf.sent.last.containsKey('brandName'), isFalse);
      expect(await brandOfPhone(c, tester), 'Nova');

      final (c2, shelf2) = await openPhone(tester);
      await tester.ensureVisible(brandBox);
      await tester.enterText(brandBox, '');
      await settle(tester);
      await save(tester);
      expect(shelf2.sent.last.containsKey('brandId'), isTrue);
      expect(shelf2.sent.last['brandId'], isNull);
      expect(await brandOfPhone(c2, tester), isNull);
    });
  });

  group('categories Saba hid', () {
    testWidgets('a product already in one keeps it, and says which', (
      tester,
    ) async {
      backend.hiddenCategories.add('c-phones');
      final (_, shelf) = await openPhone(tester);
      expect(find.text('Smartphones'), findsOneWidget);
      expect(find.text(_en.selectCategory), findsNothing);
      await save(tester);
      expect(shelf.sent.last['categoryId'], 'c-smartphones');
      expect(find.textContaining('hidden'), findsNothing, reason: 'refused');
    });

    testWidgets('one hidden after the form opened is refused on the field', (
      tester,
    ) async {
      final (_, shelf) = await openPhone(tester);
      backend.hiddenCategories.add('c-home');
      await tester.ensureVisible(find.text('Smartphones'));
      await tester.tap(find.text('Smartphones'));
      await settle(tester);
      await tester.tap(find.text('Home appliances').last);
      await settle(tester);
      await save(tester);

      expect(shelf.sent.last['categoryId'], 'c-home');
      expect(
        find.text('Saba has hidden this category. Choose another one.'),
        findsOneWidget,
      );
    });

    testWidgets('the form reads them again when it opens', (tester) async {
      final (c, _) = await openPhone(tester);
      c.read(appRouterProvider).pop();
      await settle(tester);
      backend.hiddenCategories.add('c-home');
      await pushPhone(tester, c);

      await tester.ensureVisible(find.text('Smartphones'));
      await tester.tap(find.text('Smartphones'));
      await settle(tester);
      expect(find.text('Home appliances'), findsNothing);
    });
  });

  testWidgets('Browse reads the categories again when the app comes back', (
    tester,
  ) async {
    final (c, _) = await start(tester, 'shopper@saba.app');
    c.read(appRouterProvider).go(AppRoutes.categories);
    await settle(tester);
    // The strip's first chip after All: the rest are built as it scrolls.
    expect(find.text('Phones'), findsOneWidget);

    backend.hiddenCategories.add('c-phones');
    // Away and back, through every state between, as a phone goes.
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await settle(tester);
    expect(find.text('Phones'), findsNothing);
  });

  group('Home banners', () {
    test('a banner reads its link, and may have no words', () {
      final linked = HomeMappers.banner(const {
        'id': '7',
        'imageUrl': null,
        'title': null,
        'subtitle': null,
        'link': {'type': 'STORE', 'id': '3'},
      });
      expect((linked.action?.type, linked.action?.value), ('STORE', '3'));
      expect((linked.title, linked.subtitle), (null, null));
      expect(HomeMappers.banner(const {'id': '8', 'link': null}).action, isNull);
    });

    testWidgets('a linked banner opens what it links to; one without a link '
        'is a picture', (tester) async {
      final (c, _) = await start(tester, 'shopper@saba.app');
      c.read(appRouterProvider).go(AppRoutes.home);
      await settle(tester);
      // A push leaves the router's location as it was, so the screen says.
      Finder category(String id) => find.byWidgetPredicate(
        (widget) =>
            widget is ProductListScreen &&
            widget.initialQuery.categoryId == id,
      );

      await tester.tap(find.text('Mid-season sale'));
      await settle(tester);
      expect(find.byType(ProductListScreen), findsNothing);
      expect(find.text('Mid-season sale'), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(PageView).first, const Offset(-600, 0));
        await settle(tester);
      }
      await tester.tap(find.text('Home and kitchen'));
      await settle(tester);
      expect(category('c-home'), findsOneWidget);
    });
  });
}
