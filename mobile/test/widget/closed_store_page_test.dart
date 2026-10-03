// M3 step 11: a closed store's products leave search and its page, but one a
// shopper saved still opens from the wishlist - and the page must say the
// store is closed instead of offering to sell.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/widgets/app_button.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/catalog_providers.dart';
import 'package:saba_marketplace/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/wishlist/presentation/wishlist_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

  testWidgets('a saved product of a closed store opens, saying it is closed', (
    tester,
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
    late String name;
    await tester.runAsync(() async {
      final auth = container.read(authControllerProvider.notifier);
      (await auth.signIn(
        email: 'merchant@saba.app',
        password: 'Password1',
      )).unwrap();
      (await container.read(merchantRepositoryProvider).setOpen(false))
          .unwrap();
      await auth.signOut();
      (await auth.signIn(
        email: 'shopper@saba.app',
        password: 'Password1',
      )).unwrap();
      (await container.read(wishlistRepositoryProvider).add('p-1')).unwrap();
      name = (await container.read(catalogRepositoryProvider).fetchProduct(
        'p-1',
      )).unwrap().name;
    });

    Future<void> settle() async {
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SabaApp()),
    );
    await settle();
    container.read(appRouterProvider).push(AppRoutes.wishlist);
    await settle();
    await tester.tap(find.text(name).first);
    await settle();

    expect(find.byType(ProductDetailScreen), findsOneWidget);
    expect(
      find.text('This store is closed right now. Come back later.'),
      findsOneWidget,
    );
    for (final label in ['Add to cart', 'Buy now']) {
      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, label),
      );
      expect(button.onPressed, isNull, reason: '$label on a closed store');
    }
  });
}
