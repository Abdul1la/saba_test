// One merchant, one morning's work, done by tapping.
//
// The sweep proves every merchant screen draws. This proves the job can be
// done: the dashboard says orders are waiting, that row opens those orders,
// an order opens its packing slip, the address is copyable, and the button at
// the bottom moves the order on — with the dashboard's own to-do list
// agreeing afterwards, because a queue that does not change is how a merchant
// confirms the same order twice.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/widgets/filter_chip_row.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';
import 'package:saba_marketplace/core/utils/formatters.dart';
import 'package:saba_marketplace/core/widgets/app_button.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/widgets/app_text_field.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_order_detail_screen.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_product_form_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _en = AppLocalizations(Locale('en'));

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

  Future<ProviderContainer> openStore(WidgetTester tester) async {
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

    await tester.runAsync(() async {
      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'merchant@saba.app', password: 'Password1');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );
    return container;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> press(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  // BUGS.md 56: delivered orders sat under "Shipped", counted with it.
  testWidgets('a delivered order leaves "Shipped" for its own tab', (
    tester,
  ) async {
    final container = await openStore(tester);
    await settle(tester);
    container.read(appRouterProvider).go(AppRoutes.merchantOrders);
    await settle(tester);

    final counts = container.read(merchantOrderCountsProvider).requireValue;
    expect(counts['DELIVERED'], greaterThan(0));
    final labels = tester
        .widget<TextFilterChips>(find.byType(TextFilterChips))
        .labels;
    expect(
      labels,
      contains('${_en.orderStatusShipped} · ${counts['SHIPPED'] ?? 0}'),
      reason: 'the Shipped tab counts delivered orders',
    );
    expect(
      labels,
      contains('${_en.orderStatusDelivered} · ${counts['DELIVERED']}'),
    );
  });

  testWidgets('a merchant confirms a waiting order without typing', (
    tester,
  ) async {
    final container = await openStore(tester);
    await settle(tester);
    container.read(appRouterProvider).go(AppRoutes.merchantDashboard);
    await settle(tester);

    // --- the dashboard says there is work ---------------------------------
    final waiting = find.textContaining(_en.toConfirmSuffix);
    expect(
      waiting,
      findsOneWidget,
      reason: 'the dashboard did not say any order was waiting',
    );
    await press(tester, waiting);

    // --- and that row opens those orders, not all of them ------------------
    expect(
      container
          .read(appRouterProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path,
      AppRoutes.merchantOrders,
    );
    // Bucket 0 is "To confirm"; landing anywhere else means the row opened a
    // queue that is not the one it counted.
    expect(find.textContaining(_en.toConfirm), findsWidgets);

    // The store's new orders are PENDING, as the real server says it
    // (BACKEND_PLAN.md 8.4): a tab still asking for NEW lists none.
    expect(
      find.textContaining('SB-'),
      findsWidgets,
      reason: '"To confirm" asked for a status no order has',
    );

    // --- open the first one -----------------------------------------------
    final card = find.textContaining('SB-').first;
    await press(tester, card);
    expect(
      find.byType(MerchantOrderDetailScreen),
      findsOneWidget,
      reason: 'an order in the queue did not open',
    );

    // Everything needed to pack it is on the screen.
    expect(find.text(_en.shippingAddress), findsWidgets);
    expect(find.text(_en.orderItems), findsOneWidget);

    // --- the address goes on the parcel in one tap ------------------------
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final advance = find.textContaining(_en.nextStatus);
    expect(advance, findsOneWidget, reason: 'no way to advance the order');
    await press(tester, find.textContaining('Baghdad').first);
    expect(
      copied,
      contains('Baghdad'),
      reason: 'the shipping address could not be copied',
    );

    // The copy confirms in place, on the row, rather than with a snackbar.
    expect(
      tester.widgetList(find.byType(SnackBar)),
      isEmpty,
      reason: 'the copy should confirm on the row, not in a snackbar',
    );

    // --- and what the driver takes at the door ------------------------------
    await tester.scrollUntilVisible(
      find.text(_en.collectInCash),
      300,
      scrollable: find
          .descendant(
            of: find.byType(MerchantOrderDetailScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text(_en.collectInCash), findsOneWidget);

    // --- and the order moves on, once the shopper has been called ---------
    await press(tester, advance);
    await press(tester, find.text(_en.iCalledConfirm));

    final moved = await tester.runAsync(
      () async =>
          (await container.read(merchantRepositoryProvider).order('mo-1'))
              .unwrap(),
    );
    expect(
      moved!.row.status,
      isNot('PENDING'),
      reason: 'the button reported success and the order did not move',
    );
  });

  testWidgets('a merchant edits a product they can see', (tester) async {
    final container = await openStore(tester);
    await settle(tester);
    container.read(appRouterProvider).go(AppRoutes.merchantProducts);
    await settle(tester);

    expect(find.text(_en.myProducts), findsOneWidget);

    // The pencil on the first shelf row, which is the whole reason the row
    // has icons at all.
    final edit = find.byTooltip(_en.edit).first;
    await press(tester, edit);

    expect(
      find.byType(MerchantProductFormScreen),
      findsOneWidget,
      reason: 'Edit did not open the product form',
    );
    // Editing, not creating: the form has to arrive carrying the whole
    // product, not the four fields the shelf row happens to hold. It was
    // built from that row, so the merchant edited a product without being
    // shown its description — and the picker was seeded with the single
    // thumbnail, which made Save send a one-image list and reduce a product
    // with three photographs to one.
    final filled = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller?.text ?? '')
        .where((text) => text.trim().isNotEmpty)
        .toList();
    expect(
      filled,
      isNotEmpty,
      reason: 'the edit form opened blank instead of carrying the product',
    );

    // The description only ever comes from the full record.
    expect(
      filled.any((text) => text.length > 40),
      isTrue,
      reason:
          'the description did not arrive, so the form is still being '
          'built from the shelf row',
    );

    // And every photograph is loaded, so saving cannot shorten the list.
    final product = await tester.runAsync(
      () async =>
          (await container.read(merchantRepositoryProvider).product('p-1'))
              .unwrap(),
    );
    expect(product!.media.length, greaterThan(1));
  });

  testWidgets('a price cash cannot pay is refused, in steps of 250', (
    tester,
  ) async {
    final container = await openStore(tester);
    await settle(tester);
    container.read(appRouterProvider).go(AppRoutes.merchantProducts);
    await settle(tester);
    await press(tester, find.byTooltip(_en.edit).first);

    final form = find
        .descendant(
          of: find.byType(MerchantProductFormScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text(_en.price).first,
      300,
      scrollable: form,
    );
    final price = find.descendant(
      of: find.widgetWithText(AppTextField, _en.price).first,
      matching: find.byType(TextFormField),
    );
    await tester.enterText(price, '12300');
    await settle(tester);
    // Save is at the bottom, the price well above it: the form still checks
    // it. It checked only what was on screen while it was a lazy list.
    await tester.scrollUntilVisible(
      find.text(_en.saveChanges),
      300,
      scrollable: form,
    );
    await press(tester, find.text(_en.saveChanges));
    await tester.scrollUntilVisible(
      find.text(_en.iqdSteps),
      -300,
      scrollable: form,
    );
    expect(
      find.text(_en.iqdSteps),
      findsOneWidget,
      reason: 'a price no driver can take in cash was accepted',
    );
  });

  testWidgets('a merchant ships it with the driver named, or it is refused', (
    tester,
  ) async {
    final container = await openStore(tester);
    await settle(tester);
    // One of Nova's orders being prepared, the step before it goes out.
    final preparing = await tester.runAsync(
      () async =>
          (await container
                  .read(merchantRepositoryProvider)
                  .orders(status: 'PROCESSING'))
              .unwrap()
              .items
              .first,
    );
    container
        .read(appRouterProvider)
        .go(AppRoutes.merchantOrderDetailPath(preparing!.id));
    await settle(tester);

    await press(tester, find.textContaining(_en.nextStatus));
    expect(find.text(_en.whoDelivers), findsOneWidget);
    // Nobody named: the sheet stays, and says what is missing.
    await press(tester, find.text(_en.markAsShipped));
    expect(find.text(_en.validationRequired), findsWidgets);

    Finder field(String label) => find.descendant(
      of: find.widgetWithText(AppTextField, label),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(field(_en.driverName), 'Ali');
    await tester.enterText(field(_en.phone), '07701112222');
    await press(tester, find.text(_en.markAsShipped));

    // Out with Ali: his number to call, and delivered or refused to choose.
    expect(find.text(_en.whoDelivers), findsOneWidget);
    expect(find.text('Ali'), findsOneWidget, reason: 'the driver is not shown');
    expect(find.text(_en.refusedAtDoor), findsOneWidget);
    // And Delivered beside it (the tester found none).
    expect(
      find.text(_en.orderStatusDelivered),
      findsOneWidget,
      reason: 'no Delivered button on the order page',
    );
    await press(tester, find.text(_en.refusedAtDoor));
    await press(tester, find.text(_en.refusedAtDoor).last);
    final after = await tester.runAsync(
      () async =>
          (await container.read(merchantRepositoryProvider).order(preparing.id))
              .unwrap(),
    );
    expect(after!.row.status, 'REFUSED');
  });

  testWidgets('a store closes from its dashboard, and sees what it owes', (
    tester,
  ) async {
    final container = await openStore(tester);
    await settle(tester);
    container.read(appRouterProvider).go(AppRoutes.merchantDashboard);
    await settle(tester);

    // The line says exactly which of the four states the store is in, not
    // just open or closed - a store waiting for approval used to read
    // "Store closed" with no switch and no explanation.
    expect(find.text(_en.storeApprovedOpen), findsOneWidget);
    await press(tester, find.byType(Switch));
    expect(find.text(_en.storeApprovedClosed), findsOneWidget);
    expect(find.text(_en.storeNowClosed), findsOneWidget);
    final dashboard = await tester.runAsync(
      () async => (await container.read(merchantRepositoryProvider).dashboard())
          .unwrap(),
    );
    expect(dashboard!.isOpen, isFalse, reason: 'the switch did not close it');

    // What it owes Saba, one tap from the account page.
    container.read(appRouterProvider).go(AppRoutes.merchantAccount);
    await settle(tester);
    await press(tester, find.text(_en.oweSaba));
    expect(find.text(_en.oweThisMonth), findsOneWidget);
    expect(find.text(_en.youOwe), findsOneWidget);
    // ...and the months before, as the admin web bills them.
    expect(find.text(_en.noPastMonths), findsNothing);
    expect(find.text(_en.billDue), findsWidgets);
  });

  testWidgets('a product is not saved without its name in Arabic', (
    tester,
  ) async {
    final container = await openStore(tester);
    await settle(tester);
    container.read(appRouterProvider).go(AppRoutes.merchantProducts);
    await settle(tester);
    await press(tester, find.byTooltip(_en.edit).first);

    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    final arabic = find.widgetWithText(AppTextField, _en.nameInArabic);
    expect(arabic, findsOneWidget);
    final form = find
        .descendant(
          of: find.byType(MerchantProductFormScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> save() async {
      await tester.scrollUntilVisible(
        find.text(_en.saveChanges),
        300,
        scrollable: form,
      );
      await press(tester, find.text(_en.saveChanges));
      await tester.scrollUntilVisible(arabic, -300, scrollable: form);
      await settle(tester);
    }

    // The product's Arabic name is already in; taken out, the save stops.
    final arabicField = find.descendant(
      of: arabic,
      matching: find.byType(TextFormField),
    );
    expect(
      find.descendant(of: arabic, matching: find.text('هاتف نوفا X5 الذكي')),
      findsOneWidget,
      reason: 'the form did not open with the Arabic name',
    );
    await tester.enterText(arabicField, '');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await save();
    expect(
      find.descendant(of: arabic, matching: find.text(_en.validationRequired)),
      findsOneWidget,
      reason: 'saved with no Arabic name',
    );
    await tester.enterText(
      find.descendant(of: arabic, matching: find.byType(TextFormField)),
      'Earbuds',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await save();
    expect(
      find.descendant(
        of: arabic,
        matching: find.text(_en.validationArabicLetters),
      ),
      findsOneWidget,
      reason: 'English letters taken as Arabic',
    );
  });

  testWidgets('typing a new stock figure replaces the old one', (tester) async {
    final container = await openStore(tester);
    await settle(tester);
    container.read(appRouterProvider).go(AppRoutes.merchantInventory);
    await settle(tester);

    // Open the adjust sheet on the first row.
    await press(tester, find.byTooltip(_en.adjustStock).first);
    expect(find.text(_en.stockAdjustment), findsOneWidget);

    final field = find.byType(TextField).last;
    final before = tester.widget<TextField>(field).controller!.text;
    expect(
      before,
      isNotEmpty,
      reason: 'the sheet should show what the stock is now',
    );

    // The old figure has to be SELECTED, not merely shown, because that is
    // what makes the first keystroke replace it. Asserting on entered text
    // proves nothing here: the test harness sets the whole editing value at
    // once, so it reads the same whether the caret sits at the end or the
    // number is highlighted. The selection is the actual mechanism, so the
    // selection is what is checked.
    final selection = tester.widget<TextField>(field).controller!.selection;
    expect(
      selection.textInside(before),
      before,
      reason:
          'the old stock was not selected, so typing would append to it '
          '- 18 becomes 185 and the product oversells',
    );
  });

  // M3 step 8 (the backend): a product sold in options has its stock set per
  // option. The shelf's stepper and Restock set one number for the whole, and
  // the server refuses that with 422.
  testWidgets('a product sold in options has no whole-product stock control', (
    tester,
  ) async {
    final container = await openStore(tester);
    late List<MerchantProductRow> rows;
    await tester.runAsync(() async {
      rows = (await container.read(merchantRepositoryProvider).products())
          .unwrap()
          .items;
    });
    final options = rows.firstWhere((r) => r.hasVariants);
    final plain = rows.firstWhere((r) => !r.hasVariants && !r.isOutOfStock);
    await settle(tester);
    container.read(appRouterProvider).go(AppRoutes.merchantProducts);
    await settle(tester);

    Future<Finder> rowOf(String name) async {
      await tester.enterText(find.byType(TextField).first, name);
      await settle(tester);
      return find
          .ancestor(of: find.text(name), matching: find.byType(InkWell))
          .first;
    }

    final plainRow = await rowOf(plain.name);
    expect(
      find.descendant(of: plainRow, matching: find.byTooltip(_en.increase)),
      findsOneWidget,
    );
    final optionsRow = await rowOf(options.name);
    for (final control in [
      find.byTooltip(_en.increase),
      find.byTooltip(_en.decrease),
      find.widgetWithText(AppButton, _en.restock),
    ]) {
      expect(
        find.descendant(of: optionsRow, matching: control),
        findsNothing,
        reason: '${options.name} is sold in options',
      );
    }
  });

  testWidgets('a store puts a product on a flash sale, and ends it', (
    tester,
  ) async {
    final container = await openStore(tester);
    await settle(tester);
    container.read(appRouterProvider).go(AppRoutes.merchantProducts);
    await settle(tester);
    // Nova's headphones, on no sale yet.
    final product = MockData.productById('p-5')!;
    final price = (product['price'] as num).toInt();
    await tester.enterText(
      find.byType(TextField).first,
      product['name'] as String,
    );
    await settle(tester);

    final start = find.widgetWithText(AppButton, _en.flashSale);
    expect(start, findsOneWidget);
    await press(tester, start);
    final field = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );

    // In cash steps, and below the price it has now.
    await tester.enterText(field, '${price - 100}');
    await press(tester, find.text(_en.startSale));
    expect(find.text(_en.iqdSteps), findsOneWidget);
    await tester.enterText(field, '$price');
    await press(tester, find.text(_en.startSale));
    expect(find.text(_en.salePriceNotLower), findsOneWidget);

    await tester.enterText(field, '${price - 45000}');
    await press(tester, find.text(_en.startSale));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text(_en.flashSaleSaved), findsOneWidget);
    final chip = find.textContaining(_en.flashSaleUntil('').trim());
    expect(chip, findsOneWidget, reason: 'the row does not say it is on sale');
    expect(start, findsNothing);

    // The chip opens it again. The price it compares with is the one
    // without the sale: it was called "the price now" while the price now
    // was the sale's.
    await press(tester, chip);
    expect(
      find.text(
        _en.normalPrice(
          Formatters.money(price, locale: 'en', currencyCode: 'IQD'),
        ),
      ),
      findsOneWidget,
    );

    // Ended only once the store says so: every shopper's price changes.
    await press(tester, find.text(_en.endSaleNow));
    expect(find.text(_en.endSaleQuestion), findsOneWidget);
    expect(chip, findsOneWidget, reason: 'ended before the store said so');
    await press(tester, find.text(_en.endSaleNow).last);
    expect(find.text(_en.flashSaleEnded), findsOneWidget);
    expect(chip, findsNothing);
    expect(start, findsOneWidget);

    // Hidden from shoppers, it is on no sale either.
    await press(tester, find.byTooltip(_en.hideFromShoppers));
    expect(start, findsNothing, reason: 'a hidden product offered a sale');
  });

  // The same order showed its driver as +9647705550311 and its customer as
  // +964 780 555 0117.
  testWidgets('an order shows every number the one way', (tester) async {
    final container = await openStore(tester);
    await settle(tester);
    late String part;
    await tester.runAsync(() async {
      part =
          (await container
                  .read(merchantRepositoryProvider)
                  .orders(status: 'SHIPPED'))
              .unwrap()
              .items
              .first
              .id;
    });
    container
        .read(appRouterProvider)
        .go(AppRoutes.merchantOrderDetailPath(part));
    await settle(tester);

    final numbers = [
      for (final text in tester.widgetList<Text>(find.byType(Text)))
        if ((text.data ?? '').contains('+964')) text.data!,
    ];
    expect(numbers, hasLength(2), reason: 'the customer and the driver');
    for (final number in numbers) {
      expect(number, matches(RegExp(r'\+964 7\d\d \d{3} \d{4}')));
    }
  });
}
