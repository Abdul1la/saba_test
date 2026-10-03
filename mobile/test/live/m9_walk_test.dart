// M9: the screens no round walked, against the real server. Skipped unless
// asked for:
//
//   flutter test test/live/m9_walk_test.dart \
//     --dart-define=LIVE=true --dart-define=USE_MOCK_DATA=false \
//     --dart-define=API_BASE_URL=http://localhost:3000/api/v1 \
//     --dart-define=PHASE=report|removed|coupons|buynow
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/config/app_config.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/features/addresses/domain/entities.dart';
import 'package:saba_marketplace/features/addresses/presentation/address_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/domain/entities.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/checkout/domain/entities.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/storefront_screen.dart';
import 'package:saba_marketplace/features/reviews/presentation/reviews_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE');
const _phase = String.fromEnvironment('PHASE', defaultValue: 'report');
const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _m2Store = '15';
const _nova = '1';

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

  // One sign-in per account and language: 10 per phone in 15 minutes.
  final signedIn = <String, ProviderContainer>{};
  Future<ProviderContainer> as(
    String phone,
    String password, {
    String locale = 'en',
  }) async {
    final key = '$phone|$locale';
    if (signedIn[key] case final c?) return c;
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
        .signIn(phone: phone, password: password);
    print('sign-in $phone ($locale): ${say(r)}');
    if (r.isOk) signedIn[key] = c;
    return c;
  }

  Future<ProviderContainer> asWalk({String locale = 'en'}) =>
      as('+9647731006565', 'walkpass123', locale: locale);

  Future<void> reviewsOf(
    ProviderContainer c,
    String label,
    String storeId,
  ) async {
    final list =
        (await c.read(reviewsRepositoryProvider).fetchMerchantReviews(storeId))
            .unwrap()
            .items;
    print(
      '$label reviews of $storeId: ${[for (final r in list) '${r.id} ${r.rating}* ${r.authorName} ${r.createdAt.toLocal().toString().substring(0, 16)}']}',
    );
    final page = await c.read(merchantStoreProvider(storeId).future);
    print(
      '$label store $storeId: rating=${page.rating} reviews=${page.reviewCount}',
    );
  }

  test('M9 phase $_phase', skip: !_live, timeout: Timeout.none, () async {
    print('API ${AppConfig.apiBaseUrl} mock=${AppConfig.useMockData}');

    // 2. Reporting a review.
    if (_phase == 'report') {
      final walk = await asWalk();
      final repo = walk.read(reviewsRepositoryProvider);
      await reviewsOf(walk, '2', _m2Store);
      final amina = (await repo.fetchMerchantReviews(_m2Store))
          .unwrap()
          .items
          .firstWhere((r) => (r.authorName ?? '').contains('Amina'));
      print(
        '2 no reason: ${say(await repo.reportReview(reviewId: amina.id, reason: ''))}',
      );
      print(
        '2 report ${amina.id} OFFENSIVE: ${say(await repo.reportReview(reviewId: amina.id, reason: 'OFFENSIVE', description: 'M9: rude words about the store owner.'))}',
      );
      print(
        '2 the same shopper again: ${say(await repo.reportReview(reviewId: amina.id, reason: 'SPAM', description: 'M9: a second report by the same shopper.'))}',
      );
      final ar = (await asWalk(locale: 'ar')).read(reviewsRepositoryProvider);
      print(
        '4 ar a reason not on the list: ${say(await ar.reportReview(reviewId: amina.id, reason: 'RUDE'))}',
      );

      // The web's dismiss check: a second report, on a review that stays.
      final novas = (await repo.fetchMerchantReviews(_nova)).unwrap().items;
      final other = novas.firstWhere(
        (r) => !(r.authorName ?? '').contains('Amina'),
      );
      print(
        '2 report Nova\'s ${other.id} (${other.authorName}) MISLEADING: ${say(await repo.reportReview(reviewId: other.id, reason: 'MISLEADING', description: 'M9: for the web to dismiss; the review stays.'))}',
      );
      print('2 reported: ${amina.id} (M2 Store) and ${other.id} (Nova)');
    }

    // 2, after Saba removed it.
    if (_phase == 'removed') {
      final walk = await asWalk();
      await reviewsOf(walk, '2 after', _m2Store);
      await reviewsOf(walk, '2 after', _nova);
      const removed = String.fromEnvironment('REVIEW');
      print(
        '2 report the removed one again: ${say(await walk.read(reviewsRepositoryProvider).reportReview(reviewId: removed, reason: 'SPAM'))}',
      );
    }

    // 1. The store's coupons.
    if (_phase == 'coupons') {
      final m2 = await as('+9647732172587', 'walkpass123');
      final repo = m2.read(merchantRepositoryProvider);
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final end = DateTime(2026, 10, 31, 23, 59, 59);
      MerchantCoupon coupon(
        String code, {
        bool percent = false,
        num value = 5000,
        String id = '',
        int? limit = 5,
        int used = 0,
      }) => MerchantCoupon(
        id: id,
        code: code,
        isPercentage: percent,
        value: value,
        startsAt: start,
        endsAt: end,
        minOrderAmount: 100000,
        usageLimit: limit,
        usedCount: used,
        isActive: true,
      );

      // Each refusal; stop at once if one of them is taken.
      for (final (label, c) in [
        ('NOVA10, taken', coupon('NOVA10')),
        ('12,100 off', coupon('M9ODD', value: 12100)),
        ('95%', coupon('M9PCT', percent: true, value: 95)),
      ]) {
        final r = await repo.saveCoupon(c);
        print('1 refused? $label: ${say(r)}');
        if (r.isOk) {
          print('1 !! accepted; stopping');
          return;
        }
      }
      final arRepo = (await as(
        '+9647732172587',
        'walkpass123',
        locale: 'ar',
      )).read(merchantRepositoryProvider);
      for (final (label, c) in [
        ('NOVA10', coupon('NOVA10')),
        ('12,100', coupon('M9ODD', value: 12100)),
        ('95%', coupon('M9PCT', percent: true, value: 95)),
      ]) {
        print('4 ar $label: ${say(await arRepo.saveCoupon(c))}');
      }

      final made = await repo.saveCoupon(coupon('M9SAVE5000'));
      print('1 create M9SAVE5000: ${say(made)}');
      if (made.isErr) return;
      Future<MerchantCoupon> mine() async => (await repo.coupons())
          .unwrap()
          .firstWhere((c) => c.code == 'M9SAVE5000');
      final saved = await mine();
      print(
        '1 read back: ${saved.id} fixed=${!saved.isPercentage} ${saved.value} min=${saved.minOrderAmount} '
        'limit=${saved.usageLimit} used=${saved.usedCount} active=${saved.isActive} '
        'starts=${saved.startsAt.toUtc().toIso8601String()} (${saved.startsAt.toLocal()}) '
        'ends=${saved.endsAt?.toUtc().toIso8601String()} (${saved.endsAt?.toLocal()})',
      );

      // A shopper: Nova's charger and the M2 store's phone.
      final amina = await as('+9647701234567', 'saba12345');
      final cart = amina.read(cartRepositoryProvider);
      final old = (await cart.fetchCart()).unwrap();
      for (final i in [
        ...old.groups.expand((g) => g.items),
        ...old.savedForLater,
      ]) {
        await cart.removeItem(i.id);
      }
      if (old.coupon != null) await cart.removeCoupon();
      await cart.addItem(productId: '57', variantId: '66');
      await cart.addItem(productId: '11');
      final applied = await cart.applyCoupon('M9SAVE5000');
      print(
        '1 apply: ${say(applied)} coupon=${applied.valueOrNull?.coupon?.code}:${applied.valueOrNull?.coupon?.discountAmount} total=${applied.valueOrNull?.totals.total}',
      );
      final address =
          (await amina.read(addressRepositoryProvider).fetchAddresses())
              .unwrap()
              .firstWhere((a) => a.isDefault);
      final review =
          (await amina
                  .read(checkoutRepositoryProvider)
                  .review(CheckoutSelection(addressId: address.id)))
              .unwrap();
      print(
        '1 review: ${[for (final g in review.groups) '${g.merchantName}: sub=${g.subtotal} fee=${g.shippingFee} discount=${g.discount} due=${g.amountDue}']} total=${review.total}',
      );

      // Paused: it can't be applied.
      await cart.removeCoupon();
      print(
        '1 pause: ${say(await repo.setCouponActive(saved.id, isActive: false))}',
      );
      print(
        '1 apply while paused: ${say(await cart.applyCoupon('M9SAVE5000'))}',
      );
      print(
        '1 resume: ${say(await repo.setCouponActive(saved.id, isActive: true))}',
      );
      print('1 apply again: ${say(await cart.applyCoupon('M9SAVE5000'))}');

      // Used once.
      final flow = amina.read(checkoutControllerProvider.notifier);
      await flow.selectAddress(address.id);
      final placed = await flow.placeOrder();
      print(
        '1 order with it: ${say(placed)} ${placed.valueOrNull?.orderNumber}',
      );
      if (placed.isErr) return;
      final orderId = placed.valueOrNull!.orderId;
      final order =
          (await amina.read(ordersRepositoryProvider).fetchOrder(orderId))
              .unwrap();
      print(
        '1 order: sub=${order.subtotal} ship=${order.shipping} discount=${order.discount} total=${order.total} due=${order.dueByStore}',
      );
      final used = await mine();
      print('1 used now: ${used.usedCount}');
      print(
        '1 limit below its uses: ${say(await repo.saveCoupon(coupon('M9SAVE5000', id: used.id, limit: 0, used: used.usedCount)))}',
      );
      final edited = await repo.saveCoupon(
        coupon('M9SAVE5000', id: used.id, value: 5500, used: used.usedCount),
      );
      final after = await mine();
      print(
        '1 edit to 5,500: ${say(edited)} -> value=${after.value} used=${after.usedCount} limit=${after.usageLimit}',
      );

      // Deleted: the order keeps its code.
      print('1 delete: ${say(await repo.deleteCoupon(used.id))}');
      print(
        '1 still listed: ${(await repo.coupons()).unwrap().any((c) => c.code == 'M9SAVE5000')}',
      );
      final raw = await amina
          .read(apiClientProvider)
          .get<Map<String, dynamic>>(
            '/orders/$orderId',
            decoder: (e) => e.dataAsMap,
          );
      final json = raw.valueOrNull ?? const <String, dynamic>{};
      print(
        '1 the order after the delete: couponCode=${json['couponCode']} discount=${json['discount']} '
        'parts=${[for (final p in (json['storeParts'] as List? ?? const [])) '${(p as Map)['merchantId'] ?? p['storeId']}:${p['couponCode']}:${p['discount']}']}',
      );

      // Put things back: the order cancelled.
      print(
        '1 cancel the order: ${say(await amina.read(ordersRepositoryProvider).cancelOrder(orderId: orderId, reason: 'ORDERED_BY_MISTAKE'))}',
      );
    }

    // 3. Buy now.
    if (_phase == 'buynow') {
      final walk = await asWalk();
      final orders = walk.read(ordersRepositoryProvider);
      print(
        "3 Walk Shopper's orders: ${[for (final o in (await orders.fetchOrders()).unwrap().items) '${o.orderNumber}:${o.status.name}']}",
      );
      final book = walk.read(addressRepositoryProvider);
      var saved = (await book.fetchAddresses()).unwrap();
      print(
        '3 addresses: ${[for (final a in saved) '${a.id} ${a.governorate} ${a.area} default=${a.isDefault}']}',
      );
      if (saved.isEmpty) {
        print(
          '3 add a Baghdad address: ${say(await book.create(const Address(id: '', fullName: 'Walk Shopper', phone: '+9647731006565', governorate: Governorate.baghdad, area: 'Karrada', landmark: 'Near the mosque')))}',
        );
        saved = (await book.fetchAddresses()).unwrap();
      }
      final address = saved.firstWhere(
        (a) => a.isDefault,
        orElse: () => saved.first,
      );
      print('3 address: ${address.governorate} ${address.area}');
      final cart = walk.read(cartRepositoryProvider);
      final old = (await cart.fetchCart()).unwrap();
      for (final i in [
        ...old.groups.expand((g) => g.items),
        ...old.savedForLater,
      ]) {
        await cart.removeItem(i.id);
      }
      if (old.coupon != null) await cart.removeCoupon();
      // A cart with its own coupon, which Buy now must leave alone.
      await cart.addItem(productId: '5');
      final before = await cart.applyCoupon('NOVA10');
      String cartOf(Cart c) =>
          '${[for (final i in c.groups.expand((g) => g.items)) '${i.name} x${i.quantity}']} coupon=${c.coupon?.code}:${c.coupon?.discountAmount} total=${c.totals.total}';
      print(
        '3 cart before: ${before.valueOrNull == null ? say(before) : cartOf(before.valueOrNull!)}',
      );

      final checkout = walk.read(checkoutRepositoryProvider);
      CheckoutSelection buy(
        String product, {
        String? variant,
        int quantity = 1,
      }) => CheckoutSelection(
        addressId: address.id,
        paymentMethodId: 'pm-cod',
        buyNow: BuyNowLine(
          productId: product,
          variantId: variant,
          quantity: quantity,
        ),
      );
      String reviewOf(Result<CheckoutSummary> r) {
        final s = r.valueOrNull;
        if (s == null) return say(r);
        return '${[
              for (final g in s.groups) '${g.merchantName}: ${[for (final l in g.lines) '${l.name} x${l.quantity}']} sub=${g.subtotal} fee=${g.shippingFee} discount=${g.discount} due=${g.amountDue} delivers=${g.deliversHere}',
            ]} '
            'sub=${s.subtotal} ship=${s.shipping} discount=${s.discount} total=${s.total} canPlace=${s.canPlaceOrder} warnings=${s.warnings}';
      }

      final phone = buy('57', variant: '66');
      print(
        '3 Buy now M3 Phone review: ${reviewOf(await checkout.review(phone))}',
      );
      final key = 'm9-buynow-${DateTime.now().millisecondsSinceEpoch}';
      final placed = await checkout.placeOrder(
        selection: phone,
        idempotencyKey: key,
      );
      final again = await checkout.placeOrder(
        selection: phone,
        idempotencyKey: key,
      );
      print(
        '3 place: ${say(placed)} ${placed.valueOrNull?.orderNumber}; same key again: ${say(again)} '
        '${again.valueOrNull?.orderId == placed.valueOrNull?.orderId ? 'SAME order' : 'DIFFERENT'}',
      );
      print('3 cart after: ${cartOf((await cart.fetchCart()).unwrap())}');
      if (placed.valueOrNull case final p?) {
        final o = (await orders.fetchOrder(p.orderId)).unwrap();
        print(
          '3 order ${o.orderNumber}: ${[for (final i in o.items) '${i.productName} x${i.quantity} ${i.lineTotal}']} '
          'sub=${o.subtotal} ship=${o.shipping} discount=${o.discount} total=${o.total} ${o.status.name}',
        );
        final m2 = await as('+9647732172587', 'walkpass123');
        final waiting =
            (await m2
                    .read(merchantRepositoryProvider)
                    .orders(status: 'PENDING'))
                .unwrap()
                .items;
        print(
          '3 the store sees it: ${waiting.any((r) => r.orderNumber == o.orderNumber) ? 'YES' : 'no'}',
        );
      }

      print(
        '3 Buy now 2 cameras (first order): ${reviewOf(await checkout.review(buy('9', quantity: 2)))}',
      );
      final over = await checkout.placeOrder(
        selection: buy('9', quantity: 2),
        idempotencyKey: 'm9-over-${DateTime.now().millisecondsSinceEpoch}',
      );
      print('3 place 2 cameras: ${say(over)}');
      final zakho = await checkout.placeOrder(
        selection: buy('15'),
        idempotencyKey: 'm9-zakho-${DateTime.now().millisecondsSinceEpoch}',
      );
      print(
        '3 Buy now from Zakho (no delivery here): ${reviewOf(await checkout.review(buy('15')))} / place: ${say(zakho)}',
      );
      final gone = await checkout.placeOrder(
        selection: buy('13'),
        idempotencyKey: 'm9-gone-${DateTime.now().millisecondsSinceEpoch}',
      );
      print(
        '3 Buy now something run out: ${reviewOf(await checkout.review(buy('13')))} / place: ${say(gone)}',
      );
      for (final r in [over, zakho, gone]) {
        if (r.valueOrNull case final p?) {
          print(
            '3 !! placed ${p.orderNumber}; cancelling: ${say(await orders.cancelOrder(orderId: p.orderId, reason: 'ORDERED_BY_MISTAKE'))}',
          );
        }
      }

      final ar = (await asWalk(locale: 'ar')).read(checkoutRepositoryProvider);
      print(
        '4 ar 2 cameras: ${reviewOf(await ar.review(buy('9', quantity: 2)))}',
      );
      print(
        '4 ar Zakho: ${say(await ar.placeOrder(selection: buy('15'), idempotencyKey: 'm9-ar-${DateTime.now().millisecondsSinceEpoch}'))}',
      );

      // Put things back.
      if (placed.valueOrNull case final p?) {
        print(
          '3 cancel the Buy now order: ${say(await orders.cancelOrder(orderId: p.orderId, reason: 'ORDERED_BY_MISTAKE'))}',
        );
      }
      final left = (await cart.fetchCart()).unwrap();
      for (final i in left.groups.expand((g) => g.items)) {
        await cart.removeItem(i.id);
      }
      if (left.coupon != null) await cart.removeCoupon();
    }
  });
}
