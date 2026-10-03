import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/features/media/domain/entities.dart';
import 'package:saba_marketplace/features/media/domain/media_repository.dart';
import 'package:saba_marketplace/features/media/presentation/media_providers.dart';

PickedMedia _file(String name) => PickedMedia(
  fileName: name,
  mimeType: 'image/jpeg',
  sizeBytes: 1024,
  bytes: Uint8List.fromList(<int>[1, 2, 3]),
  width: 800,
  height: 800,
);

class _FakeCancelToken implements UploadCancelToken {
  final Completer<void> _cancelled = Completer<void>();

  @override
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  @override
  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get onCancel => _cancelled.future;
}

/// A repository whose behaviour is chosen per file name, so a test can make
/// exactly one item in a batch fail.
class _FakeMediaRepository implements MediaRepository {
  _FakeMediaRepository({
    this.failFor = const <String>{},
    this.hangFor = const <String>{},
  });

  final Set<String> failFor;

  /// Files that never resolve until their cancel token fires.
  final Set<String> hangFor;

  final List<String> deleted = <String>[];
  final List<String> uploadAttempts = <String>[];

  @override
  UploadCancelToken createCancelToken() => _FakeCancelToken();

  @override
  Future<Result<UploadedMedia>> upload(
    PickedMedia media, {
    UploadProgressCallback? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    uploadAttempts.add(media.fileName);
    onProgress?.call(512, 1024);

    if (hangFor.contains(media.fileName)) {
      await (cancelToken! as _FakeCancelToken).onCancel;
      return const Err<UploadedMedia>(CancelledFailure());
    }

    if (failFor.contains(media.fileName)) {
      return const Err<UploadedMedia>(ServerFailure(message: 'boom'));
    }

    return Ok<UploadedMedia>(
      UploadedMedia(
        id: 'remote-${media.fileName}',
        url: 'https://cdn.example.com/${media.fileName}',
        kind: MediaKind.image,
        fileName: media.fileName,
      ),
    );
  }

  @override
  Future<Result<void>> delete(String mediaId) async {
    deleted.add(mediaId);
    return const Result<void>.ok(null);
  }
}

ProviderContainer _containerWith(_FakeMediaRepository repository) {
  final container = ProviderContainer(
    overrides: [mediaRepositoryProvider.overrideWithValue(repository)],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  return container;
}

const MediaSlot _slot = MediaSlot(
  id: 'test-slot',
  constraints: MediaConstraints.productImages,
);

void main() {
  test('uploads a batch and exposes the finished media in order', () async {
    final repository = _FakeMediaRepository();
    final container = _containerWith(repository);
    final controller = container.read(mediaUploadProvider(_slot).notifier);

    await controller.addPicked([_file('a.jpg'), _file('b.jpg')]);
    await pumpEventQueue();

    final items = container.read(mediaUploadProvider(_slot));
    expect(items, hasLength(2));
    expect(items.every((item) => item.isDone), isTrue);
    expect(controller.uploadedMedia.map((media) => media.id), [
      'remote-a.jpg',
      'remote-b.jpg',
    ]);
  });

  test('a failed item does not lose the others', () async {
    final repository = _FakeMediaRepository(failFor: {'bad.jpg'});
    final container = _containerWith(repository);
    final controller = container.read(mediaUploadProvider(_slot).notifier);

    await controller.addPicked([
      _file('a.jpg'),
      _file('bad.jpg'),
      _file('b.jpg'),
    ]);
    await pumpEventQueue();

    final items = container.read(mediaUploadProvider(_slot));

    // All three rows survive; only the middle one is marked failed.
    expect(items, hasLength(3));
    expect(items[0].status, MediaUploadStatus.completed);
    expect(items[1].status, MediaUploadStatus.failed);
    expect(items[2].status, MediaUploadStatus.completed);

    expect(items[1].failure, isA<ServerFailure>());
    expect(controller.uploadedMedia, hasLength(2));
    expect(controller.hasFailures, isTrue);
  });

  test(
    'retrying a failed item does not re-upload the successful ones',
    () async {
      final repository = _FakeMediaRepository(failFor: {'bad.jpg'});
      final container = _containerWith(repository);
      final controller = container.read(mediaUploadProvider(_slot).notifier);

      await controller.addPicked([_file('a.jpg'), _file('bad.jpg')]);
      await pumpEventQueue();

      final failed = container
          .read(mediaUploadProvider(_slot))
          .firstWhere((item) => item.status == MediaUploadStatus.failed);

      repository.failFor.clear();
      await controller.retry(failed.localId);
      await pumpEventQueue();

      final items = container.read(mediaUploadProvider(_slot));
      expect(items.every((item) => item.isDone), isTrue);
      // a.jpg once, bad.jpg twice.
      expect(repository.uploadAttempts, ['a.jpg', 'bad.jpg', 'bad.jpg']);
    },
  );

  test('cancellation stops an upload without reporting an error', () async {
    final repository = _FakeMediaRepository(hangFor: {'slow.jpg'});
    final container = _containerWith(repository);
    final controller = container.read(mediaUploadProvider(_slot).notifier);

    await controller.addPicked([_file('slow.jpg')]);
    await pumpEventQueue();

    var item = container.read(mediaUploadProvider(_slot)).single;
    expect(item.status, MediaUploadStatus.uploading);
    expect(item.progress, 0.5);

    controller.cancel(item.localId);
    await pumpEventQueue();

    item = container.read(mediaUploadProvider(_slot)).single;
    expect(item.status, MediaUploadStatus.cancelled);
    // A cancellation is a user action, not an error worth showing.
    expect(item.failure, isNull);
    expect(item.canRetry, isTrue);
    expect(controller.uploadedMedia, isEmpty);
  });

  test('cancelling one upload leaves the others running', () async {
    final repository = _FakeMediaRepository(hangFor: {'slow.jpg'});
    final container = _containerWith(repository);
    final controller = container.read(mediaUploadProvider(_slot).notifier);

    await controller.addPicked([_file('slow.jpg'), _file('fast.jpg')]);
    await pumpEventQueue();

    final slow = container
        .read(mediaUploadProvider(_slot))
        .firstWhere((item) => item.displayName == 'slow.jpg');
    controller.cancel(slow.localId);
    await pumpEventQueue();

    final items = container.read(mediaUploadProvider(_slot));
    expect(items, hasLength(2));
    expect(
      items.firstWhere((item) => item.displayName == 'fast.jpg').status,
      MediaUploadStatus.completed,
    );
    expect(controller.uploadedMedia, hasLength(1));
  });

  test('removing an uploaded item deletes it on the server too', () async {
    final repository = _FakeMediaRepository();
    final container = _containerWith(repository);
    final controller = container.read(mediaUploadProvider(_slot).notifier);

    await controller.addPicked([_file('a.jpg')]);
    await pumpEventQueue();

    final item = container.read(mediaUploadProvider(_slot)).single;
    await controller.remove(item.localId);

    expect(container.read(mediaUploadProvider(_slot)), isEmpty);
    // Otherwise an abandoned upload would linger in storage.
    expect(repository.deleted, ['remote-a.jpg']);
  });

  test('rejects files beyond maxItems and reports why', () async {
    final repository = _FakeMediaRepository();
    final container = _containerWith(repository);
    final controller = container.read(mediaUploadProvider(_slot).notifier);

    // productImages allows 10.
    final rejections = await controller.addPicked(
      List.generate(12, (index) => _file('file$index.jpg')),
    );
    await pumpEventQueue();

    expect(rejections, hasLength(2));
    expect(rejections.every((r) => r == MediaRejection.tooManyItems), isTrue);
    expect(container.read(mediaUploadProvider(_slot)), hasLength(10));
  });

  test('rejects an invalid file without queuing it', () async {
    final repository = _FakeMediaRepository();
    final container = _containerWith(repository);
    final controller = container.read(mediaUploadProvider(_slot).notifier);

    final rejections = await controller.addPicked([
      PickedMedia(
        fileName: 'virus.exe',
        mimeType: 'application/x-msdownload',
        sizeBytes: 10,
        bytes: Uint8List.fromList(<int>[0]),
      ),
      _file('good.jpg'),
    ]);
    await pumpEventQueue();

    expect(rejections, [MediaRejection.unsupportedExtension]);
    expect(container.read(mediaUploadProvider(_slot)), hasLength(1));
    expect(repository.uploadAttempts, ['good.jpg']);
  });

  test('reorder moves an item to the requested position', () async {
    final repository = _FakeMediaRepository();
    final container = _containerWith(repository);
    final controller = container.read(mediaUploadProvider(_slot).notifier);

    await controller.addPicked([
      _file('a.jpg'),
      _file('b.jpg'),
      _file('c.jpg'),
    ]);
    await pumpEventQueue();

    // Promote the third image to be the main one.
    controller.reorder(2, 0);

    expect(
      container
          .read(mediaUploadProvider(_slot))
          .map((item) => item.displayName),
      ['c.jpg', 'a.jpg', 'b.jpg'],
    );
    expect(controller.uploadedMedia.first.id, 'remote-c.jpg');
  });

  test('setExisting seeds an edit form with server media', () async {
    final container = _containerWith(_FakeMediaRepository());
    final controller = container.read(mediaUploadProvider(_slot).notifier);

    controller.setExisting(const [
      UploadedMedia(
        id: 'm1',
        url: 'https://cdn.example.com/m1.jpg',
        kind: MediaKind.image,
      ),
    ]);

    final items = container.read(mediaUploadProvider(_slot));
    expect(items, hasLength(1));
    expect(items.single.isDone, isTrue);
    expect(items.single.source, isNull);
    expect(controller.uploadedMedia.single.id, 'm1');
  });
}
