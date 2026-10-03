// Home's Filters sheet, each filter checked against the grid it filters, and
// the rail under a product. The user asked whether the filters worked:
// "In stock only" kept a product sold out since the app opened, and a price
// typed as "50,000" was read as no price at all. Related products were any
// six, headphones followed by an air fryer and a laptop.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/utils/formatters.dart';
import 'package:saba_marketplace/core/utils/validators.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart';
import 'package:saba_marketplace/features/catalog/domain/product_query.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/filter_sheet.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/core/providers/paged_state.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _en = AppLocalizations(Locale('en'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DioFactory.mockBackend.resetForTesting());
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  Future<ProviderContainer> as(String email) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    (await c
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1'))
        .unwrap();
    return c;
  }

  /// Every page of the grid for [query].
  Future<List<ProductSummary>> grid(
    ProviderContainer c, [
    ProductQuery query = const ProductQuery(),
  ]) async {
    final found = <ProductSummary>[];
    for (var page = 1; ; page++) {
      final list =
          (await c
                  .read(catalogRepositoryProvider)
                  .fetchProducts(query: query, page: page))
              .unwrap();
      found.addAll(list.items);
      if (!list.hasNextPage) return found;
    }
  }

  Set<String> ids(Iterable<ProductSummary> products) => {
    for (final product in products) product.id,
  };

  test('each filter keeps exactly the products it names', () async {
    final c = await as('shopper@saba.app');
    final all = await grid(c);

    expect(
      ids(await grid(c, const ProductQuery(minPrice: 50000, maxPrice: 200000))),
      ids(all.where((p) => p.price >= 50000 && p.price <= 200000)),
      reason: 'the price range',
    );
    expect(
      ids(await grid(c, const ProductQuery(onSaleOnly: true))),
      ids(all.where((p) => p.originalPrice != null)),
      reason: 'on sale',
    );
    expect(
      ids(await grid(c, const ProductQuery(inStockOnly: true))),
      ids(all.where((p) => p.stockStatus.isPurchasable)),
      reason: 'in stock',
    );
    final brands = (await c.read(catalogRepositoryProvider).fetchBrands())
        .unwrap();
    final nova = brands.firstWhere((brand) => brand.name == 'Nova');
    final novas = await grid(c, ProductQuery(brandIds: [nova.id]));
    expect(novas, isNotEmpty);
    expect(novas.map((p) => p.brandName).toSet(), {'Nova'}, reason: 'brand');
  });

  test('"In stock only" leaves out a product sold out since', () async {
    final store = await as('merchant@saba.app');
    final shelf = store.read(merchantRepositoryProvider);
    final row = (await shelf.inventory()).unwrap().items.firstWhere(
      (row) => row.available > 0 && row.variantLabel == null,
    );
    (await shelf.adjustStock(
      inventoryId: row.id,
      quantity: -row.available,
    )).unwrap();

    final c = await as('shopper@saba.app');
    expect(
      ids(await grid(c, const ProductQuery(inStockOnly: true))),
      isNot(contains(row.productId)),
    );
  });

  test('related products are from the same category, and only it', () async {
    final c = await as('shopper@saba.app');
    final catalog = c.read(catalogRepositoryProvider);
    for (final id in ['p-1', 'p-5', 'p-12']) {
      final category = MockData.products.firstWhere(
        (product) => product['id'] == id,
      )['categoryId'];
      final related = (await catalog.fetchRelatedProducts(id)).unwrap();
      for (final product in related) {
        expect(product.id, isNot(id));
        expect(
          MockData.products.firstWhere(
            (p) => p['id'] == product.id,
          )['categoryId'],
          category,
          reason: '${product.name} under $id',
        );
      }
    }
  });

  testWidgets('a price typed as "50,000" filters by 50,000', (tester) async {
    ProductQuery? applied;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => applied = await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const FilterSheet(query: ProductQuery()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '50,000');
    await tester.enterText(fields.at(1), '200,000');
    await tester.tap(find.text(_en.apply));
    await tester.pumpAndSettle();
    expect(applied?.minPrice, 50000);
    expect(applied?.maxPrice, 200000);
  });

  // The live shop has no brands (the store's form sends none), and the
  // filter still showed "Brands" over nothing. Shown only when there are.
  for (final (label, brands) in [
    ('none', const <Brand>[]),
    ('one', const [Brand(id: 'b-1', name: 'Nova')]),
  ]) {
    testWidgets('the filter shows Brands only when there are some ($label)', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [brandsProvider.overrideWith((ref, _) async => brands)],
          retry: (_, _) => null,
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: FilterSheet(query: ProductQuery())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(_en.brands),
        brands.isEmpty ? findsNothing : findsOneWidget,
      );
      expect(find.text('Nova'), brands.isEmpty ? findsNothing : findsOneWidget);
    });
  }

  // Written the way the examples write them: the product form's own hint
  // said "12,250", and typing it was refused as not a number.
  test('a number typed with commas is read the same everywhere', () {
    expect(Formatters.typedNumber('50,000'), 50000);
    expect(Formatters.typedNumber('٥٠٬٠٠٠'), 50000);
    expect(Formatters.typedNumber('12 250'), 12250);
    expect(Formatters.typedWholeNumber('1,000'), 1000);
    expect(Formatters.typedWholeNumber('2.5'), isNull, reason: 'half a unit');
    expect(Validators.cashPrice('12,250', _en), isNull);
    expect(Validators.cashPrice('12,300', _en), _en.iqdSteps);
    expect(Validators.number('1,000', _en), isNull);
    expect(Validators.cashFee('3,000', _en), isNull);
  });

  // The tester: the last one bought, and Home's card still said available
  // until a full reload; the product page was right.
  test('a grid already open shows the last one bought as sold out', () async {
    final store = await as('merchant@saba.app');
    final shelf = store.read(merchantRepositoryProvider);
    final row = (await shelf.inventory()).unwrap().items.firstWhere(
      (row) => row.productId == 'p-5',
    );
    (await shelf.adjustStock(
      inventoryId: row.id,
      quantity: 1 - row.available,
    )).unwrap();

    final c = await as('shopper@saba.app');
    final name = MockData.products.firstWhere((p) => p['id'] == 'p-5')['name'];
    final query = ProductQuery(search: '$name');
    final open = c.listen(productListProvider(query), (_, _) {});
    addTearDown(open.close);
    ProductSummary card(PagedState<ProductSummary> state) =>
        state.items.firstWhere((p) => p.id == 'p-5');
    expect(
      card(await c.read(productListProvider(query).future)).stockStatus,
      isNot(StockStatus.outOfStock),
    );

    await c
        .read(cartControllerProvider.notifier)
        .addItem(productId: 'p-5', quantity: 1);
    final checkout = c.read(checkoutControllerProvider.notifier);
    await checkout.priceOrder();
    (await checkout.placeOrder()).unwrap();
    // The order's announcement arrives on the next turn.
    await Future<void>.delayed(Duration.zero);
    expect(
      card(await c.read(productListProvider(query).future)).stockStatus,
      StockStatus.outOfStock,
    );
  });
}
