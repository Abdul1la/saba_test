import 'dart:io' show File;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/entities.dart';
import '../domain/media_repository.dart';

/// The only file in the app that knows `image_picker` and `file_picker` exist.
///
/// Everything above it depends on [MediaPicker], so replacing either plugin —
/// or faking the picker in a test — changes nothing outside this class (§69).
class MediaPickerImpl implements MediaPicker {
  MediaPickerImpl({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  /// Shrunk as it is picked, rather than uploaded whole.
  ///
  /// A phone camera hands over 4 to 12 MB; a shop photo needs neither the
  /// pixels nor the wait, and a slow upload on an Iraqi mobile connection is
  /// how a merchant gives up halfway through adding a product. 1600px on the
  /// long side at quality 82 lands well under 2 MB and still looks right on
  /// the biggest phone.
  static const double _maxSide = 1600;
  static const int _quality = 82;

  @override
  Future<List<PickedMedia>> pickImages({
    required MediaConstraints constraints,
    bool multiple = true,
  }) async {
    if (!multiple) {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _maxSide,
        maxHeight: _maxSide,
        imageQuality: _quality,
      );
      if (file == null) return const <PickedMedia>[];
      return [await _fromXFile(file, constraints)];
    }

    final files = await _imagePicker.pickMultiImage(
      limit: constraints.maxItems > 1 ? constraints.maxItems : null,
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: _quality,
    );

    final media = <PickedMedia>[];
    for (final file in files) {
      media.add(await _fromXFile(file, constraints));
    }
    return media;
  }

  @override
  Future<PickedMedia?> captureImage({
    required MediaConstraints constraints,
  }) async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: _quality,
    );
    if (file == null) return null;
    return _fromXFile(file, constraints);
  }

  @override
  Future<List<PickedMedia>> pickFiles({
    required MediaConstraints constraints,
    bool multiple = true,
  }) async {
    final extensions = constraints.allowedExtensions.toList();

    final files = multiple
        ? await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: extensions,
          )
        : <PlatformFile>[
            ?await FilePicker.pickFile(
              type: FileType.custom,
              allowedExtensions: extensions,
            ),
          ];

    final media = <PickedMedia>[];
    for (final file in files) {
      media.add(await _fromPlatformFile(file, constraints));
    }
    return media;
  }

  Future<PickedMedia> _fromPlatformFile(
    PlatformFile file,
    MediaConstraints constraints,
  ) async {
    // On the web there is no path, so the bytes are the only way to read it.
    final path = file.path;
    final bytes = path == null ? await file.readAsBytes() : null;
    final length = await file.length() ?? bytes?.length ?? 0;

    return _resolveDimensions(
      PickedMedia(
        fileName: file.name,
        sizeBytes: length,
        mimeType: MediaMimeTypes.forFileName(file.name),
        path: path,
        bytes: bytes,
      ),
      constraints,
    );
  }

  Future<PickedMedia> _fromXFile(
    XFile file,
    MediaConstraints constraints,
  ) async {
    final length = await file.length();

    // `mimeType` is null on several platforms, so fall back to the extension.
    final reported = file.mimeType;
    final mimeType = reported != null && reported.isNotEmpty
        ? reported
        : MediaMimeTypes.forFileName(file.name);

    final picked = PickedMedia(
      fileName: file.name,
      sizeBytes: length,
      mimeType: mimeType,
      path: kIsWeb ? null : file.path,
      bytes: kIsWeb ? await file.readAsBytes() : null,
    );

    return _resolveDimensions(picked, constraints);
  }

  /// Reads an image's pixel size without fully decoding it.
  ///
  /// Only done when the slot actually has dimension rules, and only for
  /// images — decoding every file would be wasteful. A file we cannot read is
  /// returned unchanged and left for the server to judge.
  Future<PickedMedia> _resolveDimensions(
    PickedMedia media,
    MediaConstraints constraints,
  ) async {
    if (!constraints.checksDimensions) return media;
    if (media.kind != MediaKind.image) return media;

    try {
      final bytes =
          media.bytes ??
          (media.path == null ? null : await File(media.path!).readAsBytes());
      if (bytes == null) return media;

      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      descriptor.dispose();
      buffer.dispose();

      return media.copyWith(width: width, height: height);
    } on Object {
      // An undecodable image is not rejected here; the backend decides.
      return media;
    }
  }
}
