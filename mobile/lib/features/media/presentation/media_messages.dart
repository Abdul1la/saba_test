import '../../../core/localization/app_localizations.dart';
import '../domain/entities.dart';

/// Turns a machine-readable rejection into text a person can read.
///
/// Mirrors how `FailureCode` is localized: the domain stays language-free and
/// the presentation layer owns the wording.
extension MediaRejectionMessages on MediaRejection {
  String localizedMessage(AppLocalizations l10n) => switch (this) {
    MediaRejection.tooLarge => l10n.mediaTooLarge,
    MediaRejection.unsupportedType => l10n.mediaUnsupportedType,
    MediaRejection.unsupportedExtension => l10n.mediaUnsupportedExtension,
    MediaRejection.imageTooSmall => l10n.mediaImageTooSmall,
    MediaRejection.imageTooLarge => l10n.mediaImageTooLarge,
    MediaRejection.tooManyItems => l10n.maxFilesReached,
    MediaRejection.unreadable => l10n.mediaUnreadable,
  };
}

/// Summarises a batch of rejections into one sentence.
///
/// When every rejected file failed for the same reason, that reason is shown.
/// A mixed batch gets a generic line, because listing five different problems
/// in a snack bar helps nobody.
String describeRejections(
  List<MediaRejection> rejections,
  AppLocalizations l10n,
) {
  if (rejections.isEmpty) return '';

  final distinct = rejections.toSet();
  if (distinct.length == 1) {
    return distinct.first.localizedMessage(l10n);
  }
  return l10n.someFilesRejected;
}
