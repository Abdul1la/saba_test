import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/json_reader.dart';
import '../domain/entities.dart';
import '../domain/media_repository.dart';

/// Adapts Dio's [CancelToken] to the domain's [UploadCancelToken].
///
/// Keeps the HTTP client out of the domain while still giving the UI a real
/// cancel button.
class DioUploadCancelToken implements UploadCancelToken {
  DioUploadCancelToken();

  final CancelToken token = CancelToken();

  @override
  void cancel() {
    if (!token.isCancelled) token.cancel('cancelled');
  }

  @override
  bool get isCancelled => token.isCancelled;
}

class MediaRepositoryImpl implements MediaRepository {
  const MediaRepositoryImpl(this.client);

  final ApiClient client;

  @override
  UploadCancelToken createCancelToken() => DioUploadCancelToken();

  @override
  Future<Result<UploadedMedia>> upload(
    PickedMedia media, {
    UploadProgressCallback? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    if (!media.hasContents) {
      // Defensive: the controller validates first, so reaching here means the
      // file became unreadable between picking and uploading.
      return const Err<UploadedMedia>(
        ValidationFailure(message: '', statusCode: null),
      );
    }

    // Demo mode has no file store, so it kept nothing: the demo server
    // answered with a picsum.photos address, and a laptop with no network -
    // or a shop phone with a bad one - drew a broken tile. The merchant
    // uploaded a photo, saw it in the form, saved, and found a grey box on
    // the shelf and in the edit screen. Here the app keeps the picture
    // itself, as the data it already holds, so it survives saving, closing
    // the app and coming back.
    if (AppConfig.isDemoMode) {
      final kept = await _keptInTheDemo(media);
      if (kept != null) return Ok<UploadedMedia>(kept);
    }

    final FormData formData;
    try {
      formData = FormData.fromMap(<String, dynamic>{
        'file': media.bytes != null
            ? MultipartFile.fromBytes(
                media.bytes!,
                filename: media.fileName,
                contentType: _mediaType(media.mimeType),
              )
            : await MultipartFile.fromFile(
                media.path!,
                filename: media.fileName,
                contentType: _mediaType(media.mimeType),
              ),
        // Advisory only. The backend re-derives the real type from the bytes
        // and must not trust either of these (§56).
        'kind': media.kind.name.toUpperCase(),
        'fileName': media.fileName,
      });
    } on Object {
      return const Err<UploadedMedia>(ValidationFailure(statusCode: null));
    }

    return client.upload<UploadedMedia>(
      ApiEndpoints.mediaUpload,
      formData: formData,
      decoder: _decode,
      onSendProgress: onProgress,
      cancelToken: cancelToken is DioUploadCancelToken
          ? cancelToken.token
          : null,
    );
  }

  @override
  Future<Result<void>> delete(String mediaId) =>
      client.command(ApiEndpoints.media(mediaId), method: 'DELETE');

  /// `image/jpeg` to a Dio media type. Returns null for anything unparsable,
  /// which lets Dio fall back to its own detection.
  static DioMediaType? _mediaType(String mimeType) {
    final parts = mimeType.split('/');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return DioMediaType(parts[0], parts[1]);
  }

  static UploadedMedia _decode(ApiEnvelope envelope) {
    final json = envelope.dataAsMap;

    final declared = MediaKind.fromApi(json['kind'] ?? json['type']);
    final mimeType = Json.str(json, const ['mimeType', 'contentType']);

    return UploadedMedia(
      id: Json.str(json, const ['id', 'mediaId']),
      url: Json.str(json, const ['url', 'fileUrl', 'location']),
      kind: declared == MediaKind.unknown && mimeType.isNotEmpty
          ? MediaKind.fromMimeType(mimeType)
          : declared,
      thumbnailUrl: Json.strOrNull(json, const [
        'thumbnailUrl',
        'thumbnail',
        'previewUrl',
      ]),
      fileName: Json.strOrNull(json, const [
        'fileName',
        'name',
        'originalName',
      ]),
      sizeBytes: Json.integerOrNull(json, const ['sizeBytes', 'size', 'bytes']),
    );
  }

  /// The picked file as a data URI, or null when its bytes cannot be read.
  ///
  /// Only for demo mode. A real backend stores the file and returns a URL;
  /// this keeps the same shape so nothing above it knows the difference.
  Future<UploadedMedia?> _keptInTheDemo(PickedMedia media) async {
    try {
      final bytes =
          media.bytes ??
          (media.path == null ? null : await File(media.path!).readAsBytes());
      if (bytes == null) return null;
      final url = 'data:${media.mimeType};base64,${base64Encode(bytes)}';
      return UploadedMedia(
        id: url,
        url: url,
        fileName: media.fileName,
        kind: media.kind,
        sizeBytes: media.sizeBytes,
      );
    } on Object {
      return null;
    }
  }
}
