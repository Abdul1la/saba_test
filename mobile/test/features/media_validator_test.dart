import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/features/media/domain/entities.dart';
import 'package:saba_marketplace/features/media/domain/media_validator.dart';

PickedMedia _file({
  String name = 'photo.jpg',
  String mimeType = 'image/jpeg',
  int sizeBytes = 1024,
  int? width,
  int? height,
  bool withContents = true,
}) {
  return PickedMedia(
    fileName: name,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    bytes: withContents ? Uint8List.fromList(<int>[1, 2, 3]) : null,
    width: width,
    height: height,
  );
}

const int _mb = 1024 * 1024;

void main() {
  group('MediaValidator single file', () {
    test('accepts a file that satisfies every rule', () {
      final rejection = MediaValidator.validate(
        _file(sizeBytes: 2 * _mb, width: 1200, height: 1200),
        MediaConstraints.productImages,
      );
      expect(rejection, isNull);
    });

    test('rejects a file over the size limit', () {
      final rejection = MediaValidator.validate(
        _file(sizeBytes: 20 * _mb, width: 1200, height: 1200),
        MediaConstraints.productImages,
      );
      expect(rejection, MediaRejection.tooLarge);
    });

    test('rejects a disallowed MIME type', () {
      // The extension is allowed but the declared type is not.
      final rejection = MediaValidator.validate(
        _file(name: 'sneaky.png', mimeType: 'application/x-msdownload'),
        MediaConstraints.productImages,
      );
      expect(rejection, MediaRejection.unsupportedType);
    });

    test('rejects a disallowed extension', () {
      final rejection = MediaValidator.validate(
        _file(name: 'movie.mp4', mimeType: 'video/mp4'),
        MediaConstraints.productImages,
      );
      expect(rejection, MediaRejection.unsupportedExtension);
    });

    test('rejects a file with no extension', () {
      final rejection = MediaValidator.validate(
        _file(name: 'noextension'),
        MediaConstraints.productImages,
      );
      expect(rejection, MediaRejection.unsupportedExtension);
    });

    test('rejects an unreadable file', () {
      final rejection = MediaValidator.validate(
        _file(withContents: false),
        MediaConstraints.productImages,
      );
      expect(rejection, MediaRejection.unreadable);
    });

    test('rejects a zero-byte file', () {
      final rejection = MediaValidator.validate(
        _file(sizeBytes: 0),
        MediaConstraints.productImages,
      );
      expect(rejection, MediaRejection.unreadable);
    });

    test('falls back to the extension when the picker reports no MIME type', () {
      // Several platforms return a null MIME type; a valid file must still pass.
      final rejection = MediaValidator.validate(
        _file(name: 'photo.png', mimeType: '', width: 800, height: 800),
        MediaConstraints.productImages,
      );
      expect(rejection, isNull);
    });
  });

  group('MediaValidator dimensions', () {
    test('rejects an image below the minimum size', () {
      final rejection = MediaValidator.validate(
        _file(width: 100, height: 100),
        MediaConstraints.productImages,
      );
      expect(rejection, MediaRejection.imageTooSmall);
    });

    test('rejects an image above the maximum size', () {
      final rejection = MediaValidator.validate(
        _file(width: 9000, height: 9000),
        MediaConstraints.productImages,
      );
      expect(rejection, MediaRejection.imageTooLarge);
    });

    test('allows an image whose dimensions could not be decoded', () {
      // Unknown dimensions are left for the server to judge rather than
      // blocking a possibly valid upload.
      final rejection = MediaValidator.validate(
        _file(),
        MediaConstraints.productImages,
      );
      expect(rejection, isNull);
    });

    test('ignores dimension rules for non-images', () {
      final rejection = MediaValidator.validate(
        _file(name: 'notes.pdf', mimeType: 'application/pdf'),
        MediaConstraints.attachments,
      );
      expect(rejection, isNull);
    });
  });

  group('MediaValidator batches', () {
    test('reports every file, so good ones are not lost with the bad', () {
      final results = MediaValidator.validateAll([
        _file(name: 'a.jpg', width: 800, height: 800),
        _file(name: 'huge.jpg', sizeBytes: 50 * _mb),
        _file(name: 'b.jpg', width: 800, height: 800),
      ], MediaConstraints.productImages);

      expect(results, hasLength(3));
      expect(results[0].isValid, isTrue);
      expect(results[1].rejection, MediaRejection.tooLarge);
      expect(results[2].isValid, isTrue);
    });

    test('enforces maxItems against files already in the slot', () {
      final results = MediaValidator.validateAll(
        [
          _file(name: 'a.jpg', width: 800, height: 800),
          _file(name: 'b.jpg', width: 800, height: 800),
        ],
        MediaConstraints.evidencePhotos, // maxItems: 5
        alreadySelected: 4,
      );

      expect(results[0].isValid, isTrue);
      expect(results[1].rejection, MediaRejection.tooManyItems);
    });

    test('an invalid file does not consume a slot', () {
      final results = MediaValidator.validateAll(
        [
          _file(name: 'bad.exe', mimeType: 'application/x-msdownload'),
          _file(name: 'good.jpg', width: 800, height: 800),
        ],
        MediaConstraints.avatar, // maxItems: 1
      );

      expect(results[0].rejection, MediaRejection.unsupportedExtension);
      // The rejected file must not have used up the single slot.
      expect(results[1].isValid, isTrue);
    });

    test('an empty batch produces no results', () {
      expect(
        MediaValidator.validateAll(const [], MediaConstraints.productImages),
        isEmpty,
      );
    });
  });

  group('MediaMimeTypes', () {
    test('reads the extension case-insensitively', () {
      expect(MediaMimeTypes.extensionOf('Photo.JPEG'), 'jpeg');
      expect(MediaMimeTypes.extensionOf('archive.tar.gz'), 'gz');
      expect(MediaMimeTypes.extensionOf('noextension'), '');
      expect(MediaMimeTypes.extensionOf('trailing.'), '');
    });

    test('maps known extensions to MIME types', () {
      expect(MediaMimeTypes.forFileName('a.png'), 'image/png');
      expect(MediaMimeTypes.forFileName('a.mp4'), 'video/mp4');
      expect(MediaMimeTypes.forFileName('a.pdf'), 'application/pdf');
      expect(MediaMimeTypes.forFileName('a.unknown'), '');
    });
  });

  group('MediaKind', () {
    test('derives the kind from a MIME type', () {
      expect(MediaKind.fromMimeType('image/png'), MediaKind.image);
      expect(MediaKind.fromMimeType('video/mp4'), MediaKind.video);
      expect(MediaKind.fromMimeType('application/pdf'), MediaKind.document);
      expect(MediaKind.fromMimeType(''), MediaKind.unknown);
    });
  });
}
