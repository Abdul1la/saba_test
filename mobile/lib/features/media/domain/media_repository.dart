import '../../../core/errors/result.dart';
import 'entities.dart';

/// Reported as an upload runs, so the UI can show a real progress bar rather
/// than an indeterminate spinner.
typedef UploadProgressCallback = void Function(int sent, int total);

/// Cancels an in-flight upload.
///
/// Deliberately not Dio's `CancelToken`: the domain layer must not know the
/// HTTP client. The data layer maps this onto one.
abstract interface class UploadCancelToken {
  void cancel();

  bool get isCancelled;
}

/// Chooses files from the device.
///
/// An interface, so screens depend on "pick me some images" rather than on
/// `image_picker` or `file_picker`. Swapping the plugin, or faking it in a
/// test, touches only the data layer (§69).
abstract interface class MediaPicker {
  /// Opens the gallery. Honours [MediaConstraints.maxItems] where the platform
  /// supports a selection limit.
  Future<List<PickedMedia>> pickImages({
    required MediaConstraints constraints,
    bool multiple = true,
  });

  /// Opens the camera for a single photo.
  Future<PickedMedia?> captureImage({required MediaConstraints constraints});

  /// Opens the document picker, restricted to the allowed extensions.
  Future<List<PickedMedia>> pickFiles({
    required MediaConstraints constraints,
    bool multiple = true,
  });
}

/// Uploads to, and deletes from, the platform's media store.
///
/// The backend owns storage: it validates the file again, generates the key,
/// and returns the URL. The app never talks to object storage directly and
/// never invents a key (§56).
abstract interface class MediaRepository {
  Future<Result<UploadedMedia>> upload(
    PickedMedia media, {
    UploadProgressCallback? onProgress,
    UploadCancelToken? cancelToken,
  });

  Future<Result<void>> delete(String mediaId);

  /// Creates a token this repository understands.
  UploadCancelToken createCancelToken();
}
