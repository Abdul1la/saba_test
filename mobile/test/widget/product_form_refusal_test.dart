// M3, against the real server: a product refused on its photos or its
// options - "Two options have the same choices." - saved nothing and said
// nothing, because the form draws no field for either. What it cannot show
// on a field it now says in a message.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/merchant/domain/entities.dart';
import 'package:saba_marketplace/features/merchant/presentation/merchant_providers.dart';
import 'package:saba_marketplace/features/merchant/presentation/screens/merchant_product_form_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _refusal = 'Two options have the same choices.';

/// The demo server, except that saving is refused as the real one refuses
/// two options with the same choices.
class _Refusing extends MerchantRepositoryImpl {
  const _Refusing(super.client);

  @override
  Future<Result<void>> saveProduct(ProductDraft draft) async =>
      const Result.err(
        ValidationFailure(
          message: _refusal,
          fieldErrors: [FieldError(field: 'variants', message: _refusal)],
        ),
      );
}

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
            case 'readAll':
              return Map<String, String>.from(store);
          }
          return null;
        });
  });
  tearDown(() => DioFactory.mockBackend.resetForTesting());

  testWidgets('a refusal the form has no field for is said, not swallowed', (
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
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        merchantRepositoryProvider.overrideWith(
          (ref) => _Refusing(ref.watch(apiClientProvider)),
        ),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    late MerchantProductRow row;
    await tester.runAsync(() async {
      (await container
              .read(authControllerProvider.notifier)
              .signIn(email: 'merchant@saba.app', password: 'Password1'))
          .unwrap();
      row = (await container.read(merchantRepositoryProvider).products())
          .unwrap()
          .items
          .firstWhere((r) => r.status == 'APPROVED');
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
    container
        .read(appRouterProvider)
        .push(AppRoutes.merchantProductForm, extra: row);
    await settle();
    expect(find.byType(MerchantProductFormScreen), findsOneWidget);

    final save = find.text('Save changes');
    await tester.ensureVisible(save.last);
    await tester.pump();
    await tester.tap(save.last);
    await settle();

    expect(find.text(_refusal), findsOneWidget, reason: 'refused in silence');
  });
}
