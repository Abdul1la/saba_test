import 'package:flutter/foundation.dart';

/// What a file is, as far as the app cares.
enum MediaKind {
  image,
  video,
  document,
  unknown;

  static MediaKind fromMimeType(String mimeType) {
    final type = mimeType.toLowerCase();
    if (type.startsWith('image/')) return MediaKind.image;
    if (type.startsWith('video/')) return MediaKind.video;
    if (type.isEmpty) return MediaKind.unknown;
    return MediaKind.document;
  }

  static MediaKind fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'IMAGE' => MediaKind.image,
        'VIDEO' => MediaKind.video,
        'DOCUMENT' || 'FILE' => MediaKind.document,
        _ => MediaKind.unknown,
      };
}

/// Extension to MIME type, resolved without a plugin.
///
/// The picker reports a MIME type on some platforms and not others, and a
/// client-supplied MIME type is not trustworthy anyway — the backend
/// re-derives it (§56). This exists only so client-side validation can reject
/// an obviously wrong file before spending an upload on it.
class MediaMimeTypes {
  const MediaMimeTypes._();

  static const Map<String, String> byExtension = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'bmp': 'image/bmp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'm4v': 'video/x-m4v',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt': 'text/plain',
    'csv': 'text/csv',
  };

  /// Lower-case extension without the dot, or an empty string.
  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  static String forFileName(String fileName) =>
      byExtension[extensionOf(fileName)] ?? '';
}

/// A file the user chose, before it is uploaded.
///
/// Carries either a [path] (mobile and desktop) or [bytes] (web), never
/// necessarily both. Nothing here depends on a picker plugin.
@immutable
class PickedMedia {
  const PickedMedia({
    required this.fileName,
    required this.sizeBytes,
    required this.mimeType,
    this.path,
    this.bytes,
    this.width,
    this.height,
  });

  final String fileName;
  final int sizeBytes;
  final String mimeType;

  /// Filesystem path. Null on web.
  final String? path;

  /// In-memory contents. Populated on web, and for small files elsewhere.
  final Uint8List? bytes;

  /// Pixel dimensions, when the file is an image and they could be decoded.
  final int? width;
  final int? height;

  MediaKind get kind => MediaKind.fromMimeType(mimeType);

  String get extension => MediaMimeTypes.extensionOf(fileName);

  bool get hasContents => path != null || bytes != null;

  PickedMedia copyWith({int? width, int? height, String? mimeType}) {
    return PickedMedia(
      fileName: fileName,
      sizeBytes: sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      path: path,
      bytes: bytes,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// A file the backend has accepted and now serves.
///
/// The app never constructs a storage key or a URL — the backend issues both
/// (§56).
@immutable
class UploadedMedia {
  const UploadedMedia({
    required this.id,
    required this.url,
    required this.kind,
    this.thumbnailUrl,
    this.fileName,
    this.sizeBytes,
  });

  final String id;
  final String url;
  final MediaKind kind;
  final String? thumbnailUrl;
  final String? fileName;
  final int? sizeBytes;

  /// Best URL to show in a preview: the thumbnail when one exists.
  String get previewUrl => thumbnailUrl ?? url;
}

/// Why a chosen file was refused before upload.
///
/// A machine-readable reason, translated by the presentation layer — the same
/// split used by `FailureCode`.
enum MediaRejection {
  tooLarge,
  unsupportedType,
  unsupportedExtension,
  imageTooSmall,
  imageTooLarge,
  tooManyItems,
  unreadable,
}

/// The rules a given upload slot accepts.
@immutable
class MediaConstraints {
  const MediaConstraints({
    required this.allowedMimeTypes,
    required this.allowedExtensions,
    required this.maxBytes,
    this.maxItems = 1,
    this.minWidth,
    this.minHeight,
    this.maxWidth,
    this.maxHeight,
  });

  final Set<String> allowedMimeTypes;
  final Set<String> allowedExtensions;
  final int maxBytes;
  final int maxItems;
  final int? minWidth;
  final int? minHeight;
  final int? maxWidth;
  final int? maxHeight;

  static const int _mb = 1024 * 1024;

  /// Product gallery images (§24). Generous ceiling, but a real minimum so a
  /// merchant cannot list a product with a thumbnail-sized photo.
  static const MediaConstraints productImages = MediaConstraints(
    allowedMimeTypes: {'image/jpeg', 'image/png', 'image/webp', 'image/heic'},
    allowedExtensions: {'jpg', 'jpeg', 'png', 'webp', 'heic'},
    maxBytes: 8 * _mb,
    maxItems: 10,
    minWidth: 400,
    minHeight: 400,
    maxWidth: 6000,
    maxHeight: 6000,
  );

  /// Photos attached to a review (§20) or a return request (§19).
  static const MediaConstraints evidencePhotos = MediaConstraints(
    allowedMimeTypes: {'image/jpeg', 'image/png', 'image/webp', 'image/heic'},
    allowedExtensions: {'jpg', 'jpeg', 'png', 'webp', 'heic'},
    maxBytes: 8 * _mb,
    maxItems: 5,
    minWidth: 200,
    minHeight: 200,
  );

  /// A photo sent in a chat (§43), one at a time. 5 MB is the server's own
  /// ceiling; no minimum, so a quick snap of a receipt or a fault is fine.
  static const MediaConstraints chatPhoto = MediaConstraints(
    allowedMimeTypes: {'image/jpeg', 'image/png', 'image/webp', 'image/heic'},
    allowedExtensions: {'jpg', 'jpeg', 'png', 'webp', 'heic'},
    maxBytes: 5 * _mb,
  );

  /// Support ticket and conversation attachments (§43, §44).
  static const MediaConstraints attachments = MediaConstraints(
    allowedMimeTypes: {
      'image/jpeg',
      'image/png',
      'image/webp',
      'application/pdf',
      'text/plain',
    },
    allowedExtensions: {'jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt'},
    maxBytes: 16 * _mb,
    maxItems: 5,
  );

  static const MediaConstraints avatar = MediaConstraints(
    allowedMimeTypes: {'image/jpeg', 'image/png', 'image/webp'},
    allowedExtensions: {'jpg', 'jpeg', 'png', 'webp'},
    maxBytes: 4 * _mb,
    minWidth: 100,
    minHeight: 100,
  );

  bool get acceptsImages =>
      allowedMimeTypes.any((type) => type.startsWith('image/'));
  bool get acceptsVideos =>
      allowedMimeTypes.any((type) => type.startsWith('video/'));
  bool get acceptsDocuments => allowedMimeTypes.any(
    (type) => !type.startsWith('image/') && !type.startsWith('video/'),
  );

  bool get checksDimensions =>
      minWidth != null ||
      minHeight != null ||
      maxWidth != null ||
      maxHeight != null;
}
