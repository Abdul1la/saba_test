// Apple 1.2 and Google Play: an app where people talk and sell must let
// them report what they see and block who they talk to (the reviewer's item
// 3; backend 426336e). A shopper reports a product or a store; either side
// of a chat reports it or blocks the other; a block stops the writing on
// both sides and only the side that blocked can lift it. A review is
// reported by a shopper or a store, its own store's included; a guest signs
// in first.
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
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/auth/presentation/screens/login_screen.dart';
import 'package:saba_marketplace/features/reviews/presentation/widgets/report_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _en = AppLocalizations(Locale('en'));

/// The demo shopper's chat with Nova Electronics.
const _chat = 'conv-m-1-shoppersabaapp';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};

  setUp(() {
    store.clear();
    DioFactory.mockBackend.resetForTesting();
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
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// The app on a phone, signed in as [email] (a guest without one), at
  /// [route].
  Future<void> open(WidgetTester tester, String? email, String route) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saba.pref.onboarding_seen': true,
      'saba.pref.locale': 'en',
    });
    final preferences = await AppPreferences.create();
    final c = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    if (email != null) {
      await tester.runAsync(() async {
        (await c
                .read(authControllerProvider.notifier)
                .signIn(email: email, password: 'Password1'))
            .unwrap();
      });
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const SabaApp()),
    );
    await settle(tester);
    c.read(appRouterProvider).go(route);
    await settle(tester);
  }

  /// Picks [reason] in the report dialog titled [title] and sends it.
  Future<void> report(WidgetTester tester, String title, String reason) async {
    expect(find.text(title), findsOneWidget, reason: 'not the $title dialog');
    await tester.tap(find.text(reason));
    await tester.pump();
    await tester.tap(find.text(_en.submit));
    await settle(tester);
  }

  testWidgets('a shopper reports a product and a store', (tester) async {
    await open(tester, 'shopper@saba.app', AppRoutes.productDetailPath('p-1'));
    await tester.tap(find.byTooltip(_en.reportProduct));
    await settle(tester);
    await report(tester, _en.reportProduct, _en.reportCounterfeit);
    expect(find.text(_en.reportThanks), findsOneWidget);

    await open(tester, 'shopper@saba.app', AppRoutes.storefrontPath('m-1'));
    await tester.tap(find.byTooltip(_en.reportStore));
    await settle(tester);
    await report(tester, _en.reportStore, _en.reportMisleading);
    expect(find.text(_en.reportThanks), findsOneWidget);
  });

  testWidgets('a store does not report its own product or store', (
    tester,
  ) async {
    await open(tester, 'merchant@saba.app', AppRoutes.productDetailPath('p-1'));
    expect(find.byTooltip(_en.reportProduct), findsNothing);
    await open(tester, 'merchant@saba.app', AppRoutes.storefrontPath('m-1'));
    expect(find.byTooltip(_en.reportStore), findsNothing);
  });

  // The final review: a guest was asked why, then shown the server's refusal.
  testWidgets('a guest who reports a review signs in first', (tester) async {
    await open(tester, null, AppRoutes.merchantReviewsPath('m-1'));
    await tester.tap(find.byTooltip(_en.reportReview).first);
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ReportDialog), findsNothing, reason: 'asked why');
  });

  // Saba takes a store's report of a review, one of its own store's too
  // (backend, 2026-10-01).
  testWidgets('a store reports a review of its own store', (tester) async {
    await open(
      tester,
      'merchant@saba.app',
      AppRoutes.merchantReviewsPath('m-1'),
    );
    await tester.tap(find.byTooltip(_en.reportReview).first);
    await settle(tester);
    await report(tester, _en.reportReview, _en.reportOffensive);
    expect(find.text(_en.reportSubmitted), findsOneWidget);
  });

  testWidgets('a chat is reported, blocked and unblocked', (tester) async {
    await open(tester, 'shopper@saba.app', AppRoutes.conversationPath(_chat));
    expect(find.byType(TextField), findsOneWidget, reason: 'no message box');

    Future<void> menu(String item) async {
      await tester.tap(find.byTooltip(_en.moreOptions));
      await settle(tester);
      await tester.tap(find.text(item).last);
      await settle(tester);
    }

    await menu(_en.report);
    await report(tester, _en.reportChat, _en.reportSpam);
    expect(find.text(_en.reportThanks), findsOneWidget);

    // Asked first; then nobody writes, and the chat is still there.
    await menu(_en.block);
    expect(find.text(_en.blockTitle), findsOneWidget);
    await tester.tap(find.text(_en.block).last);
    await settle(tester);
    expect(find.text(_en.chatBlockedByMe), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'still writable');

    await tester.tap(find.text(_en.unblock).last);
    await settle(tester);
    expect(find.text(_en.chatBlockedByMe), findsNothing);
    expect(find.byType(TextField), findsOneWidget, reason: 'not open again');
  });

  testWidgets('the other side cannot write, nor lift the block', (
    tester,
  ) async {
    await open(tester, 'shopper@saba.app', AppRoutes.conversationPath(_chat));
    await tester.tap(find.byTooltip(_en.moreOptions));
    await settle(tester);
    await tester.tap(find.text(_en.block).last);
    await settle(tester);
    await tester.tap(find.text(_en.block).last);
    await settle(tester);
    expect(find.text(_en.chatBlockedByMe), findsOneWidget);

    await open(tester, 'merchant@saba.app', AppRoutes.conversationPath(_chat));
    expect(find.text(_en.chatBlocked), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(_en.unblock), findsNothing, reason: "not the store's");
  });
}
