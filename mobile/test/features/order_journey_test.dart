import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/network/api_client.dart';
import 'package:saba_marketplace/core/network/api_response.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import '../support/saba_web.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/domain/catalog_repository.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart'
    show ProductSummary;
import 'package:saba_marketplace/features/catalog/domain/product_query.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/home/domain/entities.dart'
    show HomeSection, HomeSectionType;
import 'package:saba_marketplace/features/home/presentation/home_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';
import 'package:saba_marketplace/features/orders/domain/orders_repository.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/returns/domain/entities.dart';
import 'package:saba_marketplace/features/returns/presentation/returns_providers.dart';
import 'package:saba_marketplace/features/search/presentation/search_providers.dart';

/// One store's part of an order, from the store's call to the shopper's
/// door and, within 7 days, back: through the real pipeline down to the
/// demo backend.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _driver = Courier(name: 'Ali', phone: '+9647701112222');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keys = <String, String>{};
  late AppPreferences preferences;

  setUp(() async {
    DioFactory.mockBackend.resetForTesting();
    keys.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await AppPreferences.create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'write':
              keys[call.arguments['key'] as String] =
                  call.arguments['value'] as String? ?? '';
              return null;
            case 'read':
              return keys[call.arguments['key'] as String];
            case 'delete':
              keys.remove(call.arguments['key'] as String);
              return null;
            case 'readAll':
              return Map<String, String>.from(keys);
            case 'deleteAll':
              keys.clear();
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// The shopper, Nova's owner, and the calls between them.
  Future<_Journey> start() async {
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final journey = _Journey(container);
    await journey.asShopper();
    return journey;
  }

  test('shipping names who brings it; the shopper can call them', () async {
    final j = await start();
    final orderId = await j.buy();

    await j.asStore();
    final part = await j.storePart();
    await j.move(part, ['CONFIRMED', 'PROCESSING']);
    expect(
      (await j.store.updateOrderStatus(orderId: part, status: 'SHIPPED')).isOk,
      isFalse,
      reason: 'shipped with nobody named to bring it',
    );
    await j.move(part, ['SHIPPED']);

    await j.asShopper();
    final nova = (await j.orders.fetchOrder(orderId)).unwrap().parts['m-1']!;
    expect(nova.courierName, 'Ali', reason: 'the shopper is not told who');
    expect(nova.courierPhone, '+9647701112222');
  });

  test(
    'stock comes back when a part is declined, refused or cancelled',
    () async {
      final j = await start();
      final before = await j.stock();

      // Declined by the store.
      await j.buy();
      expect(await j.stock(), before - 1);
      await j.asStore();
      (await j.store.updateOrderStatus(
        orderId: await j.storePart(),
        status: 'CANCELLED',
        reason: 'Out of stock',
      )).unwrap();
      expect(await j.stock(), before, reason: 'a declined part kept its stock');

      // Refused at the door.
      await j.asShopper();
      final refusedOrder = await j.buy();
      await j.asStore();
      final part = await j.storePart();
      await j.move(part, ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'REFUSED']);
      expect(await j.stock(), before, reason: 'a refused part kept its stock');
      await j.asShopper();
      expect(
        (await j.orders.fetchOrder(refusedOrder)).unwrap().status,
        OrderStatus.refused,
      );

      // Cancelled by the shopper - with a reason, or not at all.
      final cancelled = await j.buy();
      expect(
        (await j.orders.cancelOrder(orderId: cancelled, reason: '')).isOk,
        isFalse,
        reason: 'an order was cancelled with no reason given',
      );
      (await j.orders.cancelOrder(
        orderId: cancelled,
        reason: 'CHANGED_MIND',
      )).unwrap();
      expect(
        await j.stock(),
        before,
        reason: 'a cancelled order kept its stock',
      );
    },
  );

  test('"did you receive it" is asked once the store says it went', () async {
    final j = await start();
    final orderId = await j.buy();

    await j.asStore();
    await j.move(await j.storePart(), [
      'CONFIRMED',
      'PROCESSING',
      'SHIPPED',
      'DELIVERED',
    ]);
    await j.asShopper();

    // "No": the store hears of it, to call the shopper.
    final answered = (await j.orders.confirmReceived(
      orderId: orderId,
      merchantId: 'm-1',
      received: false,
    )).unwrap();
    expect(answered.parts['m-1']!.received, isFalse);
    await j.asStore();
    final inbox =
        (await j.container.read(notificationsRepositoryProvider).fetch())
            .unwrap();
    expect(inbox.items.map((n) => n.title), contains(startsWith('Order ')));
    expect(
      inbox.items.any((n) => n.title.endsWith('not received')),
      isTrue,
      reason: 'the store was not told',
    );
  });

  test(
    'a return: the store approves, collects and hands the cash back',
    () async {
      final j = await start();
      final orderId = await j.buy(quantity: 2);
      final line = (await j.orders.fetchOrder(orderId)).unwrap().items.single;
      Future<bool> askToReturn() async => (await j.orders.requestReturn(
        orderId: orderId,
        lines: [ReturnLine(orderItemId: line.id, quantity: 2)],
        reason: 'DAMAGED',
      )).isOk;

      expect(await askToReturn(), isFalse, reason: 'returned before it came');

      await j.asStore();
      await j.move(await j.storePart(), [
        'CONFIRMED',
        'PROCESSING',
        'SHIPPED',
        'DELIVERED',
      ]);
      await j.asShopper();
      final stock = await j.stock();
      expect(await askToReturn(), isTrue);

      final summary =
          (await j.container.read(returnsRepositoryProvider).fetchReturns())
              .unwrap()
              .items
              .first;
      var request =
          (await j.container
                  .read(returnsRepositoryProvider)
                  .fetchReturn(summary.id))
              .unwrap();
      expect(
        request.refund?.amount,
        line.unitPrice * 2,
        reason: 'the refund was not what was paid',
      );
      expect(request.items.single.name, line.productName);
      expect(request.refund?.method, 'Cash, from the store');

      // The store sees it on its order, and answers it step by step.
      await j.asStore();
      final part = await j.storePart(status: 'DELIVERED');
      final onOrder = (await j.store.order(part)).unwrap().returns;
      expect(onOrder.map((r) => r.id), [request.id]);
      expect(
        (await j.store.answerReturn(request.id, 'REFUNDED')).isOk,
        isFalse,
        reason: 'cash handed back before the item was collected',
      );
      (await j.store.answerReturn(request.id, 'APPROVED')).unwrap();
      (await j.store.answerReturn(request.id, 'REFUNDED')).unwrap();
      expect(
        await j.stock(),
        stock + 2,
        reason: 'the item is not back on sale',
      );

      await j.asShopper();
      request =
          (await j.container
                  .read(returnsRepositoryProvider)
                  .fetchReturn(request.id))
              .unwrap();
      expect(request.status, ReturnStatus.refunded);
      expect(request.refund?.status, RefundStatus.completed);
    },
  );

  test('the store owes Saba 8% of what it delivered, less returns', () async {
    final j = await start();
    num share(num base) => (base * 8 / 100 / 250).round() * 250;
    await j.asStore();
    final before = (await j.store.bills()).unwrap().current;

    await j.asShopper();
    final orderId = await j.buy(quantity: 2);
    final line = (await j.orders.fetchOrder(orderId)).unwrap().items.single;
    await j.asStore();
    expect(
      (await j.store.bills()).unwrap().current.sales,
      before.sales,
      reason: 'counted before it was delivered',
    );
    await j.move(await j.storePart(), [
      'CONFIRMED',
      'PROCESSING',
      'SHIPPED',
      'DELIVERED',
    ]);
    final bill = (await j.store.bills()).unwrap().current;
    expect(bill.sales, before.sales + line.unitPrice * 2);
    expect(bill.orderCount, before.orderCount + 1);
    expect(bill.owed, share(bill.sales - bill.returned));
    expect(bill.owed % 250, 0, reason: 'not an amount cash can pay');

    // The dashboard and the analytics count the same sales.
    expect((await j.store.dashboard()).unwrap().revenue, bill.sales);
    expect((await j.store.analytics()).unwrap().revenue, bill.sales);

    // One comes back, and its cash is handed back: it comes off.
    await j.asShopper();
    (await j.orders.requestReturn(
      orderId: orderId,
      lines: [ReturnLine(orderItemId: line.id, quantity: 1)],
      reason: 'DAMAGED',
    )).unwrap();
    await j.asStore();
    final part = await j.storePart(status: 'DELIVERED');
    final request = (await j.store.order(part)).unwrap().returns.single;
    (await j.store.answerReturn(request.id, 'APPROVED')).unwrap();
    (await j.store.answerReturn(request.id, 'REFUNDED')).unwrap();
    final after = (await j.store.bills()).unwrap().current;
    expect(after.returned, bill.returned + line.unitPrice);
    expect(after.owed, share(after.sales - after.returned));
  });

  test('a closed store takes no orders, and says so', () async {
    final j = await start();
    await j.asStore();
    (await j.store.setOpen(false)).unwrap();
    expect((await j.store.dashboard()).unwrap().isOpen, isFalse);

    await j.asShopper();
    final product = (await j.catalog.fetchProduct(j.product)).unwrap();
    expect(product.merchant?.isOpen, isFalse, reason: 'the page does not know');
    final refused = await j.tryBuy();
    expect(refused.isOk, isFalse, reason: 'a closed store took an order');
    expect(refused.failureOrNull?.message, contains('Closed right now'));

    await j.asStore();
    (await j.store.setOpen(true)).unwrap();
    await j.asShopper();
    expect((await j.tryBuy()).isOk, isTrue);
  });

  test('a product needs its Arabic name, and Arabic readers see it', () async {
    final j = await start();
    await j.asStore();
    ProductDraft draft(String arabic) => ProductDraft(
      id: j.product,
      name: 'Earbuds',
      nameAr: arabic,
      categoryId: 'c-audio',
      price: 25000,
      stock: 5,
    );

    final missing = await j.store.saveProduct(draft(''));
    expect(missing.isOk, isFalse, reason: 'saved with no Arabic name');
    expect(missing.failureOrNull?.messageForField('nameAr'), isNotNull);
    expect(
      (await j.store.saveProduct(draft('Earbuds'))).isOk,
      isFalse,
      reason: 'English letters taken as the Arabic name',
    );
    (await j.store.saveProduct(draft('سماعات'))).unwrap();

    // Kept: the form reopens with it, and the shopper's page shows it.
    final kept = (await j.store.product(j.product)).unwrap();
    expect(kept.nameAr, 'سماعات');
    expect(kept.nameEn, 'Earbuds');
    expect(kept.price, 25000, reason: "Nova's edit was not kept");
    await j.asShopper();
    expect((await j.catalog.fetchProduct(j.product)).unwrap().name, 'Earbuds');
    await j.container
        .read(localeControllerProvider.notifier)
        .setLocale(const Locale('ar'));
    expect((await j.catalog.fetchProduct(j.product)).unwrap().name, 'سماعات');
  });

  test('Home: the stores\' flash sales, and every store', () async {
    final j = await start();
    await j.asShopper();
    Future<List<HomeSection>> home() async =>
        (await j.container.read(homeRepositoryProvider).fetchHomeFeed())
            .unwrap();
    HomeSection of(List<HomeSection> feed, HomeSectionType type) =>
        feed.firstWhere((section) => section.type == type);

    final feed = await home();
    for (final gone in [
      's-trending',
      's-bestsellers',
      's-brands',
      's-sale',
      's-new',
    ]) {
      expect(feed.map((section) => section.id), isNot(contains(gone)));
    }

    // The flash sales the stores are running, the soonest to end first,
    // and the countdown to that one's end.
    final flash = of(feed, HomeSectionType.flashSale);
    expect(flash.products, isNotEmpty);
    final now = DateTime.now();
    for (final product in flash.products) {
      expect(
        product.originalPrice,
        greaterThan(product.price),
        reason: '${product.name} is in the sale at its full price',
      );
      expect(
        product.flashSaleEndsAt?.isAfter(now),
        isTrue,
        reason: '${product.name} is in the sale with no end still to come',
      );
    }
    final ends = [
      for (final product in flash.products) product.flashSaleEndsAt!,
    ];
    expect(ends, orderedEquals([...ends]..sort()));
    expect(
      flash.endsAt?.isAtSameMomentAs(ends.first),
      isTrue,
      reason: 'the countdown is not to the soonest end: ${flash.endsAt}',
    );

    // Every store, wherever it is, with the products it has.
    final stores = of(feed, HomeSectionType.merchantCarousel).merchants;
    expect(
      stores.map((store) => store.id),
      unorderedEquals([for (final store in MockData.merchants) store['id']]),
    );
    for (final store in stores) {
      expect(
        store.productCount,
        MockData.products
            .where(
              (p) =>
                  (p['merchant'] as Map)['id'] == store.id &&
                  MockData.startsOnSale(p['id']),
            )
            .length,
        reason: '${store.storeName} claims products it does not have',
      );
    }

    // A closed store's offers leave the sale: nobody can buy them.
    expect(flash.products.map((p) => p.merchantId), contains('m-1'));
    await j.asStore();
    (await j.store.setOpen(false)).unwrap();
    await j.asShopper();
    expect(
      of(
        await home(),
        HomeSectionType.flashSale,
      ).products.map((p) => p.merchantId),
      isNot(contains('m-1')),
    );
  });

  test(
    'a flash sale: the store sets it, Home shows it, it ends on its own',
    () async {
      final j = await start();
      await j.asStore();
      final before = MockData.productById(j.product)!['price'] as num;
      Future<Result<void>> sale(num price, Duration from) =>
          j.store.startFlashSale(
            productId: j.product,
            salePrice: price,
            endsAt: DateTime.now().add(from),
          );
      String? refused(Result<void> result, String field) =>
          result.failureOrNull?.messageForField(field);

      // Cash steps, lower than the price, and an end still to come.
      const hour = Duration(hours: 1);
      expect(refused(await sale(before - 100, hour), 'salePrice'), isNotNull);
      expect(refused(await sale(before, hour), 'salePrice'), isNotNull);
      expect(
        refused(await sale(before - 1000, -hour), 'saleEndsAt'),
        isNotNull,
      );

      (await sale(before - 50000, const Duration(seconds: 2))).unwrap();
      final row = (await j.store.products(
        query: MockData.productById(j.product)!['name'] as String,
      )).unwrap().items.firstWhere((row) => row.id == j.product);
      expect(row.isOnFlashSale, isTrue);
      expect(row.price, before - 50000);
      expect(row.priceBeforeSale, before);

      await j.asShopper();
      final flash = (await j.flashSale())!;
      final card = flash.products.firstWhere((p) => p.id == j.product);
      expect(card.price, before - 50000);
      expect(card.originalPrice, before);
      expect(
        flash.endsAt?.isAtSameMomentAs(card.flashSaleEndsAt!),
        isTrue,
        reason: 'the countdown is not to the soonest sale',
      );

      // Over on its own: the price it had, everywhere it is read.
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(
        (await j.flashSale())!.products.map((p) => p.id),
        isNot(contains(j.product)),
      );
      final page = (await j.catalog.fetchProduct(j.product)).unwrap();
      expect(page.price, before, reason: 'the sale ended and kept its price');
      expect(page.originalPrice, isNull);
      expect(await j.stock(), isPositive);
      final placed = await j.buy();
      final order = (await j.orders.fetchOrder(placed)).unwrap();
      expect(order.items.single.unitPrice, before);
    },
  );

  // A store's own product never reached the flash sale: Home read the
  // demo's products alone, where the product list reads the approved ones
  // stores added too.
  test('a store\'s own approved product reaches the flash sale', () async {
    final j = await start();
    await j.asStore();
    final body = <String, dynamic>{
      'name': 'Nova Pocket Speaker',
      'nameAr': 'سماعة نوفا الصغيرة',
      'price': 60000,
      'stock': 10,
      'categoryId': 'c-headphones',
    };
    final id =
        (await j.client.post<Map<String, dynamic>>(
              ApiEndpoints.merchantOwnProducts,
              data: body,
              decoder: (envelope) => envelope.dataAsMap,
            )).unwrap()['id']
            as String;
    await j._signIn('admin@saba.app');
    expect(
      await j.container.read(adminAnswersProvider).product(id, approve: true),
      isNull,
    );

    await j.asStore();
    (await j.store.startFlashSale(
      productId: id,
      salePrice: 45000,
      endsAt: DateTime.now().add(const Duration(hours: 1)),
    )).unwrap();
    await j.asShopper();
    expect((await j.flashSale())!.products.map((p) => p.id), contains(id));
    final feed =
        (await j.container.read(homeRepositoryProvider).fetchHomeFeed())
            .unwrap();
    final nova = feed
        .firstWhere((s) => s.type == HomeSectionType.merchantCarousel)
        .merchants
        .firstWhere((store) => store.id == 'm-1');
    expect(
      nova.productCount,
      MockData.products
              .where(
                (p) =>
                    (p['merchant'] as Map)['id'] == 'm-1' &&
                    MockData.startsOnSale(p['id']),
              )
              .length +
          1,
      reason: 'Home does not count the product Nova added',
    );

    // Changed during the sale, it stays on it, and ending it gives back
    // the price from before.
    await j.asStore();
    (await j.client.command(
      ApiEndpoints.merchantOwnProduct(id),
      method: 'PUT',
      data: {...body, 'price': 45000, 'originalPrice': 60000},
    )).unwrap();
    await j.asShopper();
    expect((await j.flashSale())!.products.map((p) => p.id), contains(id));
    await j.asStore();
    (await j.store.endFlashSale(id)).unwrap();
    await j.asShopper();
    expect((await j.catalog.fetchProduct(id)).unwrap().price, 60000);
  });

  test('a hidden or deleted product leaves the flash sale', () async {
    final j = await start();
    await j.asStore();
    (await j.store.startFlashSale(
      productId: j.product,
      salePrice: 100000,
      endsAt: DateTime.now().add(const Duration(hours: 1)),
    )).unwrap();
    Future<bool> inSale() async {
      await j.asShopper();
      final shown = (await j.flashSale())!.products.map((p) => p.id);
      await j.asStore();
      return shown.contains(j.product);
    }

    expect(await inSale(), isTrue);
    (await j.store.setProductShown(j.product, shown: false)).unwrap();
    expect(await inSale(), isFalse, reason: 'a hidden product is on sale');
    // Nor can one be put on a sale: nobody would see it.
    expect(
      (await j.store.startFlashSale(
        productId: j.product,
        salePrice: 90000,
        endsAt: DateTime.now().add(const Duration(hours: 1)),
      )).failureOrNull?.statusCode,
      409,
    );
    (await j.store.setProductShown(j.product, shown: true)).unwrap();
    expect(await inSale(), isTrue);
    (await j.store.deleteProduct(j.product)).unwrap();
    expect(await inSale(), isFalse, reason: 'a deleted product is on sale');
  });

  // The store's shelf said "Out of stock" for Kite headphones shoppers saw
  // in stock, on the flash sale and in their carts.
  test('the store and the shopper are told the same stock', () async {
    final j = await start();
    await j.asStore();
    final rows = (await j.store.products()).unwrap().items;
    await j.asShopper();
    var compared = 0;
    for (final row in rows) {
      final seen = await j.catalog.fetchProduct(row.id);
      // Only what shoppers can open: not a draft, waiting or hidden one.
      if (seen case Ok(value: final product)) {
        expect(
          row.stock,
          product.availableQuantity,
          reason: '${row.name}: the store and the shopper disagree',
        );
        compared++;
      }
    }
    expect(compared, greaterThan(3));
  });

  test('"End sale now": every option back to its price', () async {
    final j = await start();
    await j.asStore();
    // Nova's laptop, sold in options, not on a sale yet.
    const phone = 'p-3';
    Future<List<num>> prices() async {
      final product = (await j.catalog.fetchProduct(phone)).unwrap();
      return [product.price, for (final v in product.variants) v.price];
    }

    final before = await prices();
    (await j.store.startFlashSale(
      productId: phone,
      salePrice: before.first - 9000,
      endsAt: DateTime.now().add(const Duration(hours: 1)),
    )).unwrap();
    expect(await prices(), [
      for (final price in before) price - 9000,
    ], reason: 'each option comes down by the same amount');
    (await j.store.endFlashSale(phone)).unwrap();
    expect(await prices(), before);
    expect(
      (await j.store.products(
        query: MockData.productById(phone)!['name'] as String,
      )).unwrap().items.firstWhere((row) => row.id == phone).isOnFlashSale,
      isFalse,
    );
  });

  test(
    'a city shows the products of its stores; delivery is per store',
    () async {
      final j = await start();
      await j.asShopper();
      Future<PaginatedList<ProductSummary>> list(ProductQuery query) async =>
          (await j.catalog.fetchProducts(query: query)).unwrap();

      expect(
        (await list(const ProductQuery())).meta.total,
        MockData.products.where((p) => MockData.startsOnSale(p['id'])).length,
      );
      final duhok = await list(
        const ProductQuery(governorate: 'DUHOK', deliverTo: 'BAGHDAD'),
      );
      expect(
        duhok.meta.total,
        13,
        reason: 'the count does not follow the city',
      );
      expect(duhok.items.map((p) => p.merchantId).toSet(), {'m-3', 'm-4'});
      // Neither Duhok store sends to Baghdad; both send to Erbil.
      expect(duhok.items.where((p) => p.deliveryAvailable), isEmpty);
      expect(
        (await list(
          const ProductQuery(governorate: 'DUHOK', deliverTo: 'ERBIL'),
        )).items.every((p) => p.deliveryAvailable),
        isTrue,
      );
      // Nova, in Baghdad, sends everywhere.
      final baghdad = await list(
        const ProductQuery(governorate: 'BAGHDAD', deliverTo: 'BAGHDAD'),
      );
      expect(baghdad.items.map((p) => p.merchantId).toSet(), {'m-1'});
      expect(baghdad.items.every((p) => p.deliveryAvailable), isTrue);
      // Unsaid when nobody said where they are.
      expect(
        (await list(
          const ProductQuery(governorate: 'BAGHDAD'),
        )).items.any((p) => p.deliveryAvailable),
        isFalse,
      );
    },
  );

  test('search finds Arabic however it is typed, in Arabic', () async {
    final j = await start();
    await j.asShopper();
    await j.container
        .read(localeControllerProvider.notifier)
        .setLocale(const Locale('ar'));
    final search = j.container.read(searchRepositoryProvider);
    Future<List<String>> find(String term) async => [
      for (final product in (await j.catalog.fetchProducts(
        query: ProductQuery(search: term),
      )).unwrap().items)
        product.id,
    ];

    expect(
      (await search.popularSearches()).unwrap(),
      isEmpty,
      reason: 'popular searches nobody made',
    );
    expect(await find('زرافة'), isEmpty);
    expect(
      await find('ساعه'),
      unorderedEquals(['p-7', 'p-49']),
      reason: 'ة typed as ه',
    );
    // Popular: what people searched for and found, and nothing else.
    expect((await search.popularSearches()).unwrap(), ['ساعه']);
    // Atlas Home's, on sale: its steam iron waits for Saba, its espresso
    // machine is a draft and its blender was turned down.
    expect(
      await find('اطلس'),
      unorderedEquals(['p-2', 'p-6', 'p-8', 'p-12']),
      reason: 'أ typed as ا',
    );
    expect(await find('عجانة'), ['p-8'], reason: 'the shadda');
    expect(
      await find('الكاميرا'),
      unorderedEquals(['p-9', 'p-43', 'p-44']),
      reason: 'ال in front',
    );
    expect(await find('٦٥'), ['p-11'], reason: 'Arabic digits');
    expect(await find('نوفا الذكي'), unorderedEquals(['p-1', 'p-7']));
    // By its category, in either language.
    const headphones = ['p-5', 'p-45', 'p-46', 'p-47'];
    expect(await find('سماعات'), unorderedEquals(headphones));
    expect(await find('headphones'), unorderedEquals(headphones));

    // The Arabic name comes back, in the results and the suggestions.
    expect(
      (await search.suggestions('ساعه')).unwrap().map((s) => s.text),
      contains('ساعة نوفا الذكية الإصدار 4'),
    );
    final feed =
        (await j.container.read(homeRepositoryProvider).fetchHomeFeed())
            .unwrap();
    final categories = feed.firstWhere(
      (section) => section.id == 's-categories',
    );
    expect(categories.title, 'تسوّق حسب القسم');
    expect(categories.categories.first.name, 'هواتف');

    // Newest first means the day it was added, not the id as text.
    final newest = (await j.catalog.fetchProducts(
      query: const ProductQuery(sort: ProductSort.newest),
    )).unwrap().items;
    expect(newest.first.id, 'p-12');

    // A store finds its own products the same way.
    await j.asStore();
    final shelf = (await j.store.products(query: 'اوديو')).unwrap().items;
    expect(shelf.map((row) => row.id), [j.product]);
  });
}

class _Journey {
  _Journey(this.container);

  final ProviderContainer container;

  /// A cheap, in-stock Nova product with no options.
  final String product =
      MockData.products.firstWhere(
            (product) =>
                (product['merchant'] as Map)['id'] == 'm-1' &&
                product['variants'] == null &&
                product['stockStatus'] != 'OUT_OF_STOCK' &&
                (product['price'] as num) <= 300000,
          )['id']
          as String;

  ApiClient get client => container.read(apiClientProvider);

  /// Home's flash sale as a shopper sees it; null with nothing on one.
  Future<HomeSection?> flashSale() async =>
      (await container.read(homeRepositoryProvider).fetchHomeFeed())
          .unwrap()
          .where((s) => s.type == HomeSectionType.flashSale)
          .firstOrNull;
  MerchantRepository get store => container.read(merchantRepositoryProvider);
  OrdersRepository get orders => container.read(ordersRepositoryProvider);
  CatalogRepository get catalog => container.read(catalogRepositoryProvider);

  Future<void> _signIn(String email) async =>
      (await container
              .read(authControllerProvider.notifier)
              .signIn(email: email, password: 'Password1'))
          .unwrap();
  Future<void> asShopper() => _signIn('shopper@saba.app');
  Future<void> asStore() => _signIn('merchant@saba.app');

  /// Buys [quantity] of [product], cash, to the Baghdad address; its id.
  Future<String> buy({int quantity = 1}) async =>
      (await tryBuy(quantity: quantity)).unwrap().orderId;

  Future<Result<PlacedOrder>> tryBuy({int quantity = 1}) => container
      .read(checkoutRepositoryProvider)
      .placeOrder(
        selection: CheckoutSelection(
          addressId: 'addr-1',
          paymentMethodId: 'pm-cod',
          buyNow: BuyNowLine(productId: product, quantity: quantity),
        ),
        idempotencyKey: 'buy-${DateTime.now().microsecondsSinceEpoch}',
      );

  /// The newest part in Nova's [status] queue.
  Future<String> storePart({String status = 'PENDING'}) async =>
      (await store.orders(status: status)).unwrap().items.first.id;

  Future<void> move(String part, List<String> steps) async {
    for (final step in steps) {
      (await store.updateOrderStatus(
        orderId: part,
        status: step,
        courier: step == 'SHIPPED' ? _driver : null,
      )).unwrap();
    }
  }

  Future<num> stock() async =>
      (await client.get<Map<String, dynamic>>(
            ApiEndpoints.product(product),
            decoder: (envelope) => envelope.dataAsMap,
          )).unwrap()['availableQuantity']
          as num;
}
