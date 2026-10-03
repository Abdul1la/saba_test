import 'package:dio/dio.dart';

import 'failure.dart';

/// Translates transport-level exceptions into the app's typed [Failure] model.
///
/// This is the only place that knows about Dio, which keeps the domain and
/// presentation layers free of HTTP concerns.
class ErrorMapper {
  const ErrorMapper._();

  static Failure fromDioException(DioException exception) {
    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const TimeoutFailure();
      case DioExceptionType.cancel:
        return const CancelledFailure();
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return const NetworkFailure();
      case DioExceptionType.badCertificate:
        return const NetworkFailure();
      case DioExceptionType.badResponse:
        return _fromResponse(exception.response);
    }
  }

  static Failure _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode ?? 0;
    final body = response?.data;

    var message = '';
    var fieldErrors = const <FieldError>[];

    if (body is Map) {
      final map = Map<String, dynamic>.from(body);
      message = map['message']?.toString() ?? '';

      final errors = map['errors'];
      if (errors is List) {
        fieldErrors = errors
            .whereType<Map>()
            .map((e) => FieldError.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      } else if (errors is Map) {
        // Tolerate `{ "email": ["Invalid"] }` shaped validation output.
        fieldErrors = Map<String, dynamic>.from(errors).entries
            .map(
              (entry) => FieldError(
                field: entry.key,
                message: entry.value is List
                    ? (entry.value as List).join(', ')
                    : entry.value.toString(),
              ),
            )
            .toList(growable: false);
      }
    }

    // A backend-supplied error code wins over the bare HTTP status, because it
    // distinguishes cases the status cannot (for example inventory versus a
    // generic business rule, both of which are 409/422).
    final code = body is Map ? body['code']?.toString() : null;
    final byCode = _fromBackendCode(code, message, fieldErrors, status);
    if (byCode != null) return byCode;

    return switch (status) {
      400 => ValidationFailure(
        message: message,
        fieldErrors: fieldErrors,
        statusCode: status,
      ),
      401 => AuthenticationFailure(message: message, statusCode: status),
      403 => AuthorizationFailure(message: message, statusCode: status),
      404 => NotFoundFailure(message: message, statusCode: status),
      409 => ConflictFailure(message: message, statusCode: status),
      422 => ValidationFailure(
        message: message,
        fieldErrors: fieldErrors,
        statusCode: status,
      ),
      429 => BusinessRuleFailure(message: message, statusCode: status),
      >= 500 => ServerFailure(message: message, statusCode: status),
      _ => UnknownFailure(message: message, statusCode: status),
    };
  }

  static Failure? _fromBackendCode(
    String? code,
    String message,
    List<FieldError> fieldErrors,
    int status,
  ) {
    if (code == null || code.isEmpty) return null;
    return switch (code.toUpperCase()) {
      // A right password on an unchecked number: sign-in sends them to ask
      // for a code, not to the generic "you can't do that".
      'PHONE_NOT_VERIFIED' => PhoneNotVerifiedFailure(
        message: message,
        statusCode: status,
      ),
      'VALIDATION_ERROR' => ValidationFailure(
        message: message,
        fieldErrors: fieldErrors,
        statusCode: status,
      ),
      'AUTHENTICATION_ERROR' => AuthenticationFailure(
        message: message,
        statusCode: status,
      ),
      'AUTHORIZATION_ERROR' => AuthorizationFailure(
        message: message,
        statusCode: status,
      ),
      'NOT_FOUND_ERROR' => NotFoundFailure(
        message: message,
        statusCode: status,
      ),
      'CONFLICT_ERROR' => ConflictFailure(message: message, statusCode: status),
      'BUSINESS_RULE_ERROR' => BusinessRuleFailure(
        message: message,
        statusCode: status,
      ),
      'PAYMENT_ERROR' => PaymentFailure(message: message, statusCode: status),
      'INVENTORY_ERROR' => InventoryFailure(
        message: message,
        statusCode: status,
      ),
      'EXTERNAL_SERVICE_ERROR' => ExternalServiceFailure(
        message: message,
        statusCode: status,
      ),
      _ => null,
    };
  }

  /// Fallback for anything thrown outside Dio, such as a malformed payload.
  static Failure fromObject(Object error) {
    if (error is Failure) return error;
    if (error is DioException) return fromDioException(error);
    if (error is TypeError || error is FormatException) {
      return const ParsingFailure();
    }
    return const UnknownFailure();
  }
}
