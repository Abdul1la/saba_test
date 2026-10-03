// Photos in chats, both ways (the backend's brief 2026-10-01): a photo button
// by the message box sends a picture; it shows in the thread and opens full
// size; the chat list says "Photo"; a removed one leaves a line. The picker is
// faked, so no gallery or camera is touched.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/app.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/network/api_response.dart';
import 'package:saba_marketplace/core/network/dio_factory.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/router/app_router.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/widgets/app_network_image.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/media/domain/entities.dart';
import 'package:saba_marketplace/features/media/domain/media_repository.dart';
import 'package:saba_marketplace/features/media/presentation/media_providers.dart';
import 'package:saba_marketplace/features/messaging/presentation/messaging_providers.dart';
import 'package:saba_marketplace/features/messaging/presentation/screens/photo_viewer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keystore = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _en = AppLocalizations(Locale('en'));
const _chat = 'conv-m-1-shoppersabaapp';

/// Hands back one picture, so no gallery or camera is opened.
class _FakePicker implements MediaPicker {
  const _FakePicker();

  PickedMedia get _one => PickedMedia(
    fileName: 'snap.png',
    sizeBytes: 8,
    mimeType: 'image/png',
    bytes: Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]),
  );

  @override
  Future<List<PickedMedia>> pickImages({
    required MediaConstraints constraints,
    bool multiple = true,
  }) async => [_one];

  @override
  Future<PickedMedia?> captureImage({
    required MediaConstraints constraints,
  }) async => _one;

  @override
  Future<List<PickedMedia>> pickFiles({
    required MediaConstraints constraints,
    bool multiple = true,
  }) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  final backend = DioFactory.mockBackend;

  setUp(() {
    store.clear();
    backend.resetForTesting();
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
  tearDown(backend.resetForTesting);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<ProviderContainer> open(
    WidgetTester tester, {
    MessagingRepository? repo,
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
    final c = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        mediaPickerProvider.overrideWithValue(const _FakePicker()),
        if (repo != null) messagingRepositoryProvider.overrideWithValue(repo),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      (await c
              .read(authControllerProvider.notifier)
              .signIn(email: 'shopper@saba.app', password: 'Password1'))
          .unwrap();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const SabaApp()),
    );
    await settle(tester);
    return c;
  }

  testWidgets('a photo is sent, shows in the thread, and says "Photo" in the '
      'list', (tester) async {
    final c = await open(tester);
    c.read(appRouterProvider).go(AppRoutes.conversationPath(_chat));
    await settle(tester);

    await tester.tap(find.byTooltip(_en.sendPhoto));
    await settle(tester);
    await tester.tap(find.text(_en.chooseFromGallery));
    await settle(tester);

    // The picture is in the thread.
    expect(find.byType(AppNetworkImage), findsWidgets);

    // Tapping it opens the full-size viewer.
    await tester.tap(find.byType(AppNetworkImage).last);
    await settle(tester);
    expect(find.byType(PhotoViewerScreen), findsOneWidget);
    await tester.tap(find.byTooltip(_en.close));
    await settle(tester);

    // The chat list shows "Photo" where the last message's words would be.
    c.read(appRouterProvider).go(AppRoutes.conversations);
    await settle(tester);
    expect(find.text(_en.photo), findsWidgets);
  });

  testWidgets('a removed photo leaves a line, not an image', (tester) async {
    final c = await open(tester, repo: const _RemovedPhotoRepo());
    c.read(appRouterProvider).go(AppRoutes.conversationPath(_chat));
    await settle(tester);

    expect(find.text(_en.photoDeleted), findsOneWidget);
    expect(find.text(_en.photoRemovedBySaba), findsOneWidget);
    expect(find.byType(AppNetworkImage), findsNothing);
  });
}

/// A thread of two removed photos: one whose sender's account was deleted, one
/// Saba took down.
class _RemovedPhotoRepo implements MessagingRepository {
  const _RemovedPhotoRepo();

  @override
  Future<Result<PaginatedList<Message>>> messages(
    String conversationId, {
    int page = 1,
  }) async => Ok<PaginatedList<Message>>(
    PaginatedList<Message>(
      // Newest first, as the controller reverses.
      items: [
        Message(
          id: 'm2',
          body: '',
          sentAt: DateTime(2026, 10, 2, 10, 1),
          isMine: false,
          photoRemoved: PhotoRemoval.saba,
        ),
        Message(
          id: 'm1',
          body: '',
          sentAt: DateTime(2026, 10, 2, 10),
          isMine: true,
          photoRemoved: PhotoRemoval.account,
        ),
      ],
      meta: const PaginationMeta(page: 1, perPage: 20, total: 2, totalPages: 1),
    ),
  );

  @override
  Future<Result<Conversation>> conversation(String conversationId) async =>
      Ok<Conversation>(
        Conversation(
          id: conversationId,
          title: 'Nova Electronics',
          updatedAt: DateTime(2026, 10, 2, 10, 1),
        ),
      );

  @override
  Future<Result<List<Conversation>>> conversations() async =>
      const Ok<List<Conversation>>(<Conversation>[]);

  @override
  Future<Result<Conversation>> startWithStore(String merchantId) =>
      conversation('c');

  @override
  Future<Result<Message>> send({
    required String conversationId,
    required String body,
  }) async => Ok<Message>(
    Message(id: 'x', body: body, sentAt: DateTime.now(), isMine: true),
  );

  @override
  Future<Result<Message>> sendPhoto({
    required String conversationId,
    required PickedMedia photo,
  }) async => Ok<Message>(
    Message(id: 'x', body: '', sentAt: DateTime.now(), isMine: true),
  );

  @override
  Future<Result<void>> markRead(String conversationId) async =>
      const Ok<void>(null);

  @override
  Future<Result<Conversation>> setBlocked(
    String conversationId, {
    required bool blocked,
  }) => conversation(conversationId);
}
