// The end of the buy, which is where a shopper is most anxious.
//
// The confirmation screen drew a red alert above the words "Order placed" when
// a payment had failed, and repeated the payment's state in a coloured box
// underneath — the biggest thing on the screen saying one thing and the mark
// above it another. And an ordered item was the one place in the whole app
// where a product was drawn and could not be opened.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/widgets/call_button.dart';
import 'package:saba_marketplace/core/widgets/section_header.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';
import 'package:saba_marketplace/features/orders/domain/orders_repository.dart';
import 'package:saba_marketplace/features/orders/presentation/invoice_providers.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/orders/presentation/screens/invoice_screen.dart';
import 'package:saba_marketplace/features/orders/presentation/screens/order_detail_screen.dart';
import 'package:saba_marketplace/features/returns/presentation/screens/request_return_screen.dart';
import 'package:saba_marketplace/features/returns/presentation/widgets/return_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _en = AppLocalizations(Locale('en'));

/// The demo backend leaves a cash order's payment pending and marks a card
/// order paid, which is the only lever these tests need to reach both
/// branches of the confirmation screen.
const String _cashOnDelivery = 'pm-cod';

/// Where the dialer is opened from; the test has no phone.
const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

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

  /// Buys something, for real: signs in, fills a cart, prices the order and
  /// places it. Returns the container and the id of the order that resulted.
  Future<(ProviderContainer, String)> buySomething(
    WidgetTester tester, {
    String? paymentMethodId,
  }) async {
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

    late String orderId;
    // In `runAsync`: the demo backend answers after 350ms of real time, and a
    // widget test's clock is fake, so these would never complete out here.
    await tester.runAsync(() async {
      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'demo@saba.app', password: 'Password1');
      await container
          .read(cartControllerProvider.notifier)
          .addItem(productId: 'p-1', quantity: 1);

      final checkout = container.read(checkoutControllerProvider.notifier);
      await checkout.priceOrder();
      if (paymentMethodId != null) {
        checkout.selectPaymentMethod(paymentMethodId);
      }

      final placed = await checkout.placeOrder();
      orderId = placed.unwrap().orderId;
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
    return (container, orderId);
  }

  /// Nova takes the newest order all the way: confirmed, prepared, sent
  /// with its driver Ali, delivered. Then back to the shopper.
  Future<void> deliver(WidgetTester tester, ProviderContainer container) async {
    await tester.runAsync(() async {
      final auth = container.read(authControllerProvider.notifier);
      await auth.signIn(email: 'merchant@saba.app', password: 'Password1');
      final store = container.read(merchantRepositoryProvider);
      final part = (await store.orders(status: 'PENDING')).unwrap().items.first;
      for (final step in ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']) {
        (await store.updateOrderStatus(
          orderId: part.id,
          status: step,
          courier: step == 'SHIPPED'
              ? const Courier(name: 'Ali', phone: '+9647701112222')
              : null,
        )).unwrap();
      }
      await auth.signIn(email: 'demo@saba.app', password: 'Password1');
    });
  }

  Future<void> goTo(
    WidgetTester tester,
    ProviderContainer container,
    String location,
  ) async {
    container.read(appRouterProvider).go(location);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('a return shows under Returns on My orders and on its order', (
    tester,
  ) async {
    // Returns had a screen of their own behind a text link in the Orders
    // header, and an order never mentioned its own return.
    final (container, orderId) = await buySomething(tester);
    await deliver(tester, container);
    late String orderNumber;
    await tester.runAsync(() async {
      final orders = container.read(ordersRepositoryProvider);
      final order = (await orders.fetchOrder(orderId)).unwrap();
      orderNumber = order.orderNumber;
      (await orders.requestReturn(
        orderId: orderId,
        lines: [ReturnLine(orderItemId: order.items.first.id, quantity: 1)],
        reason: 'DAMAGED',
      )).unwrap();
    });

    await goTo(tester, container, AppRoutes.orders);
    expect(find.text(_en.myReturns), findsNothing, reason: 'header link');

    // The last pill in a row that scrolls sideways, reached the way a
    // thumb reaches it.
    await tester.scrollUntilVisible(
      find.text(_en.returns),
      200,
      // The pill row is the one sideways scroller on the screen. Found by
      // that, not through a pill, which scrolls away as the row moves.
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
      ),
    );
    await tester.tap(find.text(_en.returns));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(ReturnList), findsOneWidget);
    expect(find.text(orderNumber), findsOneWidget, reason: 'not listed');

    await goTo(tester, container, AppRoutes.orderDetailPath(orderId));
    await tester.scrollUntilVisible(
      find.text(_en.returnDetails),
      300,
      scrollable: find
          .descendant(
            of: find.byType(OrderDetailScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text(_en.returnDetails), findsOneWidget);
  });

  testWidgets('the driver is named, called in a tap, and asked about', (
    tester,
  ) async {
    final (container, orderId) = await buySomething(tester);
    await deliver(tester, container);

    String? dialled;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcher, (call) async {
          dialled = (call.arguments as Map)['url'] as String?;
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_launcher, null),
    );

    await goTo(tester, container, AppRoutes.orderDetailPath(orderId));
    final driver = find.textContaining('${_en.driverLabel}: Ali');
    expect(driver, findsOneWidget, reason: 'the order does not say who');
    final call = find.descendant(
      of: find.ancestor(of: driver, matching: find.byType(Row)).first,
      matching: find.text(_en.call),
    );
    await tester.ensureVisible(call);
    await tester.pump();
    await tester.tap(call);
    await tester.pump();
    expect(dialled, 'tel:+9647701112222', reason: 'Call did not dial Ali');

    // It came: said once, and the question goes.
    expect(find.text(_en.didYouReceive), findsOneWidget);
    await tester.tap(find.text(_en.yesReceived));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(
      find.text(_en.didYouReceive),
      findsNothing,
      reason: 'asked again after she answered',
    );
  });

  testWidgets('a settled payment says the money moved, once', (tester) async {
    final (container, orderId) = await buySomething(tester);
    // Cash is paid at the door, so it is settled once Nova has delivered.
    await deliver(tester, container);
    await goTo(tester, container, AppRoutes.orderConfirmationPath(orderId));

    expect(find.text(_en.orderPlaced), findsOneWidget);
    expect(find.text(_en.orderPlacedMessage), findsOneWidget);

    // The payment keeps its own line: "Order placed" is not the same fact as
    // "the money moved", and a cash order proves it by saying only the first.
    expect(find.text(_en.paymentConfirmed), findsOneWidget);
    // Nothing to wait for, so nothing to re-check.
    expect(find.text(_en.checkPaymentStatus), findsNothing);
  });

  testWidgets('a cash order says to pay on delivery, under the headline', (
    tester,
  ) async {
    final (container, orderId) = await buySomething(
      tester,
      paymentMethodId: _cashOnDelivery,
    );
    await goTo(tester, container, AppRoutes.orderConfirmationPath(orderId));

    // The order did happen, and the headline still says so.
    expect(find.text(_en.orderPlaced), findsOneWidget);
    // The sentence under it is about the payment, not a blanket thank-you -
    // and for cash it is the plan, not a payment stuck with a provider,
    // which is what it used to say.
    expect(find.text(_en.codPlacedMessage), findsOneWidget);
    expect(find.text(_en.paymentPendingMessage), findsNothing);
    expect(find.text(_en.orderPlacedMessage), findsNothing);
    expect(find.text(_en.payOnDelivery), findsOneWidget);
    expect(find.text(_en.paymentConfirmed), findsNothing);
    // Cash is settled at the door: there is nothing to re-check.
    expect(find.text(_en.checkPaymentStatus), findsNothing);
  });

  testWidgets('the back gesture leaves the finished order, not nothing', (
    tester,
  ) async {
    final (container, orderId) = await buySomething(tester);
    await goTo(tester, container, AppRoutes.orderConfirmationPath(orderId));
    expect(find.text(_en.orderPlaced), findsOneWidget);

    // The system back button, which this screen refuses to pop. Refusing is
    // right; doing nothing about it is what made the phone feel stuck.
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.text(_en.orderPlaced), findsNothing);
    expect(
      container
          .read(appRouterProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path,
      AppRoutes.home,
    );
  });

  // The store's own driver, named with a way to call: v1 has no delivery
  // companies and no tracking numbers.
  testWidgets("a shipped part names the store's driver", (tester) async {
    final order = Order(
      id: 'o-driver',
      orderNumber: 'SB-1001',
      placedAt: DateTime(2026, 3, 1),
      status: OrderStatus.shipped,
      paymentStatus: PaymentStatus.pending,
      items: const <OrderItem>[
        OrderItem(
          id: 'i-1',
          productName: 'Nova X5 Smartphone',
          quantity: 1,
          unitPrice: 100,
          lineTotal: 100,
          currencyCode: 'IQD',
          merchantId: 'm-1',
          merchantName: 'Nova Electronics',
          status: OrderStatus.shipped,
        ),
      ],
      subtotal: 100,
      total: 100,
      currencyCode: 'IQD',
      parts: const <String, OrderStorePart>{
        'm-1': OrderStorePart(
          amountDue: 100,
          courierName: 'Haider Salim',
          courierPhone: '+9647705550311',
        ),
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderDetailProvider('o-driver').overrideWith((ref) async => order),
        ],
        retry: (_, _) => null,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const OrderDetailScreen(orderId: 'o-driver'),
        ),
      ),
    );
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.textContaining('Haider Salim'), findsOneWidget);
    expect(find.byType(CallButton), findsWidgets);
    expect(find.textContaining('Tracking'), findsNothing);
  });

  testWidgets('an ordered item opens the product it was', (tester) async {
    final (container, orderId) = await buySomething(tester);
    await goTo(tester, container, AppRoutes.orderDetailPath(orderId));

    expect(find.byType(ProductDetailScreen), findsNothing);

    // The name of the thing bought, on the order's own item row.
    final name = find.text('Nova X5 Smartphone');
    expect(name, findsWidgets);

    await tester.tap(name.first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(ProductDetailScreen), findsOneWidget);
  });

  // BUGS 99: a cancelled invoice said nothing of it, and its total read as
  // owed.
  testWidgets('a cancelled invoice says nothing will be charged', (
    tester,
  ) async {
    Future<void> show(PaymentStatus status) async {
      final invoice = Invoice(
        orderId: 'o-inv',
        orderNumber: 'SB-1',
        issuedAt: DateTime(2026, 9, 1),
        lines: const [
          InvoiceLine(
            description: 'Nova X5',
            quantity: 1,
            unitPrice: 250000,
            total: 250000,
          ),
        ],
        subtotal: 250000,
        total: 250000,
        currencyCode: 'IQD',
        paymentStatus: status,
      );
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            invoiceProvider('o-inv').overrideWith((ref) async => invoice),
          ],
          retry: (_, _) => null,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const InvoiceScreen(orderId: 'o-inv'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    TextDecoration? totalLine() => tester
        .widget<Text>(
          find
              .descendant(
                of: find.widgetWithText(CardLine, _en.total),
                matching: find.byType(Text),
              )
              .last,
        )
        .style
        ?.decoration;

    await show(PaymentStatus.cancelled);
    expect(find.text(_en.cancelledNothingCharged), findsOneWidget);
    expect(totalLine(), TextDecoration.lineThrough);

    await show(PaymentStatus.pending);
    expect(find.text(_en.cancelledNothingCharged), findsNothing);
    expect(totalLine(), isNot(TextDecoration.lineThrough));
  });

  // The tester: an order of two offered one item for return. Only what was
  // delivered can go back, but the other one says why it is not there.
  testWidgets('the return page says why an item is not on it', (tester) async {
    OrderItem line(String id, String name, OrderStatus status) => OrderItem(
      id: id,
      productName: name,
      quantity: 1,
      unitPrice: 100,
      lineTotal: 100,
      currencyCode: 'IQD',
      merchantId: 'm-1',
      merchantName: 'Nova Electronics',
      status: status,
      canReturn: status == OrderStatus.delivered,
    );
    final order = Order(
      id: 'o-two',
      orderNumber: 'SB-1003',
      placedAt: DateTime(2026, 9, 20),
      status: OrderStatus.confirmed,
      paymentStatus: PaymentStatus.pending,
      items: [
        line('i-1', 'Nova X5 Smartphone', OrderStatus.delivered),
        line('i-2', 'Nova Watch Series 4', OrderStatus.shipped),
      ],
      subtotal: 200,
      total: 200,
      currencyCode: 'IQD',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderDetailProvider('o-two').overrideWith((ref) async => order),
        ],
        retry: (_, _) => null,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const RequestReturnScreen(orderId: 'o-two'),
        ),
      ),
    );
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.text('Nova X5 Smartphone'), findsOneWidget);
    expect(find.text(_en.notOnThisReturn), findsOneWidget);
    expect(find.text('Nova Watch Series 4'), findsOneWidget, reason: 'hidden');
    expect(find.text(_en.notDeliveredYetReturn), findsOneWidget);
  });
}
