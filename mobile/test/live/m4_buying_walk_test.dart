// M4 (BACKEND_PLAN.md 8.1): buying, from the cart to delivered, with the
// app's own code against the real server. Skipped unless asked for; run in
// phases, the web checking between them:
//
//   flutter test test/live/m4_buying_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1 \
//     --dart-define=PHASE=place
//
// Store A is M2's test store, store B Nova; the shopper is the demo shopper.
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
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/addresses/domain/entities.dart';
import 'package:saba_marketplace/features/addresses/presentation/address_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/domain/entities.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart';
import 'package:saba_marketplace/features/catalog/domain/product_query.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/storefront_screen.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/reviews/presentation/rate_order_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _phase = String.fromEnvironment('PHASE', defaultValue: 'place');
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

  String say(Result<Object?> result) => result.fold(
    ok: (value) => 'OK',
    err: (Failure f) => 'ERR ${f.statusCode} "${f.message}" ${f.fieldErrors}',
  );

  Future<ProviderContainer> as(
    String? phone,
    String? email,
    String password, {
    String locale = 'en',
  }) async {
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
    final r = await c
        .read(authControllerProvider.notifier)
        .signIn(phone: phone, email: email, password: password);
    print('sign-in ${phone ?? email} ($locale): ${say(r)}');
    return c;
  }

  Future<ProviderContainer> asShopper({String locale = 'en'}) =>
      as('+9647701234567', null, 'saba12345', locale: locale);
  Future<ProviderContainer> asStoreA({String locale = 'en'}) =>
      as('+9647732172587', null, 'walkpass123', locale: locale);
  Future<ProviderContainer> asNova({String locale = 'en'}) =>
      as(null, 'merchant@saba.app', 'saba12345', locale: locale);

  Future<void> inbox(ProviderContainer c, String label, {int count = 3}) async {
    final list = await c.read(notificationsRepositoryProvider).fetch();
    for (final n in (list.valueOrNull?.items ?? const []).take(count)) {
      print(
        '$label: "${n.title}" / "${n.body}" -> ${n.targetType}:${n.targetId}',
      );
    }
  }

  String cartOf(Result<Cart> result) {
    final cart = result.valueOrNull;
    if (cart == null) return say(result);
    return [
      for (final g in cart.groups)
        '[${g.merchantName}: ${[for (final i in g.items) '${i.name}${i.variantLabel == null ? '' : ' (${i.variantLabel})'} x${i.quantity} ${i.lineTotal}']} '
            'sub=${g.subtotal} fee=${g.shippingFee} time=${g.estimatedDelivery} '
            'delivers=${g.deliversHere}]',
      'saved=${[for (final i in cart.savedForLater) i.name]}',
      'coupon=${cart.coupon?.code}:${cart.coupon?.discountAmount}'
          '${cart.coupon?.applies == false ? ' (not applying, min ${cart.coupon?.minOrderAmount})' : ''}',
      'totals: sub=${cart.totals.subtotal} ship=${cart.totals.shipping} '
          'coupon=${cart.totals.couponDiscount} total=${cart.totals.total}',
    ].join(' ');
  }

  String reviewOf(Result<CheckoutSummary> result) {
    final s = result.valueOrNull;
    if (s == null) return say(result);
    return [
      for (final g in s.groups)
        '[${g.merchantName}: sub=${g.subtotal} fee=${g.shippingFee} '
            'discount=${g.discount} due=${g.amountDue} time=${g.estimatedDelivery} '
            'delivers=${g.deliversHere}]',
      'sub=${s.subtotal} ship=${s.shipping} discount=${s.discount} total=${s.total}',
      'canPlace=${s.canPlaceOrder} warnings=${s.warnings}',
      'pay=${[for (final m in s.paymentMethods) '${m.id}:${m.isEnabled}']}',
    ].join(' ');
  }

  test('M4 phase $_phase', skip: !_live, timeout: Timeout.none, () async {
    print('API ${AppConfig.apiBaseUrl} mock=${AppConfig.useMockData}');
    final sh = await asShopper();
    final catalog = sh.read(catalogRepositoryProvider);
    final cart = sh.read(cartRepositoryProvider);
    final checkout = sh.read(checkoutRepositoryProvider);
    final orders = sh.read(ordersRepositoryProvider);

    Future<ProductSummary?> find(String words, {String? store}) async {
      for (var page = 1; page < 20; page++) {
        final list = (await catalog.fetchProducts(
          query: ProductQuery(search: store == null ? words : null),
          page: page,
        )).valueOrNull;
        if (list == null) return null;
        for (final p in list.items) {
          if (store == null ? p.name == words : p.merchantName == store) {
            return p;
          }
        }
        if (!list.hasNextPage) return null;
      }
      return null;
    }

    if (_phase == 'place') {
      // The shopper starts with nothing: no orders, no address.
      final before = (await orders.fetchOrders()).valueOrNull;
      print('orders before: ${before?.items.length}');
      final addresses = sh.read(addressRepositoryProvider);
      var saved = (await addresses.fetchAddresses()).valueOrNull ?? const [];
      print(
        'addresses: ${[for (final a in saved) '${a.id} ${a.governorate} ${a.area} default=${a.isDefault}']}',
      );
      if (!saved.any((a) => a.governorate == Governorate.baghdad)) {
        final made = await addresses.create(
          const Address(
            id: '',
            fullName: 'Saba Shopper',
            phone: '+9647701234567',
            governorate: Governorate.baghdad,
            area: 'Karrada',
            landmark: 'Near Al-Rasheed Mosque',
            street: 'Street 62, house 14',
          ),
        );
        print('address Baghdad: ${say(made)}');
        saved = (await addresses.fetchAddresses()).valueOrNull ?? const [];
      }
      final baghdad = saved.firstWhere(
        (a) => a.governorate == Governorate.baghdad,
      );
      if (!baghdad.isDefault) {
        print('default: ${say(await addresses.setDefault(baghdad.id))}');
      }
      sh.invalidate(addressListProvider);
      final selection = CheckoutSelection(addressId: baghdad.id);

      // An empty cart to start from.
      final old = (await cart.fetchCart()).valueOrNull;
      for (final i in [
        ...?old?.groups.expand((g) => g.items),
        ...?old?.savedForLater,
      ]) {
        await cart.removeItem(i.id);
      }
      if (old?.coupon != null) await cart.removeCoupon();

      // 1. Three stores; one does not deliver to Baghdad.
      final phone = await find('M3 Phone');
      final charger = await find('Nova Fast Charger 65W');
      final headphones = await find('Kite Audio Studio Headphones');
      final camera = await find('Orbit Mirrorless Camera');
      final zakho = await find('', store: 'Zakho Mobile');
      print(
        'products: phone=${phone?.id} charger=${charger?.id}:${charger?.price} '
        'headphones=${headphones?.id}:${headphones?.price} '
        'camera=${camera?.id}:${camera?.price} zakho=${zakho?.id} ${zakho?.name}:${zakho?.price}',
      );
      final page = (await catalog.fetchProduct(phone!.id)).unwrap();
      final white = page.variants.firstWhere(
        (v) => (v.availableQuantity ?? 0) > 0,
      );
      print(
        '1 M3 Phone options: ${[for (final v in page.variants) '${v.id} ${v.options} ${v.price} ${v.availableQuantity}']}',
      );
      print(
        '1 add M3 Phone ${white.options}: ${say(await cart.addItem(productId: phone.id, variantId: white.id))}',
      );
      print(
        '1 add charger: ${say(await cart.addItem(productId: charger!.id))}',
      );
      final withZakho = await cart.addItem(productId: zakho!.id);
      print('1 add ${zakho.name}: ${say(withZakho)}');
      print('1 cart: ${cartOf(withZakho)}');
      print('1 review: ${reviewOf(await checkout.review(selection))}');
      final ar = await asShopper(locale: 'ar');
      print(
        '12 ar cart: ${cartOf(await ar.read(cartRepositoryProvider).fetchCart())}',
      );
      print(
        '12 ar review: ${reviewOf(await ar.read(checkoutRepositoryProvider).review(selection))}',
      );
      final blocked = await checkout.placeOrder(
        selection: selection,
        idempotencyKey: 'm4-zakho-${DateTime.now().millisecondsSinceEpoch}',
      );
      print(
        '1 place with Zakho in: ${say(blocked)} ${blocked.valueOrNull?.orderNumber ?? ''}',
      );
      if (blocked.valueOrNull case final placed?) {
        print(
          '1 !! placed; cancelling: ${say(await orders.cancelOrder(orderId: placed.orderId, reason: 'ORDERED_BY_MISTAKE'))}',
        );
      }
      final zakhoLine = withZakho.valueOrNull!.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.productId == zakho.id);
      print('1 take Zakho out: ${cartOf(await cart.removeItem(zakhoLine.id))}');

      // Saved for later, and back.
      final chargerLine = (await cart.fetchCart())
          .unwrap()
          .groups
          .expand((g) => g.items)
          .firstWhere((i) => i.productId == charger.id);
      print(
        '1 save for later: ${cartOf(await cart.saveForLater(chargerLine.id))}',
      );
      final savedLine = (await cart.fetchCart())
          .unwrap()
          .savedForLater
          .firstWhere((i) => i.productId == charger.id);
      print('1 move back: ${cartOf(await cart.moveToCart(savedLine.id))}');

      // 2. Coupons: each store's own goods, and its minimum.
      final arCart = ar.read(cartRepositoryProvider);
      print(
        '2 NOVA10 under 100,000: ${cartOf(await cart.applyCoupon('NOVA10'))}',
      );
      print('12 ar NOVA10: ${cartOf(await arCart.applyCoupon('NOVA10'))}');
      await cart.removeCoupon();
      print(
        '2 add headphones: ${say(await cart.addItem(productId: headphones!.id))}',
      );
      print('2 NOVA10: ${cartOf(await cart.applyCoupon('NOVA10'))}');
      print('2 NOVA10 review: ${reviewOf(await checkout.review(selection))}');
      print('2 WEEKEND15: ${cartOf(await cart.applyCoupon('WEEKEND15'))}');
      print(
        '12 ar WEEKEND15: ${cartOf(await arCart.applyCoupon('WEEKEND15'))}',
      );
      print('2 ATLAS5000: ${cartOf(await cart.applyCoupon('ATLAS5000'))}');
      print(
        '12 ar ATLAS5000: ${cartOf(await arCart.applyCoupon('ATLAS5000'))}',
      );
      final now = (await cart.fetchCart()).unwrap();
      if (now.coupon?.code != 'NOVA10') {
        print('2 NOVA10 again: ${cartOf(await cart.applyCoupon('NOVA10'))}');
      }

      // 3. The first-order limit.
      final withCamera = await cart.addItem(productId: camera!.id);
      print('3 add camera: ${cartOf(withCamera)}');
      print('3 review: ${reviewOf(await checkout.review(selection))}');
      print(
        '12 ar review: ${reviewOf(await ar.read(checkoutRepositoryProvider).review(selection))}',
      );
      final over = await checkout.placeOrder(
        selection: selection,
        idempotencyKey: 'm4-over-${DateTime.now().millisecondsSinceEpoch}',
      );
      print('3 place over the limit: ${say(over)}');
      if (over.valueOrNull case final placed?) {
        print(
          '3 !! placed; cancelling: ${say(await orders.cancelOrder(orderId: placed.orderId, reason: 'ORDERED_BY_MISTAKE'))}',
        );
      }
      final cameraLine = (await cart.fetchCart())
          .unwrap()
          .groups
          .expand((g) => g.items)
          .firstWhere((i) => i.productId == camera.id);
      print(
        '3 take camera out: ${cartOf(await cart.removeItem(cameraLine.id))}',
      );

      // 4. Placed, through the app's checkout.
      final flow = sh.read(checkoutControllerProvider.notifier);
      await flow.selectAddress(baghdad.id);
      final review = sh.read(checkoutControllerProvider).summary;
      print(
        '4 review: ${review == null ? 'none ${sh.read(checkoutControllerProvider).failure?.message}' : reviewOf(Result.ok(review))}',
      );
      final chosen = sh.read(checkoutControllerProvider).selection;
      final key = 'm4-order-${DateTime.now().millisecondsSinceEpoch}';
      final placed = await checkout.placeOrder(
        selection: chosen,
        idempotencyKey: key,
      );
      print(
        '4 place: ${say(placed)} ${placed.valueOrNull?.orderNumber} ${placed.valueOrNull?.orderId}',
      );
      final again = await checkout.placeOrder(
        selection: chosen,
        idempotencyKey: key,
      );
      print(
        '4 same key again: ${say(again)} ${again.valueOrNull?.orderNumber} '
        '${again.valueOrNull?.orderId == placed.valueOrNull?.orderId ? 'SAME order' : 'DIFFERENT'}',
      );
      print(
        '4 orders now: ${(await orders.fetchOrders()).valueOrNull?.items.length}',
      );
      print('4 cart after: ${cartOf(await cart.fetchCart())}');
      final order = (await orders.fetchOrder(
        placed.valueOrNull!.orderId,
      )).unwrap();
      print(
        '4 order ${order.orderNumber}: ${order.status.name} pay=${order.paymentStatus.name} '
        'sub=${order.subtotal} ship=${order.shipping} discount=${order.discount} '
        'total=${order.total} cod=${order.isCashOnDelivery} canCancel=${order.canCancel}',
      );
      print(
        '4 items: ${[for (final i in order.items) '${i.merchantName}: ${i.productName}${i.variantLabel == null ? '' : ' (${i.variantLabel})'} x${i.quantity} ${i.lineTotal} ${i.status.name}']}',
      );
      print(
        '4 parts: ${[for (final e in order.parts.entries) '${e.key} due=${e.value.amountDue} time=${e.value.deliveryTime}']}',
      );
      await inbox(sh, '4 shopper', count: 1);
      await inbox(await asStoreA(), '4 store A', count: 1);
      await inbox(await asNova(), '4 Nova', count: 1);
      await inbox(await asStoreA(locale: 'ar'), '12 ar store A', count: 1);
    }

    // Step 1 again with a Zakho product in stock: the first run's Zagros Z10
    // had run out, so it was refused for that instead.
    if (_phase == 'zakho') {
      final saved = (await sh.read(addressRepositoryProvider).fetchAddresses())
          .unwrap();
      final selection = CheckoutSelection(
        addressId: saved.firstWhere((a) => a.isDefault).id,
      );
      final bank = (await find('Tigris Power Bank 20000mAh'))!;
      print('1 ${bank.name} ${bank.merchantName} ${bank.stockStatus.name}');
      final added = await cart.addItem(productId: bank.id);
      print('1 cart: ${cartOf(added)}');
      print('1 review: ${reviewOf(await checkout.review(selection))}');
      final ar = await asShopper(locale: 'ar');
      print(
        '12 ar review: ${reviewOf(await ar.read(checkoutRepositoryProvider).review(selection))}',
      );
      final blocked = await checkout.placeOrder(
        selection: selection,
        idempotencyKey: 'm4-zakho-${DateTime.now().millisecondsSinceEpoch}',
      );
      print('1 place: ${say(blocked)}');
      if (blocked.valueOrNull case final placed?) {
        print(
          '1 !! placed; cancelling: ${say(await orders.cancelOrder(orderId: placed.orderId, reason: 'ORDERED_BY_MISTAKE'))}',
        );
      }
      for (final i in (await cart.fetchCart()).unwrap().groups.expand(
        (g) => g.items,
      )) {
        print('1 take out: ${cartOf(await cart.removeItem(i.id))}');
      }
    }

    if (_phase == 'deliver') {
      final orderId = (await orders.fetchOrders()).unwrap().items.first.id;
      Future<void> shopperSees(String label) async {
        final o = (await orders.fetchOrder(orderId)).unwrap();
        print(
          '$label shopper: ${o.orderNumber} ${o.status.name} pay=${o.paymentStatus.name} '
          'canCancel=${o.canCancel} items=${[for (final i in o.items) '${i.merchantName}:${i.status.name}']} '
          'drivers=${[for (final e in o.parts.entries) '${e.key}:${e.value.courierName}/${e.value.courierPhone}']}',
        );
      }

      await shopperSees('5 start');

      // 5 and 6. Each store moves its own part, one step at a time.
      for (final (step, name, open) in [
        ('5', 'store A', asStoreA),
        ('6', 'Nova', asNova),
      ]) {
        final s = await open();
        final repo = s.read(merchantRepositoryProvider);
        final number = (await orders.fetchOrder(orderId)).unwrap().orderNumber;
        final waiting = (await repo.orders(status: 'PENDING')).unwrap().items;
        final part = waiting.where((r) => r.orderNumber == number).firstOrNull;
        print(
          '$step $name "To confirm": ${part == null ? 'ABSENT' : 'part ${part.id} ${part.status} ${part.total} ${part.customerName}'}',
        );
        if (part == null) continue;
        print('$step $name counts: ${(await repo.orderCounts()).valueOrNull}');
        Future<Result<void>> move(String status, [Courier? courier]) =>
            repo.updateOrderStatus(
              orderId: part.id,
              status: status,
              courier: courier,
            );

        print(
          '$step $name jump to SHIPPED: ${say(await move('SHIPPED', const Courier(name: 'Ali Hassan', phone: '+9647701112222')))}',
        );
        print('$step $name confirm: ${say(await move('CONFIRMED'))}');
        await shopperSees('$step after confirm');
        print('$step $name jump to DELIVERED: ${say(await move('DELIVERED'))}');
        print('$step $name prepare: ${say(await move('PROCESSING'))}');
        await shopperSees('$step after prepare');
        print('$step $name ship, no driver: ${say(await move('SHIPPED'))}');
        print(
          '$step $name ship, no name: ${say(await move('SHIPPED', const Courier(name: '', phone: '+9647701112222')))}',
        );
        print(
          '$step $name ship, bad phone: ${say(await move('SHIPPED', const Courier(name: 'Ali Hassan', phone: '0123')))}',
        );
        if (step == '5') {
          final ar = (await asStoreA(
            locale: 'ar',
          )).read(merchantRepositoryProvider);
          print(
            '12 ar ship, no name: ${say(await ar.updateOrderStatus(
              orderId: part.id,
              status: 'SHIPPED',
              courier: const Courier(name: '', phone: '+9647701112222'),
            ))}',
          );
          print(
            '12 ar ship, bad phone: ${say(await ar.updateOrderStatus(
              orderId: part.id,
              status: 'SHIPPED',
              courier: const Courier(name: 'Ali Hassan', phone: '0123'),
            ))}',
          );
        }
        final driver = step == '5'
            ? const Courier(name: 'Ali Hassan', phone: '+9647701112222')
            : const Courier(name: 'Omar Saleh', phone: '07709998877');
        print(
          '$step $name ship with ${driver.name} ${driver.phone}: ${say(await move('SHIPPED', driver))}',
        );
        await shopperSees('$step after ship');
        final detail = (await repo.order(part.id)).valueOrNull;
        print(
          '$step $name page: courier=${detail?.courier?.name}/${detail?.courier?.phone}',
        );
        print('$step $name deliver: ${say(await move('DELIVERED'))}');
        await shopperSees('$step after deliver');
        print('$step $name counts: ${(await repo.orderCounts()).valueOrNull}');
      }

      // 7. Received, rated, and the invoice.
      final o = (await orders.fetchOrder(orderId)).unwrap();
      for (final id in o.parts.keys) {
        final r = await orders.confirmReceived(
          orderId: orderId,
          merchantId: id,
          received: true,
        );
        print(
          '7 received from $id: ${say(r)} -> ${r.valueOrNull?.parts[id]?.received}',
        );
      }
      Future<String> due() async {
        final d = await sh.refresh(orderToRateProvider.future);
        return d == null
            ? 'nothing to rate'
            : '${d.orderNumber} ${[for (final s in d.stores) '${s.id}:${s.storeName}']}';
      }

      print('7 rating due: ${await due()}');
      final rate = sh.read(rateOrderProvider);
      for (var i = 1; i <= 2; i++) {
        print(
          '7 not now #$i: ${await rate.notNow(orderId) ?? 'OK'} -> ${await due()}',
        );
      }
      print(
        '7 rate: ${await rate.rate(orderId: orderId, stars: {for (final id in o.parts.keys) id: id == '15' ? 5 : 4}, comment: 'M4 walk: both came on time.') ?? 'OK'} -> ${await due()}',
      );
      final invoice = (await orders.fetchInvoice(orderId));
      final inv = invoice.valueOrNull;
      print(
        '7 invoice: ${say(invoice)} ${inv?.invoiceNumber} sub=${inv?.subtotal} ship=${inv?.shipping} '
        'discount=${inv?.discount} total=${inv?.total} pay=${inv?.paymentStatus.name} '
        'lines=${[for (final l in inv?.lines ?? const []) '${l.merchantName}: ${l.description} x${l.quantity} ${l.total}']}',
      );
      final after = (await orders.fetchOrder(orderId)).unwrap();
      print(
        '7 order: sub=${after.subtotal} ship=${after.shipping} discount=${after.discount} total=${after.total} '
        '${after.status.name} pay=${after.paymentStatus.name}',
      );
      for (final id in ['15', '1']) {
        final page = await sh.read(merchantStoreProvider(id).future);
        print(
          '7 store $id page: ${page.storeName} rating=${page.rating} reviews=${page.reviewCount}',
        );
      }
      print(
        '7 timeline: ${[for (final t in after.timeline) '${t.status.name}${t.storeName == null ? '' : '@${t.storeName}'}']}',
      );
      await inbox(sh, '7 shopper', count: 8);
      await inbox(await asShopper(locale: 'ar'), '12 ar shopper', count: 8);
    }

    // 8, 9 and 10: M3 Phone alone, cancelled, declined, refused at the door;
    // its stock back each time.
    if (_phase == 'cancel') {
      final phone = (await find('M3 Phone'))!;
      final white = (await catalog.fetchProduct(
        phone.id,
      )).unwrap().variants.firstWhere((v) => (v.availableQuantity ?? 0) > 0);
      final storeA = await asStoreA();
      final repo = storeA.read(merchantRepositoryProvider);
      Future<String> stock() async {
        final shelf = (await repo.inventory()).unwrap().items.where(
          (r) => r.productId == phone.id,
        );
        final page = (await catalog.fetchProduct(phone.id)).valueOrNull;
        return 'store ${[for (final r in shelf) '${r.variantLabel}:${r.available}']} '
            'shopper ${[for (final v in page?.variants ?? const <ProductVariant>[]) '${v.options.values.join()}:${v.availableQuantity}']}';
      }

      final address =
          (await sh.read(addressRepositoryProvider).fetchAddresses())
              .unwrap()
              .firstWhere((a) => a.isDefault);
      Future<(String, String)> placeOne(String step) async {
        print(
          '$step add M3 Phone: ${say(await cart.addItem(productId: phone.id, variantId: white.id))}',
        );
        final flow = sh.read(checkoutControllerProvider.notifier);
        await flow.selectAddress(address.id);
        final placed = (await flow.placeOrder()).unwrap();
        final part = (await repo.orders(status: 'PENDING'))
            .unwrap()
            .items
            .firstWhere((r) => r.orderNumber == placed.orderNumber);
        print(
          '$step placed ${placed.orderNumber} (store part ${part.id}); stock ${await stock()}',
        );
        return (placed.orderId, part.id);
      }

      Future<void> shopperSees(String label, String id) async {
        final o = (await orders.fetchOrder(id)).unwrap();
        print(
          '$label shopper: ${o.orderNumber} ${o.status.name} pay=${o.paymentStatus.name} '
          'total=${o.total} due=${[for (final p in o.parts.values) p.amountDue]} canCancel=${o.canCancel} '
          'last=${o.timeline.lastOrNull?.status.name}:${o.timeline.lastOrNull?.reasonCode}',
        );
      }

      print('8 stock at start: ${await stock()}');

      // 8. Cancelled by the shopper once the store has confirmed.
      final (cancelId, cancelPart) = await placeOne('8');
      print(
        '8 store confirms: ${say(await repo.updateOrderStatus(orderId: cancelPart, status: 'CONFIRMED'))}',
      );
      await shopperSees('8 confirmed', cancelId);
      print(
        '8 cancel with no reason: ${say(await orders.cancelOrder(orderId: cancelId, reason: ''))}',
      );
      print(
        '8 cancel CHANGED_MIND: ${say(await orders.cancelOrder(orderId: cancelId, reason: 'CHANGED_MIND', note: 'Bought one in a shop.'))}',
      );
      await shopperSees('8 cancelled', cancelId);
      print('8 stock after: ${await stock()}');
      await inbox(storeA, '8 store A', count: 1);
      print(
        '8 store A part: ${(await repo.order(cancelPart)).valueOrNull?.row.status}',
      );

      // 9. Declined by the store, with a reason from the list.
      final (declineId, declinePart) = await placeOne('9');
      print(
        '9 decline OUT_OF_STOCK: ${say(await repo.updateOrderStatus(orderId: declinePart, status: 'CANCELLED', reason: 'OUT_OF_STOCK'))}',
      );
      await shopperSees('9 declined', declineId);
      print('9 stock after: ${await stock()}');
      await inbox(sh, '9 shopper', count: 1);

      // 10. Refused at the door; on the way, the shopper can no longer cancel.
      final (refusedId, refusedPart) = await placeOne('10');
      for (final status in ['CONFIRMED', 'PROCESSING']) {
        print(
          '10 $status: ${say(await repo.updateOrderStatus(orderId: refusedPart, status: status))}',
        );
      }
      await shopperSees('10 preparing', refusedId);
      print(
        '8 cancel past CONFIRMED: ${say(await orders.cancelOrder(orderId: refusedId, reason: 'CHANGED_MIND'))}',
      );
      final ar = await asShopper(locale: 'ar');
      print(
        '12 ar cancel past CONFIRMED: ${say(await ar.read(ordersRepositoryProvider).cancelOrder(orderId: refusedId, reason: 'CHANGED_MIND'))}',
      );
      print(
        '10 REFUSED before shipping: ${say(await repo.updateOrderStatus(orderId: refusedPart, status: 'REFUSED'))}',
      );
      print(
        '10 SHIPPED: ${say(await repo.updateOrderStatus(
          orderId: refusedPart,
          status: 'SHIPPED',
          courier: const Courier(name: 'Ali Hassan', phone: '+9647701112222'),
        ))}',
      );
      print(
        '10 REFUSED: ${say(await repo.updateOrderStatus(orderId: refusedPart, status: 'REFUSED'))}',
      );
      await shopperSees('10 refused', refusedId);
      print('10 stock after: ${await stock()}');
      await inbox(sh, '10 shopper', count: 1);
      await inbox(ar, '12 ar shopper', count: 3);
      await inbox(await asStoreA(locale: 'ar'), '12 ar store A', count: 3);

      // The backend's 2ef1cd4: nothing that has run out goes in the cart.
      final gone = await find('Zagros Z10 Smartphone');
      print(
        'fix: add Zagros Z10 (run out): ${say(await cart.addItem(productId: gone!.id))}',
      );
      print(
        'fix ar: ${say(await ar.read(cartRepositoryProvider).addItem(productId: gone.id))}',
      );
      print('cart at the end: ${cartOf(await cart.fetchCart())}');
    }

    // Step 7's sheet: asked only while a delivered part is unanswered, so a
    // second, small order, delivered and left unanswered; "Not now" three
    // times lets it go.
    if (_phase == 'rating') {
      final charger = (await find('Nova Fast Charger 65W'))!;
      print(
        '7b add charger: ${say(await cart.addItem(productId: charger.id))}',
      );
      final flow = sh.read(checkoutControllerProvider.notifier);
      final address =
          (await sh.read(addressRepositoryProvider).fetchAddresses())
              .unwrap()
              .firstWhere((a) => a.isDefault);
      await flow.selectAddress(address.id);
      final placed = await flow.placeOrder();
      print(
        '7b place: ${say(placed)} ${placed.valueOrNull?.orderNumber} '
        'total=${sh.read(checkoutControllerProvider).summary?.total}',
      );
      final orderId = placed.valueOrNull!.orderId;
      final nova = (await asNova()).read(merchantRepositoryProvider);
      final part = (await nova.orders(status: 'PENDING'))
          .unwrap()
          .items
          .firstWhere((r) => r.orderNumber == placed.valueOrNull!.orderNumber);
      for (final status in [
        'CONFIRMED',
        'PROCESSING',
        'SHIPPED',
        'DELIVERED',
      ]) {
        print(
          '7b Nova $status: ${say(await nova.updateOrderStatus(
            orderId: part.id,
            status: status,
            courier: status == 'SHIPPED' ? const Courier(name: 'Omar Saleh', phone: '07709998877') : null,
          ))}',
        );
      }
      Future<String> due() async {
        final d = await sh.refresh(orderToRateProvider.future);
        return d == null
            ? 'nothing to rate'
            : '${d.orderNumber} ${[for (final s in d.stores) '${s.id}:${s.storeName}']}';
      }

      print('7b rating due: ${await due()}');
      final rate = sh.read(rateOrderProvider);
      for (var i = 1; i <= 3; i++) {
        print(
          '7b not now #$i: ${await rate.notNow(orderId) ?? 'OK'} -> ${await due()}',
        );
      }
      final o = (await orders.fetchOrder(orderId)).unwrap();
      print(
        '7b order ${o.orderNumber}: ${o.status.name} pay=${o.paymentStatus.name} '
        'received=${[for (final p in o.parts.values) p.received]}',
      );
    }
  });

  // 11 and 12 on the real screens: the store's order tabs with their counts,
  // and an order's page with the shopper's name, address and phone.
  for (final locale in ['en', 'ar']) {
    testWidgets(
      "M4 the store's orders ($locale)",
      skip: !_live || _phase != 'storeorders',
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
        final c = (await tester.runAsync(() => asStoreA(locale: locale)))!;
        final repo = c.read(merchantRepositoryProvider);
        final counts = (await tester.runAsync(repo.orderCounts))!;
        final all = (await tester.runAsync(repo.orders))!;
        print('11 $locale counts: ${counts.valueOrNull}');
        print(
          '11 $locale all orders: ${[for (final r in all.valueOrNull?.items ?? const <MerchantOrderRow>[]) '${r.orderNumber}:${r.status}']}',
        );
        Future<void> settle() async {
          for (var i = 0; i < 12; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        List<String> texts() => [
          for (final w in tester.widgetList<Text>(find.byType(Text, skipOffstage: false))) ?w.data,
        ];

        await tester.pumpWidget(
          UncontrolledProviderScope(container: c, child: const SabaApp()),
        );
        await settle();
        c.read(appRouterProvider).go(AppRoutes.merchantOrders);
        await settle();
        print(
          '11 $locale tabs: ${texts().where((t) => t.contains(' · ')).toList()}',
        );
        final delivered = all.valueOrNull!.items.firstWhere(
          (r) => r.status == 'DELIVERED',
        );
        c
            .read(appRouterProvider)
            .go(AppRoutes.merchantOrderDetailPath(delivered.id));
        await settle();
        final page = texts().join(' | ');
        for (final want in [
          'Saba Shopper',
          'Karrada',
          'Near Al-Rasheed Mosque',
          '+964 770 123 4567',
          'Ali Hassan',
        ]) {
          print(
            '11 $locale page ${delivered.orderNumber} "$want": ${page.contains(want) ? 'shown' : 'MISSING'}',
          );
        }
        await tester.runAsync(
          () => c.read(authControllerProvider.notifier).signOut(),
        );
        await tester.pumpWidget(const SizedBox());
        await settle();
      },
    );
  }
}
