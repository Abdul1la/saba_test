import '../errors/failure.dart';
import 'app_localizations.dart';

/// Turns a typed [Failure] into text a person can read.
///
/// The backend already localizes its own messages using the `Accept-Language`
/// header the client sends, so a server message is preferred when present.
/// Transport failures have no server message, and fall back to our own
/// localized copy.
extension FailureLocalization on Failure {
  String localizedMessage(AppLocalizations l10n) {
    if (message.trim().isNotEmpty) return message;
    return switch (code) {
      FailureCode.validation => l10n.errorValidation,
      FailureCode.authentication => l10n.errorUnauthorized,
      FailureCode.authorization => l10n.errorForbidden,
      FailureCode.phoneNotVerified => l10n.verifyNumberToSignIn,
      FailureCode.notFound => l10n.errorNotFound,
      FailureCode.conflict => l10n.errorConflict,
      FailureCode.businessRule => l10n.errorGeneric,
      FailureCode.payment => l10n.errorPayment,
      FailureCode.inventory => l10n.errorInventory,
      FailureCode.externalService => l10n.errorExternalService,
      FailureCode.network => l10n.errorNetwork,
      FailureCode.timeout => l10n.errorTimeout,
      FailureCode.cancelled => l10n.errorCancelled,
      FailureCode.parsing => l10n.errorParsing,
      FailureCode.server => l10n.errorServer,
      FailureCode.unknown => l10n.errorGeneric,
    };
  }

  /// Whether offering a retry button makes sense for this failure.
  bool get isRetryable => switch (code) {
    FailureCode.network ||
    FailureCode.timeout ||
    FailureCode.server ||
    FailureCode.externalService ||
    FailureCode.unknown => true,
    _ => false,
  };
}
