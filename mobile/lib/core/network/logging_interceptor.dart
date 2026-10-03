import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../constants/app_constants.dart';

/// Development-only request logging.
///
/// Credentials never reach the log: the `Authorization` header and any
/// password, token or card field in a request body are replaced with
/// `<redacted>` before anything is printed (specification section 65).
class LoggingInterceptor extends Interceptor {
  const LoggingInterceptor();

  static const Set<String> _redactedHeaders = <String>{
    ApiHeaders.authorization,
    'authorization',
    'cookie',
    'set-cookie',
  };

  static const Set<String> _redactedBodyKeys = <String>{
    'password',
    'currentpassword',
    'newpassword',
    'confirmpassword',
    'passwordconfirmation',
    'accesstoken',
    'refreshtoken',
    'access_token',
    'refresh_token',
    'token',
    'secret',
    'cardnumber',
    'card_number',
    'cvv',
    'cvc',
    'pin',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    developer.log(
      '--> ${options.method} ${options.uri}\n'
      'headers: ${_redactHeaders(options.headers)}\n'
      'body: ${_redactBody(options.data)}',
      name: 'api',
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    developer.log(
      '<-- ${response.statusCode} '
      '${response.requestOptions.method} ${response.requestOptions.uri}',
      name: 'api',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    developer.log(
      '<-- ERROR ${err.response?.statusCode ?? err.type.name} '
      '${err.requestOptions.method} ${err.requestOptions.uri}\n'
      'body: ${_redactBody(err.response?.data)}',
      name: 'api',
    );
    handler.next(err);
  }

  Map<String, dynamic> _redactHeaders(Map<String, dynamic> headers) {
    return headers.map(
      (key, value) => MapEntry(
        key,
        _redactedHeaders.contains(key.toLowerCase()) ? '<redacted>' : value,
      ),
    );
  }

  Object? _redactBody(Object? body) {
    if (body is Map) {
      return body.map(
        (key, value) => MapEntry(
          key,
          _redactedBodyKeys.contains(
                key.toString().toLowerCase().replaceAll('_', ''),
              )
              ? '<redacted>'
              : _redactBody(value),
        ),
      );
    }
    if (body is List) {
      return body.map(_redactBody).toList();
    }
    if (body is FormData) {
      return '<form-data: ${body.files.length} file(s)>';
    }
    return body;
  }
}
