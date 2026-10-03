// A shopper talks to a store from where they meet it.
//
// The chat existed, but only as Account > Messages, and only for chats the
// demo had already written: nothing in the app could start one. The Message
// button on a product opens the chat with the store that sells it, headed
// with that store's name, and Home carries the way back to every chat.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/widgets/section_header.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/messaging/presentation/screens/messaging_screens.dart';
import 'package:saba_marketplace/features/messaging/presentation/widgets/message_store_button.dart';
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

  /// The app on a phone, signed in as [email].
  Future<(ProviderContainer, Future<void> Function())> pumpApp(
    WidgetTester tester,
    String email,
  ) async {
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
          .signIn(email: email, password: 'Password1');
    });

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

  testWidgets('Message on a product opens the chat with its store', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(tester, 'demo@saba.app');

    // --- from Home, one tap to every chat ---------------------------------
    container.read(appRouterProvider).go(AppRoutes.home);
    await settle();
    await tester.tap(find.byTooltip(_en.messages));
    await settle();
    expect(
      find.byType(ConversationsScreen),
      findsOneWidget,
      reason: 'Home has no way to the chats',
    );

    // --- from a product, one tap to its store -----------------------------
    container.read(appRouterProvider).go(AppRoutes.productDetailPath('p-1'));
    await settle();
    final seller = container
        .read(productProvider('p-1'))
        .requireValue
        .merchant!;

    final message = find.byType(MessageStoreButton);
    // In the seller's block, below the description and delivery.
    await tester.scrollUntilVisible(
      message,
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(message, findsOneWidget, reason: 'the product has no Message');
    await tester.ensureVisible(message);
    await tester.pump();
    await tester.tap(message);
    await settle();

    expect(find.byType(ConversationScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SabaAppBar),
        matching: find.text(seller.storeName),
      ),
      findsOneWidget,
      reason: 'the chat does not say who it is with',
    );
    final product = container.read(productProvider('p-1')).requireValue;
    final about = _en.aboutTopic(product.name).trim();
    // Above the box, not in it: a tap inside it split the message (the
    // tester), and the box starts empty.
    expect(find.text(about), findsOneWidget, reason: 'which product it is');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.enterText(find.byType(TextField), 'Is it in black?');
    await tester.tap(find.byTooltip(_en.send));
    await settle();
    expect(
      find.text('$about Is it in black?'),
      findsOneWidget,
      reason: 'the store is not told which product the question is about',
    );
    expect(find.text(about), findsNothing, reason: 'said once, not twice');
  });

  testWidgets('a customer waiting is on the dashboard, one tap from the chat', (
    tester,
  ) async {
    final (container, settle) = await pumpApp(tester, 'merchant@saba.app');
    container.read(appRouterProvider).go(AppRoutes.merchantDashboard);
    await settle();

    // The demo store has one customer still waiting, Sara Ahmed.
    final row = find.text(
      '${_en.counted(1, CountNoun.customer)} ${_en.waitingReplySuffix}',
    );
    expect(
      row,
      findsOneWidget,
      reason: 'a waiting customer is not on the list',
    );
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await settle();

    expect(find.byType(ConversationScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SabaAppBar),
        matching: find.text('Sara Ahmed'),
      ),
      findsOneWidget,
      reason: 'the row did not open the waiting chat',
    );
  });
}
