// Where things are: the shopper's city on Home, and every store saying
// which of Iraq's governorates it is in.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/config/api_endpoints.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/location/governorate.dart';
import 'package:saba_marketplace/core/location/governorate_picker.dart';
import 'package:saba_marketplace/core/location/store_delivery.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/utils/formatters.dart';
import 'package:saba_marketplace/core/widgets/app_text_field.dart';
import 'package:saba_marketplace/core/widgets/option_sheet.dart';
import 'package:saba_marketplace/features/addresses/domain/entities.dart';
import 'package:saba_marketplace/features/addresses/presentation/address_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/widgets/product_card.dart';
import 'package:saba_marketplace/features/home/presentation/home_providers.dart';
import 'package:saba_marketplace/features/home/presentation/widgets/home_products.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Where the image cache keeps its files; a test has no phone to ask.
const _paths = MethodChannel('plugins.flutter.io/path_provider');

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

  testWidgets("Home has no city button; the shopper's city is her profile's", (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.home);
    await settle();

    expect(find.text(_en.deliverToCity('Baghdad')), findsNothing);
    expect(find.text(_en.chooseYourCity), findsNothing);

    // A city picked on Home by an older version is still on the phone. It
    // must not win over her profile: nothing on screen could change it now.
    await tester.runAsync(
      () => container
          .read(shopperGovernorateProvider.notifier)
          .choose(Governorate.duhok),
    );
    expect(container.read(shopperCityProvider), Governorate.baghdad);
    // Her profile is where it changes, and that is what counts.
    await tester.runAsync(
      () => container
          .read(authControllerProvider.notifier)
          .updateProfile(governorate: 'ERBIL'),
    );
    expect(container.read(shopperCityProvider), Governorate.erbil);
    // Signed out, the one on the phone is all there is.
    await tester.runAsync(
      () => container.read(authControllerProvider.notifier).signOut(),
    );
    await settle();
    expect(container.read(shopperCityProvider), Governorate.duhok);
  });

  // The user: the chips sit right above "All products", the grid they
  // filter, and filter only it. Under the search bar they were far from it,
  // and the flash sale, the coupons and the featured stores above keep every
  // city's.
  testWidgets('the city chips sit above All products and filter only it', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.home);
    await settle();
    Set<Governorate?> saleCities() => {
      for (final card in tester.widgetList<FlashSaleCard>(
        find.byType(FlashSaleCard),
      ))
        card.product.merchantCity,
    };
    final everyCity = saleCities();
    expect(everyCity.length, greaterThan(1), reason: 'no mix to pick from');

    container
        .read(homeProductsControllerProvider.notifier)
        .selectCity(Governorate.basra);
    await settle();
    expect(saleCities(), everyCity, reason: 'the flash sale was filtered');

    await tester.scrollUntilVisible(
      find.text(_en.allProducts),
      300,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          )
          .first,
    );
    await tester.pump();
    final chips = tester.getRect(find.byType(HomeCityChips));
    final heading = tester.getRect(find.text(_en.allProducts));
    expect(chips.bottom, lessThanOrEqualTo(heading.top), reason: 'not above');
    expect(heading.top - chips.bottom, lessThan(80), reason: 'not beside it');
  });

  testWidgets('every store says where it is: its card, its page', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    final router = container.read(appRouterProvider);

    // The store cards on Home: Atlas, in Basra.
    router.go(AppRoutes.home);
    await settle();
    final homeCity = find.descendant(
      of: find.byType(StoreCity),
      matching: find.text('Basra'),
    );
    await tester.scrollUntilVisible(
      homeCity,
      300,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(homeCity, findsOneWidget, reason: 'the Home store card has no city');

    // The store card on a product page: Nova, in Baghdad.
    router.go(AppRoutes.productDetailPath('p-1'));
    await settle();
    final sellerCity = find.descendant(
      of: find.byType(CityLabel),
      matching: find.text('Baghdad'),
    );
    await tester.scrollUntilVisible(
      sellerCity,
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(sellerCity, findsWidgets, reason: 'the store card has no city');

    // The store's own page: the city, and the street it gave.
    router.go(AppRoutes.storefrontPath('m-2'));
    await settle();
    expect(
      find.text('Basra · Corniche Street, Al-Ashar'),
      findsOneWidget,
      reason: 'the store page does not say where the store is',
    );
  });

  testWidgets("a store says whether it comes to the shopper's city", (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'shopper@saba.app',
    );
    final router = container.read(appRouterProvider);
    // The product page says "No delivery to" three times now: a pill at the
    // top, the delivery block and the buy bar.
    Future<void> see(String text) async {
      final found = find.text(text);
      for (var i = 0; i < 20 && found.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await tester.pump();
      }
      expect(found, findsWidgets, reason: 'no "$text"');
    }

    // Her city is Baghdad, where Nova is: its in-city fee and time.
    router.go(AppRoutes.productDetailPath('p-1'));
    await settle();
    await see(
      [
        _en.deliversTo('Baghdad'),
        Formatters.money(3000, locale: 'en', currencyCode: 'IQD'),
        _en.delivery1to2Days,
      ].join(' · '),
    );

    // She has moved her delivery address to Erbil: Atlas does not go there
    // - said on its product, and on its own page.
    //
    // The *address*, not her profile city. These two lines and checkout have
    // to name one city, and the one a parcel goes to is the address's; a
    // shopper browsing from Erbil with a Baghdad address was shown Nova's
    // out-of-town price and then charged its in-town one.
    await tester.runAsync(() async {
      final addresses = container.read(addressListProvider.notifier);
      final home = container.read(defaultAddressProvider)!;
      (await container
              .read(addressRepositoryProvider)
              .update(
                Address(
                  id: home.id,
                  fullName: home.fullName,
                  phone: home.phone,
                  governorate: Governorate.erbil,
                  area: home.area,
                  landmark: home.landmark,
                  street: home.street,
                  label: home.label,
                  isDefault: true,
                ),
              ))
          .unwrap();
      await addresses.refresh();
    });
    await settle();
    router.go(AppRoutes.productDetailPath('p-2'));
    await settle();
    await see(_en.noDeliveryTo('Erbil'));
    router.go(AppRoutes.storefrontPath('m-2'));
    await settle();
    await see(_en.noDeliveryTo('Erbil'));
  });

  testWidgets('a store sets where it delivers, at a fee cash can pay', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'merchant2@saba.app',
    );
    container.read(appRouterProvider).go(AppRoutes.merchantStoreSettings);
    await settle();
    final form = find.byType(Scrollable).first;
    Finder field(String label) => find.descendant(
      of: find.widgetWithText(AppTextField, label),
      matching: find.byType(TextFormField),
    );

    await tapText(tester, _en.wholeIraq);
    await settle();
    await tester.enterText(field(_en.feeInYourCity), '2100');
    await tapText(tester, _en.saveChanges);
    await settle();
    // The fee is well above Save; it is checked all the same.
    await tester.scrollUntilVisible(
      find.text(_en.iqdSteps),
      -300,
      scrollable: form,
    );
    expect(find.text(_en.iqdSteps), findsOneWidget);

    await tester.enterText(field(_en.feeInYourCity), '2000');
    await tapText(tester, _en.saveChanges);
    await settle();
    final saved = await tester.runAsync(
      () async => StoreDelivery.fromJson(
        (await container
                .read(apiClientProvider)
                .get<Map<String, dynamic>>(
                  ApiEndpoints.merchantStoreSettings,
                  decoder: (envelope) => envelope.dataAsMap,
                ))
            .unwrap()['delivery'],
      ),
    );
    expect(
      saved!.governorates,
      Governorate.values.toSet(),
      reason: '"All of Iraq" was not saved',
    );
    expect(saved.feeInside, 2000);
  });

  testWidgets('a store changes its city in Store settings', (tester) async {
    final (container, settle) = await pumpApp(
      tester,
      email: 'merchant2@saba.app',
    );
    final router = container.read(appRouterProvider);

    router.go(AppRoutes.merchantStoreSettings);
    await settle();
    // Picked from the list, like everywhere else: no country, no typing.
    expect(find.text(_en.country), findsNothing);
    // The store's own city; Basra is among the delivery chips too.
    await tester.tap(
      find.descendant(
        of: find.byType(PickerField),
        matching: find.text('Basra'),
      ),
    );
    await settle();
    await tester.tap(
      find.descendant(
        of: find.byType(OptionSheet<Governorate>),
        matching: find.text('Erbil'),
      ),
    );
    await settle();
    await tapText(tester, _en.saveChanges);
    await settle();

    router.go(AppRoutes.storefrontPath('m-2'));
    await settle();
    expect(
      find.text('Erbil · Corniche Street, Al-Ashar'),
      findsOneWidget,
      reason: 'the new city did not reach the store page',
    );
  });
}
