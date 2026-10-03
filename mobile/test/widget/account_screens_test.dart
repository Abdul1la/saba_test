// The Account screen and everything behind it, used the way a person would:
// every row opens, every form saves, and what was saved is still there.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/widgets/dark_header_card.dart';
import 'package:saba_marketplace/features/addresses/domain/entities.dart';
import 'package:saba_marketplace/features/addresses/presentation/address_providers.dart';
import 'package:saba_marketplace/features/addresses/presentation/screens/address_form_screen.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/cart/presentation/cart_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/product_card.dart';
import 'package:saba_marketplace/features/home/presentation/widgets/home_products.dart';
import 'package:saba_marketplace/features/checkout/presentation/checkout_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/messaging/presentation/messaging_providers.dart';
import 'package:saba_marketplace/features/notifications/presentation/notifications_providers.dart';
import 'package:saba_marketplace/features/orders/presentation/orders_providers.dart';
import 'package:saba_marketplace/features/profile/presentation/screens/profile_screen.dart';
import '../support/saba_web.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_order_detail_screen.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_product_form_screen.dart';
import 'package:saba_marketplace/features/orders/domain/orders_repository.dart';
import 'package:saba_marketplace/features/returns/presentation/screens/return_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Where the image cache keeps its files; a test has no phone to ask.
const _paths = MethodChannel('plugins.flutter.io/path_provider');

const _en = AppLocalizations(Locale('en'));

/// What Home can sell: the demo's products less the few its stores keep
/// off sale.
final int _onSale = MockData.products
    .where((p) => MockData.startsOnSale(p['id']))
    .length;

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

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _paths,
          (_) async => Directory.systemTemp.path,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_paths, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystore, null);
    DioFactory.mockBackend.resetForTesting();
  });

  /// The app on a phone; signed in as [email], or signed out when null.
  Future<(ProviderContainer, Future<void> Function())> pumpApp(
    WidgetTester tester, {
    String? email,
  }) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final preferences = await AppPreferences.create();
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    if (email != null) {
      await tester.runAsync(() async {
        await container
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: 'Password1');
      });
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );

    Future<void> settle() async {
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await settle();
    return (container, settle);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
  }

  testWidgets('Account: one way to the profile, and what is saved stays', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.account);
    await settle();

    // The name at the top opens the profile; no second row does the same.
    expect(
      find.text(_en.myProfile),
      findsNothing,
      reason: 'a second door to the profile',
    );
    // No heading over a single row (BUGS.md 86); Settings sits with the rest.
    expect(find.text(_en.accountSecurity), findsNothing);
    expect(find.text(_en.settings), findsOneWidget);
    await tapText(tester, 'Amina Saleh');
    await settle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Amina Hassan');
    await tapText(tester, _en.saveChanges);
    await settle();

    // Read the account again, as the next launch would.
    await tester.runAsync(
      () => container.read(authControllerProvider.notifier).refreshUser(),
    );
    expect(
      container.read(currentUserProvider)?.fullName,
      'Amina Hassan',
      reason: 'the saved name was forgotten',
    );
  });

  testWidgets('addresses: add one, make it the default, delete it', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.addresses);
    await settle();
    final before = container.read(addressListProvider).requireValue.length;

    await tapText(tester, _en.addAddress);
    await settle();
    // Her name and number are already in; the city is picked, not typed.
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '0770 111 2222');
    // The list scrolls to the typed field; a tap mid-scroll is dropped.
    await settle();
    await tapText(tester, 'Baghdad');
    await settle();
    await tester.tap(find.text('Basra'));
    await settle();
    await tester.enterText(fields.at(2), 'Al-Ashar');
    await tester.enterText(fields.at(3), 'Next to the old market');
    await tester.enterText(fields.at(4), 'Corniche Street 5');
    await tapText(tester, _en.save);
    await settle();

    bool isNew(Address address) => address.street == 'Corniche Street 5';
    var list = container.read(addressListProvider).requireValue;
    expect(list, hasLength(before + 1), reason: 'the address was not added');
    final added = list.singleWhere(isNew);
    expect(added.fullName, 'Amina Saleh');
    expect(
      added.phone,
      '+9647701112222',
      reason: 'the number was not kept the one way the driver dials it',
    );
    expect(added.governorate, Governorate.basra);
    expect(added.area, 'Al-Ashar');
    expect(added.landmark, 'Next to the old market');
    expect(
      find.text('Corniche Street 5, Al-Ashar, Basra'),
      findsOneWidget,
      reason: 'the card does not say where it is',
    );
    expect(
      find.text('${_en.nearestLandmark}: Next to the old market'),
      findsOneWidget,
      reason: 'the card does not say the landmark',
    );

    // Each card says Edit in words, and it opens that address.
    final edit = find.descendant(
      of: find
          .ancestor(
            of: find.textContaining('Corniche'),
            matching: find.byType(InkWell),
          )
          .first,
      matching: find.text(_en.edit),
    );
    await tester.ensureVisible(edit);
    await tester.pump();
    await tester.tap(edit);
    await settle();
    expect(
      find.byType(AddressFormScreen),
      findsOneWidget,
      reason: 'the card has no Edit button that works',
    );
    container.read(appRouterProvider).pop();
    await settle();

    await tapText(tester, _en.setAsDefault);
    await settle();
    list = container.read(addressListProvider).requireValue;
    expect(
      list.singleWhere(isNew).isDefault,
      isTrue,
      reason: 'Set as default did nothing',
    );

    // Delete the new one, from its own card.
    final card = find.ancestor(
      of: find.textContaining('Corniche'),
      matching: find.byType(InkWell),
    );
    final delete = find.descendant(
      of: card.first,
      matching: find.text(_en.delete),
    );
    await tester.ensureVisible(delete);
    await tester.pump();
    await tester.tap(delete);
    await settle();
    await tapText(tester, _en.delete);
    await settle();
    expect(
      container.read(addressListProvider).requireValue,
      hasLength(before),
      reason: 'the address was not deleted',
    );
  });

  /// The colour of the nearest box painted behind [text].
  Color? boxBehind(Finder text) {
    for (final element
        in find
            .ancestor(of: text, matching: find.byType(Container))
            .evaluate()) {
      final decoration = (element.widget as Container).decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        return decoration.color;
      }
    }
    return null;
  }

  /// [text] sits on a white top, in dark words.
  void expectWhiteTop(WidgetTester tester, Finder text, String screen) {
    expect(text, findsWidgets, reason: '$screen: nothing at the top');
    final first = text.first;
    expect(
      boxBehind(first),
      Theme.of(tester.element(first)).colorScheme.surface,
      reason: '$screen: the top is still black',
    );
    expect(
      tester.widget<Text>(first).style!.color!.computeLuminance(),
      lessThan(0.3),
      reason: '$screen: light words on the white top',
    );
  }

  Finder inHeader(String text) => find.descendant(
    of: find.byType(DarkHeaderCard),
    matching: find.text(text),
  );

  testWidgets('every top is white on the shopper side', (tester) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    final router = container.read(appRouterProvider);

    router.go(AppRoutes.account);
    await settle();
    expectWhiteTop(tester, inHeader('Amina Saleh'), 'Account');

    late String orderId;
    late String orderNumber;
    // An order to open: the demo shopper has none until they buy.
    await tester.runAsync(() async {
      await container
          .read(cartControllerProvider.notifier)
          .addItem(productId: 'p-1', quantity: 1);
      final checkout = container.read(checkoutControllerProvider.notifier);
      await checkout.priceOrder();
      orderId = (await checkout.placeOrder()).unwrap().orderId;
      orderNumber =
          (await container.read(ordersRepositoryProvider).fetchOrder(orderId))
              .unwrap()
              .orderNumber;
    });
    router.go(AppRoutes.orderDetailPath(orderId));
    await settle();
    expectWhiteTop(tester, inHeader(orderNumber), 'Order');
  });

  testWidgets('every top is white on the store side', (tester) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'merchant@saba.app',
    );
    final router = container.read(appRouterProvider);

    router.go(AppRoutes.merchantDashboard);
    await settle();
    expectWhiteTop(tester, inHeader('Nova Electronics'), 'Dashboard');

    router.go(AppRoutes.merchantAccount);
    await settle();
    expectWhiteTop(tester, inHeader('Nova Electronics'), 'Store account');

    router.go(AppRoutes.merchantAnalytics);
    await settle();
    expectWhiteTop(tester, find.textContaining(_en.revenue), 'Analytics');
  });

  // v1 has no email; the demo accounts' sign-in emails showed on both
  // account screens (the tester).
  testWidgets('no email on either account screen, the phone instead', (
    tester,
  ) async {
    for (final (who, route, phone) in [
      ('shopper@saba.app', AppRoutes.account, '+964 770 123 4567'),
      ('merchant@saba.app', AppRoutes.merchantAccount, '+964 771 123 4567'),
    ]) {
      final (container, settle) = await pumpApp(tester, email: who);
      container.read(appRouterProvider).go(route);
      await settle();
      expect(find.textContaining('@'), findsNothing, reason: route);
      expect(find.textContaining(phone), findsWidgets, reason: route);
    }
  });

  testWidgets('messages: each chat its own, the unread one stands out', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.conversations);
    await settle();

    final chats = container.read(conversationsProvider).requireValue;
    expect(chats, hasLength(3));
    expect(
      {for (final chat in chats) chat.lastMessage}.length,
      chats.length,
      reason: 'the same words under every store',
    );
    for (final chat in chats) {
      expect(find.text(chat.title), findsOneWidget);
      expect(find.text(chat.lastMessage!), findsOneWidget);
    }
    // The store's own logo, not a grey silhouette. (Its initials are what
    // a store with no logo on file gets.)
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/stores/nova-logo.jpg',
      ),
      findsOneWidget,
      reason: "Nova's chat does not show Nova's logo",
    );
    // The unread answer is counted beside it.
    final unread = chats.singleWhere((chat) => chat.unreadCount > 0);
    expect(find.text('${unread.unreadCount}'), findsOneWidget);
  });

  testWidgets('notifications say something real, and can all be read', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.notifications);
    await settle();
    expect(
      find.textContaining('Demo notification'),
      findsNothing,
      reason: "placeholder words on the customer's screen",
    );
    // And no order she never placed (BUGS.md 41).
    expect(find.text('The store is getting it ready.'), findsNothing);

    await tapText(tester, _en.markAllRead);
    await settle();
    final items = container.read(notificationListProvider).requireValue.items;
    expect(
      items.where((notification) => !notification.isRead),
      isEmpty,
      reason: 'Mark all as read left some unread',
    );
  });

  testWidgets('the rule pages open from Account, signed in or not', (
    tester,
  ) async {
    var (container, settle) = await pumpApp(tester);
    container.read(appRouterProvider).go(AppRoutes.account);
    await settle();
    await tapText(tester, _en.returnPolicy);
    await settle();
    expect(find.text('7 days, at every store'), findsOneWidget);

    (container, settle) = await pumpApp(tester, email: 'shopper@saba.app');
    container.read(appRouterProvider).go(AppRoutes.account);
    await settle();
    await tapText(tester, _en.termsOfUse);
    await settle();
    expect(find.text('What Saba is'), findsOneWidget);

    // The product says Saba's 7 days, not the 14 a store once wrote.
    container.read(appRouterProvider).go(AppRoutes.productDetailPath('p-1'));
    await settle();
    // In the delivery block, after "Return policy:".
    await tester.scrollUntilVisible(
      find.textContaining(_en.returnRuleShort),
      300,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.textContaining(_en.returnRuleShort), findsOneWidget);
    expect(find.textContaining('14-day'), findsNothing);
    // And the store's page, which said 14 and 30.
    container.read(appRouterProvider).go(AppRoutes.storefrontPath('m-1'));
    await settle();
    await tester.scrollUntilVisible(
      find.text(_en.returnRuleShort),
      300,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.textContaining('-day returns'), findsNothing);

    // In Arabic, the words are Arabic.
    await tester.runAsync(
      () => container
          .read(localeControllerProvider.notifier)
          .setLocale(const Locale('ar')),
    );
    container.read(appRouterProvider).go(AppRoutes.legalPath('privacy'));
    await settle();
    expect(find.text('من يرى بياناتك'), findsOneWidget);
  });

  testWidgets('a store reads the rules; returns are not its to set', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'merchant@saba.app',
    );
    final router = container.read(appRouterProvider);
    router.go(AppRoutes.merchantAccount);
    await settle();
    await tapText(tester, _en.termsOfUse);
    await settle();
    expect(find.text('What Saba is'), findsOneWidget);

    router.go(AppRoutes.merchantProductForm);
    await settle();
    expect(find.text(_en.returnRuleStore), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, _en.returnPolicy),
      findsNothing,
      reason: 'a store can still write its own return days',
    );
  });

  testWidgets('a search that found something shows under Popular', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    final router = container.read(appRouterProvider);
    router.go(AppRoutes.search);
    await settle();
    expect(
      find.text(_en.popularSearches),
      findsNothing,
      reason: 'popular searches nobody made',
    );

    await tester.enterText(find.byType(TextField).first, 'watch');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle();
    router.go(AppRoutes.home);
    await settle();
    router.go(AppRoutes.search);
    await settle();
    // An empty box, and the page acts like one: the last word typed is gone.
    expect(
      find.text(_en.recentSearches),
      findsOneWidget,
      reason: 'the old word was still typed behind an empty box',
    );
    expect(
      find.text(_en.popularSearches),
      findsOneWidget,
      reason: 'the list was read once and never again',
    );
  });

  // A long name is cut with "…" on Home, not squeezed until unreadable.
  testWidgets('Home: a long name is cut, not squashed', (tester) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    await tester.runAsync(
      () => container
          .read(authControllerProvider.notifier)
          .updateProfile(fullName: 'A' * 50),
    );
    container.read(appRouterProvider).go(AppRoutes.home);
    await settle();
    expect(find.text('${'A' * 23}…'), findsOneWidget);
  });

  testWidgets('Home: a city chip filters every product; the count follows', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.home);
    await settle();
    // "Hello", never "Welcome back" to an account that may be new.
    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Hello'), findsOneWidget);
    final down = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;
    // The All products grid's cards, not the rails' above it.
    final grid = find.descendant(
      of: find.byType(HomeAllProducts),
      matching: find.byType(ProductCard),
    );
    Iterable<ProductCard> cards() => tester.widgetList<ProductCard>(grid);

    // Every product, and the ones Nova sends to Amina in Baghdad say so.
    await tester.scrollUntilVisible(
      find.text(_en.filters),
      400,
      scrollable: down,
    );
    await settle();
    expect(find.text(_en.productsFound(_onSale)), findsOneWidget);
    expect(find.text(_en.deliveryAvailable), findsWidgets);
    // The first card: its discount, and its heart on the photo.
    final first = grid.first;
    expect(
      find.descendant(
        of: first,
        matching: find.text(
          _en.discountBadge(
            '${MockData.productById('p-1')!['discountPercentage']}',
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.byTooltip(_en.addToWishlist)),
      findsOneWidget,
    );
    // The last of the 40 is on the second page: scrolling reaches it.
    await tester.scrollUntilVisible(
      find.text('Hadba Microwave 30L'),
      600,
      scrollable: down,
    );
    await settle();

    // Duhok: its two stores only, and neither sends to Baghdad.
    await tester.scrollUntilVisible(
      find.text(_en.allCities),
      -400,
      scrollable: down,
    );
    final chips = find.descendant(
      of: find.byType(HomeCityChips),
      matching: find.byType(Scrollable),
    );
    final duhok = find.descendant(of: chips, matching: find.text('Duhok'));
    await tester.scrollUntilVisible(duhok, 120, scrollable: chips);
    // Built is not on screen: bring it into view on both axes before the tap.
    await tester.ensureVisible(duhok);
    await settle();
    await tester.tap(duhok);
    await settle();
    await tester.scrollUntilVisible(
      find.text(_en.filters),
      400,
      scrollable: down,
    );
    await settle();
    expect(
      find.text(_en.productsFound(13)),
      findsOneWidget,
      reason: 'the count does not follow the city',
    );
    expect(cards(), isNotEmpty);
    expect(cards().map((card) => card.product.merchantId).toSet(), {
      'm-3',
      'm-4',
    }, reason: 'another city showed under Duhok');
    // And each card says so.
    expect(cards().map((card) => card.product.merchantCity).toSet(), {
      Governorate.duhok,
    });
    expect(find.text(_en.deliveryAvailable), findsNothing);
  });

  testWidgets('Categories keeps the heart beside its search', (tester) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.categories);
    await settle();
    expect(find.byTooltip(_en.wishlist), findsOneWidget);
  });

  testWidgets('choosing Arabic changes the language', (tester) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    final router = container.read(appRouterProvider);

    router.go(AppRoutes.settings);
    await settle();
    await tapText(tester, 'العربية');
    await settle();
    expect(
      container.read(localeControllerProvider)?.languageCode,
      'ar',
      reason: 'choosing Arabic did not change the language',
    );
  });

  // Apple 5.1.1(v) and Google Play: every account can be deleted from the
  // app, and closing a store is not deleting it. A store asks: it closes at
  // once, the page says what the deletion waits for and how the owner hears
  // it is done, the switch cannot open it, and it can be taken back. A
  // shopper still deletes on the spot.
  testWidgets('a store asks for its account to be deleted', (tester) async {
    final (shopper, settleShopper) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    shopper.read(appRouterProvider).go(AppRoutes.profile);
    await settleShopper();
    expect(find.text(_en.deleteAccountHint), findsOneWidget);

    final (container, settle) = await pumpApp(
      tester,
      email: 'merchant@saba.app',
    );
    final router = container.read(appRouterProvider);
    router.go(AppRoutes.merchantDashboard);
    await settle();
    expect(find.byType(Switch), findsOneWidget);

    router.go(AppRoutes.profile);
    await settle();
    expect(
      find.text(_en.deleteStoreAccountHint),
      findsOneWidget,
      reason: 'a store cannot delete its account',
    );
    await tapText(tester, _en.deleteAccount);
    await settle();
    expect(
      find.text(_en.deleteStoreAccountMessage),
      findsOneWidget,
      reason: 'not told how long it takes, or what is kept',
    );
    await tapText(tester, _en.delete);
    await settle();

    expect(find.text(_en.storeDeletionTitle), findsOneWidget);
    expect(find.text(_en.storeDeletionWaitsFor), findsOneWidget);
    expect(find.textContaining('Orders still open: '), findsOneWidget);
    expect(find.textContaining('Owed to Saba: '), findsOneWidget);
    expect(find.text(_en.storeDeletionSms), findsOneWidget);
    // The reviewer: an unpaid bill stops the deletion, and the owner is told.
    expect(find.text(_en.storeDeletionUnpaid), findsOneWidget);

    final shelf = container.read(merchantRepositoryProvider);
    late MerchantDashboard dashboard;
    late bool reopened;
    await tester.runAsync(() async {
      dashboard = (await shelf.dashboard()).unwrap();
      reopened = (await shelf.setOpen(true)).isOk;
    });
    expect(dashboard.isOpen, isFalse, reason: 'still taking orders');
    expect(reopened, isFalse, reason: 'opened while being deleted');

    router.go(AppRoutes.merchantDashboard);
    await settle();
    expect(find.text(_en.storeBeingDeleted), findsOneWidget);
    expect(find.byType(Switch), findsNothing, reason: 'a switch that fails');

    // Taken back: asked first; the store stays closed.
    router.go(AppRoutes.profile);
    await settle();
    await tapText(tester, _en.keepMyAccount);
    await settle();
    await tapText(tester, _en.keepMyAccount);
    await settle();
    expect(find.text(_en.storeDeletionTitle), findsNothing);
    expect(find.text(_en.deleteStoreAccountHint), findsOneWidget);
    await tester.runAsync(() async {
      dashboard = (await shelf.dashboard()).unwrap();
    });
    expect(dashboard.isOpen, isFalse, reason: 'opened by taking it back');
  });

  // The user: a store tapping "New order" went nowhere, the one it taps
  // most; nor did a return's answer or a product's. Each opens its thing.
  testWidgets('a notification opens what it is about', (tester) async {
    // Before the app opens: an order from the shopper, answered as far as a
    // return, and a product Saba approved.
    late String part;
    late String returnId;
    late String productId;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'saba.pref.onboarding_seen': true,
        'saba.pref.locale': 'en',
      });
      final c = ProviderContainer(
        overrides: [
          appPreferencesProvider.overrideWithValue(
            await AppPreferences.create(),
          ),
        ],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      final auth = c.read(authControllerProvider.notifier);
      Future<void> signIn(String email) async =>
          (await auth.signIn(email: email, password: 'Password1')).unwrap();

      await signIn('shopper@saba.app');
      await c
          .read(cartControllerProvider.notifier)
          .addItem(productId: 'p-1', quantity: 1);
      final checkout = c.read(checkoutControllerProvider.notifier);
      await checkout.priceOrder();
      final orderId = (await checkout.placeOrder()).unwrap().orderId;

      await signIn('merchant@saba.app');
      final store = c.read(merchantRepositoryProvider);
      part = (await store.orders()).unwrap().items.first.id;
      for (final step in ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED']) {
        (await store.updateOrderStatus(
          orderId: part,
          status: step,
          courier: step == 'SHIPPED'
              ? const Courier(name: 'Ali', phone: '+9647701112222')
              : null,
        )).unwrap();
      }
      (await store.saveProduct(
        const ProductDraft(
          name: 'Walk One',
          nameAr: 'منتج تجريبي',
          categoryId: 'c-1',
          price: 12250,
          description: 'A product for the walk, ten letters.',
        ),
      )).unwrap();

      await signIn('shopper@saba.app');
      final orders = c.read(ordersRepositoryProvider);
      final order = (await orders.fetchOrder(orderId)).unwrap();
      (await orders.requestReturn(
        orderId: orderId,
        lines: [ReturnLine(orderItemId: order.items.first.id, quantity: 1)],
        reason: 'DAMAGED',
      )).unwrap();

      await signIn('merchant@saba.app');
      returnId = (await store.order(part)).unwrap().returns.single.id;
      (await store.answerReturn(returnId, 'APPROVED')).unwrap();

      await signIn('admin@saba.app');
      final queue =
          (await c
                  .read(apiClientProvider)
                  .get<Map<String, dynamic>>(
                    adminQueuePath,
                    decoder: (e) => e.dataAsMap,
                  ))
              .unwrap();
      productId = '${((queue['products'] as List).last as Map)['id']}';
      expect(
        await c.read(adminAnswersProvider).product(productId, approve: true),
        isNull,
      );
    });

    Future<void> open(
      ProviderContainer container,
      Future<void> Function() settle,
      String title,
    ) async {
      container.read(appRouterProvider).go(AppRoutes.notifications);
      await settle();
      // By its words: the order's number depends on what ran before.
      final target = find.textContaining(title).first;
      await tester.ensureVisible(target);
      await tester.pump();
      await tester.tap(target);
      await settle();
    }

    // The store: its new order, and its product.
    var (container, settle) = await pumpApp(tester, email: 'merchant@saba.app');
    await open(container, settle, 'New order SB-');
    expect(
      tester
          .widget<MerchantOrderDetailScreen>(
            find.byType(MerchantOrderDetailScreen),
          )
          .orderId,
      part,
    );
    await open(container, settle, 'Walk One is approved');
    expect(
      tester
          .widget<MerchantProductFormScreen>(
            find.byType(MerchantProductFormScreen),
          )
          .existing
          ?.id,
      productId,
    );

    // The shopper: the return.
    (container, settle) = await pumpApp(tester, email: 'shopper@saba.app');
    await open(container, settle, 'Nova Electronics will pick up your return');
    expect(
      tester
          .widget<ReturnDetailScreen>(find.byType(ReturnDetailScreen))
          .returnId,
      returnId,
    );
  });
}
