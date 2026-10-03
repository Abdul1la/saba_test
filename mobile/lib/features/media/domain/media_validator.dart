import 'package:flutter/foundation.dart';

import 'entities.dart';

/// The outcome of checking one chosen file.
@immutable
class MediaValidationResult {
  const MediaValidationResult({required this.media, this.rejection});

  final PickedMedia media;
  final MediaRejection? rejection;

  bool get isValid => rejection == null;
}

/// Client-side checks on a chosen file (§56).
///
/// This is a courtesy that saves a doomed round trip and gives immediate
/// feedback. It is **not** enforcement: the backend re-validates MIME type,
/// extension, size and dimensions, and only the backend's answer decides
/// whether a file is stored.
///
/// Pure Dart — dimensions are passed in, because decoding an image needs
/// Flutter and this layer must not.
class MediaValidator {
  const MediaValidator._();

  /// Returns the reason a file is unacceptable, or null when it passes.
  static MediaRejection? validate(
    PickedMedia media,
    MediaConstraints constraints,
  ) {
    if (!media.hasContents || media.sizeBytes <= 0) {
      return MediaRejection.unreadable;
    }

    final extension = media.extension;
    if (extension.isEmpty ||
        !constraints.allowedExtensions.contains(extension)) {
      return MediaRejection.unsupportedExtension;
    }

    // Pickers report a MIME type on some platforms and not others, so fall
    // back to what the extension implies rather than rejecting a valid file.
    final mimeType = media.mimeType.isNotEmpty
        ? media.mimeType.toLowerCase()
        : MediaMimeTypes.forFileName(media.fileName);

    if (mimeType.isEmpty || !constraints.allowedMimeTypes.contains(mimeType)) {
      return MediaRejection.unsupportedType;
    }

    if (media.sizeBytes > constraints.maxBytes) {
      return MediaRejection.tooLarge;
    }

    return _validateDimensions(media, constraints);
  }

  /// Dimension rules apply only to images whose size is actually known. An
  /// image we could not decode is allowed through for the server to judge.
  static MediaRejection? _validateDimensions(
    PickedMedia media,
    MediaConstraints constraints,
  ) {
    if (!constraints.checksDimensions) return null;
    if (media.kind != MediaKind.image) return null;

    final width = media.width;
    final height = media.height;
    if (width == null || height == null) return null;

    final minWidth = constraints.minWidth;
    final minHeight = constraints.minHeight;
    if ((minWidth != null && width < minWidth) ||
        (minHeight != null && height < minHeight)) {
      return MediaRejection.imageTooSmall;
    }

    final maxWidth = constraints.maxWidth;
    final maxHeight = constraints.maxHeight;
    if ((maxWidth != null && width > maxWidth) ||
        (maxHeight != null && height > maxHeight)) {
      return MediaRejection.imageTooLarge;
    }

    return null;
  }

  /// Validates a batch, enforcing [MediaConstraints.maxItems] against files
  /// already accepted in this slot.
  ///
  /// Every file is reported, valid or not, so the caller can accept the good
  /// ones and explain the rest — one bad file must never discard the batch.
  static List<MediaValidationResult> validateAll(
    List<PickedMedia> media,
    MediaConstraints constraints, {
    int alreadySelected = 0,
  }) {
    final results = <MediaValidationResult>[];
    var accepted = alreadySelected;

    for (final item in media) {
      final rejection = validate(item, constraints);

      if (rejection != null) {
        results.add(MediaValidationResult(media: item, rejection: rejection));
        continue;
      }

      if (accepted >= constraints.maxItems) {
        results.add(
          MediaValidationResult(
            media: item,
            rejection: MediaRejection.tooManyItems,
          ),
        );
        continue;
      }

      accepted++;
      results.add(MediaValidationResult(media: item));
    }

    return results;
  }
}
