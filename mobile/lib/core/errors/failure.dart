import 'package:flutter/foundation.dart';

/// A single field-level validation message returned by the API.
///
/// Matches the error envelope in specification section 54:
/// `{ "field": "email", "message": "Invalid email address" }`
@immutable
class FieldError {
  const FieldError({required this.field, required this.message});

  factory FieldError.fromJson(Map<String, dynamic> json) => FieldError(
    field: json['field']?.toString() ?? '',
    message: json['message']?.toString() ?? '',
  );

  final String field;
  final String message;

  @override
  String toString() => '$field: $message';
}

/// Stable machine-readable identity for a failure.
///
/// The UI translates these into localized text; the human-readable `message`
/// from the server is preferred when present, because the backend already
/// localizes it using the `Accept-Language` header we send.
enum FailureCode {
  validation,
  authentication,
  authorization,
  phoneNotVerified,
  notFound,
  conflict,
  businessRule,
  payment,
  inventory,
  externalService,
  network,
  timeout,
  cancelled,
  parsing,
  server,
  unknown,
}

/// Every error surfaced to the UI is one of these. Mirrors the backend error
/// categories from specification section 66 so that a failure keeps its meaning
/// all the way from MySQL to the widget tree.
@immutable
sealed class Failure implements Exception {
  const Failure({
    required this.message,
    this.fieldErrors = const <FieldError>[],
    this.statusCode,
  });

  /// Server-provided, already-localized message. May be empty, in which case
  /// the UI falls back to its own localized string for [code].
  final String message;
  final List<FieldError> fieldErrors;
  final int? statusCode;

  FailureCode get code;

  /// Convenience lookup for binding an API error to a specific form field.
  String? messageForField(String field) {
    for (final error in fieldErrors) {
      if (error.field == field) return error.message;
    }
    return null;
  }

  @override
  String toString() =>
      '$runtimeType(code: $code, status: $statusCode, '
      'message: $message, fields: $fieldErrors)';
}

class ValidationFailure extends Failure {
  const ValidationFailure({
    super.message = '',
    super.fieldErrors,
    super.statusCode = 422,
  });

  @override
  FailureCode get code => FailureCode.validation;
}

/// Not signed in, bad credentials, or the session was revoked.
class AuthenticationFailure extends Failure {
  const AuthenticationFailure({super.message = '', super.statusCode = 401});

  @override
  FailureCode get code => FailureCode.authentication;
}

/// Signed in, but the role or ownership check failed on the server.
class AuthorizationFailure extends Failure {
  const AuthorizationFailure({super.message = '', super.statusCode = 403});

  @override
  FailureCode get code => FailureCode.authorization;
}

/// The password was right, but the number has never been checked and Saba now
/// requires it: ask for a code and sign in with it. Its own 403 so sign-in can
/// tell it apart from a role or ownership refusal.
class PhoneNotVerifiedFailure extends Failure {
  const PhoneNotVerifiedFailure({super.message = '', super.statusCode = 403});

  @override
  FailureCode get code => FailureCode.phoneNotVerified;
}

class NotFoundFailure extends Failure {
  const NotFoundFailure({super.message = '', super.statusCode = 404});

  @override
  FailureCode get code => FailureCode.notFound;
}

class ConflictFailure extends Failure {
  const ConflictFailure({super.message = '', super.statusCode = 409});

  @override
  FailureCode get code => FailureCode.conflict;
}

class BusinessRuleFailure extends Failure {
  const BusinessRuleFailure({super.message = '', super.statusCode});

  @override
  FailureCode get code => FailureCode.businessRule;
}

class PaymentFailure extends Failure {
  const PaymentFailure({super.message = '', super.statusCode});

  @override
  FailureCode get code => FailureCode.payment;
}

/// Out of stock, or the requested quantity exceeds what the server can reserve.
class InventoryFailure extends Failure {
  const InventoryFailure({super.message = '', super.statusCode});

  @override
  FailureCode get code => FailureCode.inventory;
}

class ExternalServiceFailure extends Failure {
  const ExternalServiceFailure({super.message = '', super.statusCode});

  @override
  FailureCode get code => FailureCode.externalService;
}

class NetworkFailure extends Failure {
  const NetworkFailure({super.message = ''});

  @override
  FailureCode get code => FailureCode.network;
}

class TimeoutFailure extends Failure {
  const TimeoutFailure({super.message = ''});

  @override
  FailureCode get code => FailureCode.timeout;
}

class CancelledFailure extends Failure {
  const CancelledFailure({super.message = ''});

  @override
  FailureCode get code => FailureCode.cancelled;
}

/// The response did not match the contract the app expects.
class ParsingFailure extends Failure {
  const ParsingFailure({super.message = ''});

  @override
  FailureCode get code => FailureCode.parsing;
}

class ServerFailure extends Failure {
  const ServerFailure({super.message = '', super.statusCode = 500});

  @override
  FailureCode get code => FailureCode.server;
}

class UnknownFailure extends Failure {
  const UnknownFailure({super.message = '', super.statusCode});

  @override
  FailureCode get code => FailureCode.unknown;
}
