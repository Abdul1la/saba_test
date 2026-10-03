// M3 (BACKEND_PLAN.md 8.1): products, from the store's shelf to the
// shopper, with the app's own code against the real server. Skipped unless
// asked for; run in phases, the web answering between them:
//
//   flutter test test/live/m3_products_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1 \
//     --dart-define=PHASE=add|answered|takendown|restored|shelf
//
// The store is M2's test store; the shopper is the demo shopper.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/config/app_config.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart';
import 'package:saba_marketplace/features/catalog/domain/product_query.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/home/domain/entities.dart';
import 'package:saba_marketplace/features/home/presentation/home_providers.dart';
import 'package:saba_marketplace/features/media/data/media_repository_impl.dart';
import 'package:saba_marketplace/features/media/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/features/search/presentation/search_providers.dart';
import 'package:saba_marketplace/features/wishlist/presentation/wishlist_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _phase = String.fromEnvironment('PHASE', defaultValue: 'add');
const _storePhone = '+9647732172587';
const _storePassword = 'walkpass123';
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};

  setUpAll(() {
    HttpOverrides.global = null;
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

  Future<ProviderContainer> app({String locale = 'en'}) async {
    store.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': locale,
    });
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(await AppPreferences.create()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    return c;
  }

  String say(Result<Object?> result) => result.fold(
    ok: (value) => 'OK',
    err: (Failure f) => 'ERR ${f.statusCode} "${f.message}" ${f.fieldErrors}',
  );

  Future<ProviderContainer> asStore({String locale = 'en'}) async {
    final c = await app(locale: locale);
    final r = await c
        .read(authControllerProvider.notifier)
        .signIn(phone: _storePhone, password: _storePassword);
    print('store sign-in ($locale): ${say(r)}');
    return c;
  }

  Future<ProviderContainer> asShopper({String locale = 'en'}) async {
    final c = await app(locale: locale);
    final r = await c
        .read(authControllerProvider.notifier)
        .signIn(phone: '+9647701234567', password: 'saba12345');
    print('shopper sign-in ($locale): ${say(r)}');
    return c;
  }

  /// Every page of the store's shelf.
  Future<List<MerchantProductRow>> shelf(
    ProviderContainer c, {
    String? filter,
  }) async {
    final rows = <MerchantProductRow>[];
    for (var page = 1; ; page++) {
      final list =
          (await c
                  .read(merchantRepositoryProvider)
                  .products(filter: filter, page: page))
              .unwrap();
      rows.addAll(list.items);
      if (!list.hasNextPage) return rows;
    }
  }

  Future<MerchantProductRow?> row(ProviderContainer c, String name) async {
    for (final r in await shelf(c)) {
      if (r.name == name) return r;
    }
    return null;
  }

  /// Every page of the shopper's grid for [query].
  Future<List<ProductSummary>> grid(
    ProviderContainer c,
    ProductQuery query,
  ) async {
    final found = <ProductSummary>[];
    for (var page = 1; page < 30; page++) {
      final list = await c
          .read(catalogRepositoryProvider)
          .fetchProducts(query: query, page: page);
      if (list.isErr) {
        print('   grid ${query.toQueryParameters()}: ${say(list)}');
        return found;
      }
      found.addAll(list.valueOrNull!.items);
      if (!list.valueOrNull!.hasNextPage) break;
    }
    return found;
  }

  String has(List<ProductSummary> items, String id) =>
      items.any((p) => p.id == id) ? 'FOUND' : 'absent';

  Future<(Category, Category)> categoryPair(
    ProviderContainer c,
    String parentName,
    String childName,
  ) async {
    final tree = (await c.read(catalogRepositoryProvider).fetchCategoryTree())
        .unwrap();
    final parent = tree.firstWhere(
      (cat) => cat.name.toLowerCase().contains(parentName.toLowerCase()),
    );
    final child = parent.children.firstWhere(
      (cat) => cat.name.toLowerCase().contains(childName.toLowerCase()),
    );
    return (parent, child);
  }

  Future<void> inbox(ProviderContainer c, String label, {int count = 4}) async {
    final list = await c.read(notificationsRepositoryProvider).fetch();
    for (final n in (list.valueOrNull?.items ?? const []).take(count)) {
      print(
        '$label: "${n.title}" / "${n.body}" -> ${n.targetType}:${n.targetId}',
      );
    }
  }

  test('M3 phase $_phase', skip: !_live, timeout: Timeout.none, () async {
    print('API ${AppConfig.apiBaseUrl} mock=${AppConfig.useMockData}');
    final s = await asStore();
    final shelfRepo = s.read(merchantRepositoryProvider);
    final (phones, smartphones) = await categoryPair(s, 'phone', 'smart');
    final (accessories, cases) = await categoryPair(s, 'access', 'case');
    print(
      'categories: ${phones.name}(${phones.id}) > ${smartphones.name}(${smartphones.id}); '
      '${accessories.name}(${accessories.id}) > ${cases.name}(${cases.id})',
    );

    if (_phase == 'add') {
      final brands =
          (await s
                  .read(catalogRepositoryProvider)
                  .fetchBrands(categoryId: smartphones.id))
              .unwrap();
      final brand = brands.first;
      print('brand: ${brand.name}(${brand.id})');

      // Photos, the store's own.
      final media = MediaRepositoryImpl(s.read(apiClientProvider));
      final urls = <String>[];
      for (final file in [
        'phones-1.jpg',
        'accessories-1.jpg',
        'cameras-1.jpg',
      ]) {
        final path = 'assets/images/products/$file';
        final bytes = File(
          File(path).existsSync()
              ? path
              : 'assets/images/products/accessories-1.jpg',
        ).readAsBytesSync();
        final up = await media.upload(
          PickedMedia(
            fileName: file,
            sizeBytes: bytes.length,
            mimeType: 'image/jpeg',
            bytes: bytes,
          ),
        );
        print('1 photo $file: ${say(up)}');
        if (up.valueOrNull case final m?) urls.add(m.url);
      }

      ProductDraft phone({
        String name = 'M3 Phone',
        String nameAr = 'هاتف أوميغا',
        num price = 250000,
        num? originalPrice,
        int stock = 0,
        List<String>? images,
        List<ProductVariantDraft>? variants,
      }) => ProductDraft(
        name: name,
        nameAr: nameAr,
        description: 'A 6.5-inch phone, 128 GB, for the M3 walk.',
        categoryId: smartphones.id,
        brandId: brand.id,
        price: price,
        originalPrice: originalPrice,
        stock: stock,
        imageUrls: images ?? urls,
        variants:
            variants ??
            const [
              ProductVariantDraft(
                options: {'Colour': 'Black'},
                price: 250000,
                stock: 5,
              ),
              ProductVariantDraft(
                options: {'Colour': 'White'},
                price: 260000,
                stock: 3,
              ),
            ],
      );

      // Each refusal first.
      for (final (label, draft) in [
        ('no Arabic letter', phone(nameAr: 'Omega phone')),
        ('Arabic name of 2', phone(nameAr: 'هت')),
        ('price 12,100', phone(price: 12100, variants: const [])),
        ('price 200', phone(price: 200, variants: const [])),
        (
          '"was" price lower',
          phone(price: 250000, originalPrice: 240000, variants: const []),
        ),
        ('11 photos', phone(images: List.filled(11, urls.first))),
        ('a photo not uploaded', phone(images: ['https://example.com/x.jpg'])),
        (
          'two options the same',
          phone(
            variants: const [
              ProductVariantDraft(
                options: {'Colour': 'Black'},
                price: 250000,
                stock: 1,
              ),
              ProductVariantDraft(
                options: {'Colour': 'Black'},
                price: 250000,
                stock: 1,
              ),
            ],
          ),
        ),
        ('stock 100,000', phone(stock: 100000, variants: const [])),
      ]) {
        print('1 refused? $label: ${say(await shelfRepo.saveProduct(draft))}');
      }

      print('1 save M3 Phone: ${say(await shelfRepo.saveProduct(phone()))}');
      print(
        '2 save M3 Case: ${say(await shelfRepo.saveProduct(ProductDraft(name: 'M3 Case', nameAr: 'غطاء أنيق', description: 'A slim case for the M3 walk.', categoryId: cases.id, price: 15000, stock: 20, imageUrls: urls.take(1).toList())))}',
      );
      for (final name in ['M3 Phone', 'M3 Case']) {
        final r = await row(s, name);
        print(
          '2 shelf $name: id=${r?.id} status=${r?.status} stock=${r?.stock}',
        );
      }
      final waiting = await shelf(s, filter: 'waiting');
      print('2 Waiting tab: ${[for (final r in waiting) r.name]}');
      print('2 counts: ${(await shelfRepo.productCounts()).valueOrNull}');

      // 13. The refusals in Arabic.
      final ar = await asStore(locale: 'ar');
      final arShelf = ar.read(merchantRepositoryProvider);
      print(
        '13 ar no Arabic letter: ${say(await arShelf.saveProduct(phone(nameAr: 'Omega phone')))}',
      );
      print(
        '13 ar price 12,100: ${say(await arShelf.saveProduct(phone(price: 12100, variants: const [])))}',
      );
      return;
    }

    final phoneRow = await row(s, 'M3 Phone');
    final caseRow = await row(s, 'M3 Case');
    print(
      'shelf: M3 Phone ${phoneRow?.id} ${phoneRow?.status} shown=${phoneRow?.isActive} '
      'options=${phoneRow?.hasVariants} '
      'takenDown=${phoneRow?.takenDown} "${phoneRow?.takenDownReason}"; '
      'M3 Case ${caseRow?.id} ${caseRow?.status} "${caseRow?.rejectionReason}"',
    );
    final phoneId = phoneRow!.id;
    final sh = await asShopper();
    final catalog = sh.read(catalogRepositoryProvider);

    Future<void> findPhone(String label) async {
      print(
        '$label search "M3 Phone": ${has(await grid(sh, const ProductQuery(search: 'M3 Phone')), phoneId)}',
      );
      print(
        '$label in ${smartphones.name}: ${has(await grid(sh, ProductQuery(categoryId: smartphones.id)), phoneId)}',
      );
      print(
        '$label store page: ${has(await grid(sh, ProductQuery(merchantId: phoneRow.id.isEmpty ? null : s.read(currentUserProvider)?.merchant?.id)), phoneId)}',
      );
      final wished =
          (await sh.read(wishlistRepositoryProvider).fetchItems()).valueOrNull;
      print(
        '$label wishlist: ${wished == null ? 'ERR' : has(wished, phoneId)}',
      );
    }

    if (_phase == 'answered') {
      // 3. The store is told; the rejected one is changed and sent again.
      await inbox(s, '3 store');
      await inbox(await asStore(locale: 'ar'), '13 ar store');
      if (caseRow case final c?) {
        final full = (await shelfRepo.product(c.id)).unwrap();
        final edited = await shelfRepo.saveProduct(
          ProductDraft(
            id: c.id,
            name: 'M3 Case',
            nameAr: 'غطاء أنيق',
            description: 'A slim case for the M3 walk, photos changed.',
            categoryId: full.categoryId ?? cases.id,
            price: 15000,
            stock: 20,
            imageUrls: [for (final m in full.media) m.url],
          ),
        );
        print(
          '3 edit M3 Case: ${say(edited)} -> ${(await row(s, 'M3 Case'))?.status}',
        );
        print(
          '3 submit M3 Case: ${say(await shelfRepo.submitForApproval(c.id))} '
          '-> ${(await row(s, 'M3 Case'))?.status}',
        );
      }

      // 4. The shopper finds it.
      await findPhone('4');
      print(
        '4 search Arabic with ا: ${has(await grid(sh, const ProductQuery(search: 'هاتف اوميغا')), phoneId)}',
      );
      print(
        '4 search category name "${smartphones.name}": ${has(await grid(sh, ProductQuery(search: smartphones.name)), phoneId)}',
      );
      final suggestions = await sh
          .read(searchRepositoryProvider)
          .suggestions('M3 Ph');
      print(
        '4 suggestions "M3 Ph": ${say(suggestions)} ${[for (final x in suggestions.valueOrNull ?? const <SearchSuggestion>[]) '${x.type}:${x.text}']}',
      );
      print(
        '4 in ${phones.name}: ${has(await grid(sh, ProductQuery(categoryId: phones.id)), phoneId)}',
      );
      final others = (await grid(
        sh,
        ProductQuery(categoryId: smartphones.id),
      )).where((p) => p.id != phoneId).toList();
      if (others.isNotEmpty) {
        final related = await catalog.fetchRelatedProducts(others.first.id);
        print(
          '4 related on "${others.first.name}": ${say(related)} ${related.valueOrNull == null ? '' : has(related.valueOrNull!, phoneId)}',
        );
      }
      final page = await catalog.fetchProduct(phoneId);
      final p = page.valueOrNull;
      print(
        '4 page: ${say(page)} name="${p?.name}" photos=${p?.media.length} '
        'price=${p?.price} options=${p?.variantOptions} '
        'variants=${[for (final v in p?.variants ?? const <ProductVariant>[]) '${v.options} ${v.price} ${v.availableQuantity}']} '
        'store="${p?.merchant?.storeName}" open=${p?.merchant?.isOpen}',
      );

      // 5. Filters and sorting on a category.
      final brandId = p?.brand?.id;
      print(
        '5 brand ${p?.brand?.name}: ${has(await grid(sh, ProductQuery(categoryId: phones.id, brandIds: [?brandId])), phoneId)}',
      );
      print(
        '5 price 200,000-300,000: ${has(await grid(sh, ProductQuery(categoryId: phones.id, minPrice: 200000, maxPrice: 300000)), phoneId)}; '
        '0-100,000: ${has(await grid(sh, ProductQuery(categoryId: phones.id, minPrice: 0, maxPrice: 100000)), phoneId)}',
      );
      print(
        '5 in stock: ${has(await grid(sh, ProductQuery(categoryId: phones.id, inStockOnly: true)), phoneId)}; '
        'on sale: ${has(await grid(sh, ProductQuery(categoryId: phones.id, onSaleOnly: true)), phoneId)}',
      );
      for (final sort in ProductSort.values) {
        final items = await grid(
          sh,
          ProductQuery(categoryId: phones.id, sort: sort),
        );
        print(
          '5 sort ${sort.apiValue}: ${[for (final x in items.take(4)) '${x.name}:${x.price}']}',
        );
      }

      // 6. Wishlist.
      final wishlist = sh.read(wishlistRepositoryProvider);
      print('6 add: ${say(await wishlist.add(phoneId))}');
      print(
        '6 listed: ${has((await wishlist.fetchItems()).valueOrNull ?? const [], phoneId)}',
      );
      print('6 remove: ${say(await wishlist.remove(phoneId))}');
      print(
        '6 after remove: ${has((await wishlist.fetchItems()).valueOrNull ?? const [], phoneId)}',
      );
      print('6 add again: ${say(await wishlist.add(phoneId))}');

      // 7. A flash sale.
      final ends = DateTime.now().add(const Duration(hours: 3));
      for (final (label, price, end) in [
        ('not a step of 250', 230100, ends),
        ('not below the normal price', 260000, ends),
        (
          'ends in the past',
          230000,
          DateTime.now().subtract(const Duration(hours: 1)),
        ),
        ('an option below 250', 240000, ends),
      ]) {
        print(
          '7 refused? $label: ${say(await shelfRepo.startFlashSale(productId: phoneId, salePrice: price, endsAt: end))}',
        );
      }
      print(
        '7 start at 230,000: ${say(await shelfRepo.startFlashSale(productId: phoneId, salePrice: 230000, endsAt: ends))}',
      );
      final feed =
          (await sh.read(homeRepositoryProvider).fetchHomeFeed()).valueOrNull;
      final flash = feed?.where((x) => x.type == HomeSectionType.flashSale);
      print(
        '7 Home flash sales: ${flash == null || flash.isEmpty ? 'no section' : '${has(flash.first.products, phoneId)} ends ${flash.first.endsAt}'}',
      );
      final onSale = (await catalog.fetchProduct(phoneId)).valueOrNull;
      print(
        '7 page: price=${onSale?.price} was=${onSale?.originalPrice} '
        'variants=${[for (final v in onSale?.variants ?? const <ProductVariant>[]) v.price]}',
      );
      final found = (await grid(
        sh,
        const ProductQuery(search: 'M3 Phone'),
      )).where((x) => x.id == phoneId);
      print(
        '7 search: ${[for (final x in found) '${x.price} was ${x.originalPrice}']}',
      );
      print('7 end: ${say(await shelfRepo.endFlashSale(phoneId))}');
      final after = (await catalog.fetchProduct(phoneId)).valueOrNull;
      print(
        '7 after: price=${after?.price} was=${after?.originalPrice} '
        'variants=${[for (final v in after?.variants ?? const <ProductVariant>[]) v.price]}',
      );
      final afterSearch = (await grid(
        sh,
        const ProductQuery(search: 'M3 Phone'),
      )).where((x) => x.id == phoneId);
      print(
        '7 search after: ${[for (final x in afterSearch) '${x.price} was ${x.originalPrice}']}',
      );

      // 8. Stock.
      if (caseRow case final c?) {
        print(
          '8 M3 Case stock to 30: ${say(await shelfRepo.setProductStock(productId: c.id, stock: 30))} '
          '-> ${(await row(s, 'M3 Case'))?.stock}',
        );
      }
      print(
        '8 stepper on M3 Phone (known): ${say(await shelfRepo.setProductStock(productId: phoneId, stock: 10))}',
      );
      final inventory = (await shelfRepo.inventory())
          .unwrap()
          .items
          .where((r) => r.productId == phoneId)
          .toList();
      print(
        '8 inventory rows: ${[for (final r in inventory) '${r.id} ${r.variantLabel} ${r.available}']}',
      );
      if (inventory.isNotEmpty) {
        final one = inventory.first;
        Future<int?> now() async => (await shelfRepo.inventory())
            .unwrap()
            .items
            .firstWhere((r) => r.id == one.id)
            .available;
        print(
          '8 +3: ${say(await shelfRepo.adjustStock(inventoryId: one.id, quantity: 3))} -> ${await now()}',
        );
        print(
          '8 -2: ${say(await shelfRepo.adjustStock(inventoryId: one.id, quantity: -2))} -> ${await now()}',
        );
        print(
          '8 -1000: ${say(await shelfRepo.adjustStock(inventoryId: one.id, quantity: -1000))} -> ${await now()}',
        );
      }

      // 9. Hidden, and shown again.
      print(
        '9 hide: ${say(await shelfRepo.setProductShown(phoneId, shown: false))}',
      );
      await findPhone('9 hidden');
      print(
        '9 show: ${say(await shelfRepo.setProductShown(phoneId, shown: true))}',
      );
      await findPhone('9 shown');
      return;
    }

    if (_phase == 'takendown') {
      await findPhone('10 taken down');
      await inbox(s, '10 store', count: 2);
      return;
    }

    if (_phase == 'restored') {
      await inbox(s, '10 store', count: 2);
      await findPhone('10 restored');

      // 11. The store closed, and open again.
      print('11 close: ${say(await shelfRepo.setOpen(false))}');
      await findPhone('11 closed');
      final closedPage = (await catalog.fetchProduct(phoneId));
      print(
        '11 its page: ${say(closedPage)} open=${closedPage.valueOrNull?.merchant?.isOpen}',
      );
      print('11 open: ${say(await shelfRepo.setOpen(true))}');
      await findPhone('11 open again');

      // 12. M3 Case deleted; M3 Phone off the wishlist.
      if (caseRow case final c?) {
        print(
          '12 counts before: ${(await shelfRepo.productCounts()).valueOrNull}',
        );
        print('12 delete M3 Case: ${say(await shelfRepo.deleteProduct(c.id))}');
        print(
          '12 on the shelf: ${(await row(s, 'M3 Case')) == null ? 'gone' : 'STILL THERE'}',
        );
        print('12 counts: ${(await shelfRepo.productCounts()).valueOrNull}');
      }
      print(
        '12 wishlist remove: ${say(await sh.read(wishlistRepositoryProvider).remove(phoneId))}',
      );

      // 13. In Arabic.
      final ar = await asShopper(locale: 'ar');
      final arPage =
          (await ar.read(catalogRepositoryProvider).fetchProduct(phoneId))
              .valueOrNull;
      print(
        '13 ar page: name="${arPage?.name}" category="${arPage?.categoryName}"',
      );
      final arTree =
          (await ar.read(catalogRepositoryProvider).fetchCategoryTree())
              .valueOrNull;
      print(
        '13 ar categories: ${[for (final c in arTree ?? const <Category>[]) c.name].take(4)}',
      );
      await inbox(await asStore(locale: 'ar'), '13 ar store', count: 3);
    }
  });

  // Step 10 on the real shelf: Saba's reason shown, the show/hide button
  // locked while the product is down. And (phase shelf) no whole-product
  // stock control on a product sold in options.
  testWidgets(
    'M3 on the real shelf',
    skip: !_live || (_phase != 'takendown' && _phase != 'shelf'),
    (tester) async {
      tester.view.physicalSize = const Size(411 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => Directory.systemTemp.path,
          );
      final c = (await tester.runAsync(asStore))!;
      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const SabaApp()),
      );
      await settle();
      c.read(appRouterProvider).go(AppRoutes.merchantProducts);
      await settle();
      final reason = find.textContaining('taken down by Saba for the mobile');
      print(
        '10 shelf: "Taken down by Saba" ${find.textContaining('Taken down by Saba').evaluate().length}x, reason ${reason.evaluate().length}x',
      );
      final toggles = tester.widgetList<IconButton>(
        find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              (w.tooltip == 'Hide from shoppers' ||
                  w.tooltip == 'Show to shoppers'),
        ),
      );
      print(
        '10 show/hide buttons: ${[for (final b in toggles) b.onPressed == null ? 'locked' : 'active']}',
      );
      final phone = find
          .ancestor(of: find.text('M3 Phone'), matching: find.byType(InkWell))
          .first;
      print(
        '8 M3 Phone row: ${[
          for (final tip in ['Increase', 'Decrease']) '$tip ${find.descendant(of: phone, matching: find.byTooltip(tip)).evaluate().length}x',
        ]}, '
        'Restock ${find.descendant(of: phone, matching: find.text('Restock')).evaluate().length}x',
      );
      await tester.runAsync(
        () => c.read(authControllerProvider.notifier).signOut(),
      );
      await tester.pumpWidget(const SizedBox());
      await settle();
    },
  );
}
