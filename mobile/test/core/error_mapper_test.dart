import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/error_mapper.dart';
import 'package:saba_marketplace/core/errors/failure.dart';

DioException _responseError(int status, {Object? body}) {
  final options = RequestOptions(path: '/test');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: body,
    ),
  );
}

void main() {
  group('ErrorMapper transport errors', () {
    test('maps timeouts', () {
      final failure = ErrorMapper.fromDioException(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(failure, isA<TimeoutFailure>());
      expect(failure.code, FailureCode.timeout);
    });

    test('maps connection errors to a network failure', () {
      final failure = ErrorMapper.fromDioException(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(failure, isA<NetworkFailure>());
    });

    test('maps cancellation', () {
      final failure = ErrorMapper.fromDioException(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.cancel,
        ),
      );
      expect(failure, isA<CancelledFailure>());
    });
  });

  group('ErrorMapper HTTP statuses', () {
    test('401 becomes an authentication failure', () {
      expect(
        ErrorMapper.fromDioException(_responseError(401)),
        isA<AuthenticationFailure>(),
      );
    });

    test('403 becomes an authorization failure', () {
      expect(
        ErrorMapper.fromDioException(_responseError(403)),
        isA<AuthorizationFailure>(),
      );
    });

    test('404 becomes a not-found failure', () {
      expect(
        ErrorMapper.fromDioException(_responseError(404)),
        isA<NotFoundFailure>(),
      );
    });

    test('409 becomes a conflict failure', () {
      expect(
        ErrorMapper.fromDioException(_responseError(409)),
        isA<ConflictFailure>(),
      );
    });

    test('500 and above become server failures', () {
      expect(
        ErrorMapper.fromDioException(_responseError(503)),
        isA<ServerFailure>(),
      );
    });
  });

  group('ErrorMapper validation payloads', () {
    test('extracts the documented field error array', () {
      final failure = ErrorMapper.fromDioException(
        _responseError(
          422,
          body: <String, dynamic>{
            'success': false,
            'message': 'Validation failed',
            'errors': [
              {'field': 'email', 'message': 'Invalid email address'},
              {'field': 'password', 'message': 'Too short'},
            ],
          },
        ),
      );

      expect(failure, isA<ValidationFailure>());
      expect(failure.message, 'Validation failed');
      expect(failure.fieldErrors, hasLength(2));
      expect(failure.messageForField('email'), 'Invalid email address');
      expect(failure.messageForField('missing'), isNull);
    });

    test('tolerates a map-of-lists validation shape', () {
      final failure = ErrorMapper.fromDioException(
        _responseError(
          400,
          body: <String, dynamic>{
            'message': 'Bad request',
            'errors': {
              'phone': ['Required', 'Too short'],
            },
          },
        ),
      );

      expect(failure.messageForField('phone'), 'Required, Too short');
    });
  });

  group('ErrorMapper backend codes', () {
    test('an inventory code wins over the bare HTTP status', () {
      final failure = ErrorMapper.fromDioException(
        _responseError(
          409,
          body: <String, dynamic>{
            'code': 'INVENTORY_ERROR',
            'message': 'Only 2 left',
          },
        ),
      );

      // Without the code this 409 would have been a generic conflict.
      expect(failure, isA<InventoryFailure>());
      expect(failure.code, FailureCode.inventory);
      expect(failure.message, 'Only 2 left');
    });

    test('a payment code produces a payment failure', () {
      final failure = ErrorMapper.fromDioException(
        _responseError(
          402,
          body: <String, dynamic>{
            'code': 'PAYMENT_ERROR',
            'message': 'Card declined',
          },
        ),
      );

      expect(failure, isA<PaymentFailure>());
    });
  });

  test('fromObject passes an existing failure straight through', () {
    const original = InventoryFailure(message: 'x');
    expect(ErrorMapper.fromObject(original), same(original));
  });

  test('fromObject maps a format error to a parsing failure', () {
    expect(
      ErrorMapper.fromObject(const FormatException('bad')),
      isA<ParsingFailure>(),
    );
  });
}
