import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/failure.dart';
import '../../../core/providers/core_providers.dart';
import '../data/media_picker_impl.dart';
import '../data/media_repository_impl.dart';
import '../domain/entities.dart';
import '../domain/media_repository.dart';
import '../domain/media_validator.dart';
import '../../auth/presentation/auth_providers.dart';

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  ref.watch(accountIdProvider);
  return MediaRepositoryImpl(ref.watch(apiClientProvider));
});

final mediaPickerProvider = Provider<MediaPicker>((ref) => MediaPickerImpl());

/// Where one item in an upload slot currently is.
enum MediaUploadStatus {
  /// Queued, not started.
  pending,
  uploading,
  completed,
  failed,
  cancelled,
}

/// One row in an upload slot.
///
/// Also represents media that already existed on the server when an edit form
/// opened — those arrive as [MediaUploadStatus.completed] with no [source].
@immutable
class MediaUploadItem {
  const MediaUploadItem({
    required this.localId,
    required this.status,
    this.source,
    this.uploaded,
    this.progress = 0,
    this.failure,
  });

  final String localId;
  final MediaUploadStatus status;

  /// The picked file. Null for media that was already on the server.
  final PickedMedia? source;

  final UploadedMedia? uploaded;

  /// 0.0 to 1.0. Meaningful only while [status] is uploading.
  final double progress;

  final Failure? failure;

  bool get isDone => status == MediaUploadStatus.completed && uploaded != null;
  bool get isBusy =>
      status == MediaUploadStatus.pending ||
      status == MediaUploadStatus.uploading;
  bool get canRetry =>
      status == MediaUploadStatus.failed ||
      status == MediaUploadStatus.cancelled;

  String get displayName =>
      source?.fileName ?? uploaded?.fileName ?? uploaded?.id ?? '';

  MediaUploadItem copyWith({
    MediaUploadStatus? status,
    UploadedMedia? uploaded,
    double? progress,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return MediaUploadItem(
      localId: localId,
      status: status ?? this.status,
      source: source,
      uploaded: uploaded ?? this.uploaded,
      progress: progress ?? this.progress,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

/// Identifies one upload slot on one screen.
///
/// Equality is by [id] alone: the id names the slot ("product-images"), and a
/// slot's constraints never change while it is on screen. That keeps this
/// usable as a Riverpod family key without needing equality on
/// [MediaConstraints].
@immutable
class MediaSlot {
  const MediaSlot({required this.id, required this.constraints});

  final String id;
  final MediaConstraints constraints;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MediaSlot && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MediaSlot($id)';
}

/// Owns the files in one upload slot.
///
/// Each file uploads independently, so a failure, a cancellation or a rejected
/// file never discards the others — the requirement that made this a shared
/// component rather than per-feature code.
class MediaUploadController extends Notifier<List<MediaUploadItem>> {
  MediaUploadController(this.slot);

  final MediaSlot slot;

  static const Uuid _uuid = Uuid();

  /// Live cancel tokens, keyed by item id.
  final Map<String, UploadCancelToken> _tokens = <String, UploadCancelToken>{};

  MediaRepository get _repository => ref.read(mediaRepositoryProvider);
  MediaPicker get _picker => ref.read(mediaPickerProvider);

  @override
  List<MediaUploadItem> build() {
    ref.watch(accountIdProvider);
    ref.onDispose(() {
      for (final token in _tokens.values) {
        token.cancel();
      }
      _tokens.clear();
    });
    return const <MediaUploadItem>[];
  }

  // ------------------------------------------------------------- queries ---

  /// The media to submit with the form: completed uploads, in display order.
  List<UploadedMedia> get uploadedMedia => state
      .where((item) => item.isDone)
      .map((item) => item.uploaded!)
      .toList(growable: false);

  bool get isUploading => state.any((item) => item.isBusy);

  bool get hasFailures =>
      state.any((item) => item.status == MediaUploadStatus.failed);

  int get remainingSlots => (slot.constraints.maxItems - state.length).clamp(
    0,
    slot.constraints.maxItems,
  );

  // ------------------------------------------------------------- seeding ---

  /// Seeds the slot with media the server already holds, for an edit form.
  void setExisting(List<UploadedMedia> media) {
    state = media
        .map(
          (item) => MediaUploadItem(
            localId: item.id,
            status: MediaUploadStatus.completed,
            uploaded: item,
            progress: 1,
          ),
        )
        .toList(growable: false);
  }

  // -------------------------------------------------------------- picking ---

  Future<List<MediaRejection>> pickImages({bool fromCamera = false}) async {
    final picked = fromCamera
        ? <PickedMedia>[
            ?await _picker.captureImage(constraints: slot.constraints),
          ]
        : await _picker.pickImages(
            constraints: slot.constraints,
            multiple: slot.constraints.maxItems > 1,
          );
    return addPicked(picked);
  }

  Future<List<MediaRejection>> pickFiles() async {
    final picked = await _picker.pickFiles(
      constraints: slot.constraints,
      multiple: slot.constraints.maxItems > 1,
    );
    return addPicked(picked);
  }

  /// Validates a batch, queues what passes, and returns why the rest failed.
  ///
  /// Returning the rejections instead of throwing is what lets a screen accept
  /// four good photos and explain the fifth, rather than dropping all five.
  Future<List<MediaRejection>> addPicked(List<PickedMedia> picked) async {
    if (picked.isEmpty) return const <MediaRejection>[];

    final results = MediaValidator.validateAll(
      picked,
      slot.constraints,
      alreadySelected: state.length,
    );

    final accepted = <MediaUploadItem>[];
    final rejections = <MediaRejection>[];

    for (final result in results) {
      if (result.isValid) {
        accepted.add(
          MediaUploadItem(
            localId: _uuid.v4(),
            status: MediaUploadStatus.pending,
            source: result.media,
          ),
        );
      } else {
        rejections.add(result.rejection!);
      }
    }

    if (accepted.isNotEmpty) {
      state = <MediaUploadItem>[...state, ...accepted];
      // Kick each one off independently.
      for (final item in accepted) {
        unawaited(_upload(item.localId));
      }
    }

    return rejections;
  }

  // ------------------------------------------------------------- mutation ---

  Future<void> retry(String localId) => _upload(localId);

  void cancel(String localId) {
    _tokens.remove(localId)?.cancel();
    _patch(
      localId,
      (item) => item.copyWith(
        status: MediaUploadStatus.cancelled,
        progress: 0,
        clearFailure: true,
      ),
    );
  }

  /// Removes an item. Media already stored on the server is deleted there too,
  /// so an abandoned upload does not linger in storage.
  Future<void> remove(String localId) async {
    final item = _find(localId);
    if (item == null) return;

    _tokens.remove(localId)?.cancel();
    state = state.where((entry) => entry.localId != localId).toList();

    final uploaded = item.uploaded;
    if (uploaded != null) {
      // Best effort: the row is already gone from the UI, and a failed delete
      // is the backend's orphan to collect.
      await _repository.delete(uploaded.id);
    }
  }

  /// Moves an item. Order is meaningful: the first image in a product gallery
  /// is the main one.
  ///
  /// [newIndex] is already adjusted for the removal, matching
  /// `ReorderableListView.onReorderItem`.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) return;

    final items = <MediaUploadItem>[...state];
    final item = items.removeAt(oldIndex);
    items.insert(newIndex.clamp(0, items.length), item);
    state = items;
  }

  void clear() {
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    state = const <MediaUploadItem>[];
  }

  // -------------------------------------------------------------- internal ---

  Future<void> _upload(String localId) async {
    final item = _find(localId);
    final source = item?.source;
    if (item == null || source == null) return;

    final token = _repository.createCancelToken();
    _tokens[localId] = token;

    _patch(
      localId,
      (entry) => entry.copyWith(
        status: MediaUploadStatus.uploading,
        progress: 0,
        clearFailure: true,
      ),
    );

    final result = await _repository.upload(
      source,
      cancelToken: token,
      onProgress: (sent, total) {
        if (total <= 0 || !ref.mounted) return;
        _patch(localId, (entry) => entry.copyWith(progress: sent / total));
      },
    );

    _tokens.remove(localId);
    if (!ref.mounted) return;

    result.fold(
      ok: (uploaded) => _patch(
        localId,
        (entry) => entry.copyWith(
          status: MediaUploadStatus.completed,
          uploaded: uploaded,
          progress: 1,
          clearFailure: true,
        ),
      ),
      err: (failure) => _patch(
        localId,
        (entry) => entry.copyWith(
          // A cancelled request is a user action, not an error to report.
          status: failure.code == FailureCode.cancelled
              ? MediaUploadStatus.cancelled
              : MediaUploadStatus.failed,
          progress: 0,
          failure: failure.code == FailureCode.cancelled ? null : failure,
        ),
      ),
    );
  }

  MediaUploadItem? _find(String localId) {
    for (final item in state) {
      if (item.localId == localId) return item;
    }
    return null;
  }

  void _patch(
    String localId,
    MediaUploadItem Function(MediaUploadItem item) update,
  ) {
    state = state
        .map((item) => item.localId == localId ? update(item) : item)
        .toList(growable: false);
  }
}

final mediaUploadProvider =
    NotifierProvider.family<
      MediaUploadController,
      List<MediaUploadItem>,
      MediaSlot
    >(MediaUploadController.new);
