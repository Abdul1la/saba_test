import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../constants/app_constants.dart';
import '../errors/error_mapper.dart';
import '../errors/failure.dart';
import '../errors/result.dart';
import 'api_response.dart';
import 'live_updates.dart';

/// Turns a decoded response envelope into a domain object.
typedef ResponseDecoder<T> = T Function(ApiEnvelope envelope);

/// Thin, typed wrapper over Dio.
///
/// Every method returns a [Result] instead of throwing, so data sources and
/// repositories handle transport failures explicitly. This is the only layer
/// that touches Dio types.
class ApiClient {
  const ApiClient(this.dio, {this.live});

  final Dio dio;

  /// Told what each write changed, so the screens showing it reload.
  final LiveUpdates? live;

  Future<Result<T>> get<T>(
    String path, {
    required ResponseDecoder<T> decoder,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) => _send<T>(
    method: 'GET',
    path: path,
    decoder: decoder,
    queryParameters: queryParameters,
    cancelToken: cancelToken,
  );

  Future<Result<T>> post<T>(
    String path, {
    required ResponseDecoder<T> decoder,
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    String? idempotencyKey,
  }) => _send<T>(
    method: 'POST',
    path: path,
    decoder: decoder,
    data: data,
    queryParameters: queryParameters,
    cancelToken: cancelToken,
    idempotencyKey: idempotencyKey,
  );

  Future<Result<T>> put<T>(
    String path, {
    required ResponseDecoder<T> decoder,
    Object? data,
    CancelToken? cancelToken,
  }) => _send<T>(
    method: 'PUT',
    path: path,
    decoder: decoder,
    data: data,
    cancelToken: cancelToken,
  );

  Future<Result<T>> patch<T>(
    String path, {
    required ResponseDecoder<T> decoder,
    Object? data,
    CancelToken? cancelToken,
  }) => _send<T>(
    method: 'PATCH',
    path: path,
    decoder: decoder,
    data: data,
    cancelToken: cancelToken,
  );

  Future<Result<T>> delete<T>(
    String path, {
    required ResponseDecoder<T> decoder,
    Object? data,
    CancelToken? cancelToken,
  }) => _send<T>(
    method: 'DELETE',
    path: path,
    decoder: decoder,
    data: data,
    cancelToken: cancelToken,
  );

  /// Convenience for endpoints whose body carries nothing the app needs.
  Future<Result<void>> command(
    String path, {
    String method = 'POST',
    Object? data,
    CancelToken? cancelToken,
    String? idempotencyKey,
  }) => _send<void>(
    method: method,
    path: path,
    data: data,
    cancelToken: cancelToken,
    idempotencyKey: idempotencyKey,
    decoder: (_) {},
  );

  /// Sends a multipart upload, reporting progress as bytes leave the device.
  ///
  /// Separate from [post] because only uploads need `onSendProgress`, and
  /// because a large body should not be retried blindly.
  Future<Result<T>> upload<T>(
    String path, {
    required FormData formData,
    required ResponseDecoder<T> decoder,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onSendProgress,
    String? idempotencyKey,
  }) async {
    try {
      final response = await dio.post<dynamic>(
        path,
        data: formData,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        options: Options(
          headers: <String, dynamic>{
            ApiHeaders.idempotencyKey: ?idempotencyKey,
          },
          // A large file over a slow link must not trip the normal timeout.
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      final envelope = ApiEnvelope.fromResponse(response.data);
      if (!envelope.success) {
        return Err<T>(
          BusinessRuleFailure(
            message: envelope.message,
            statusCode: response.statusCode,
          ),
        );
      }
      return Ok<T>(decoder(envelope));
    } on DioException catch (error) {
      return Err<T>(ErrorMapper.fromDioException(error));
    } catch (error) {
      return Err<T>(ErrorMapper.fromObject(error));
    }
  }

  /// Fetches one page of a paginated collection.
  Future<Result<PaginatedList<T>>> getPage<T>(
    String path, {
    required T Function(Map<String, dynamic> json) itemDecoder,
    int page = 1,
    int? perPage,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) => _send<PaginatedList<T>>(
    method: 'GET',
    path: path,
    cancelToken: cancelToken,
    queryParameters: <String, dynamic>{
      'page': page,
      'perPage': perPage ?? AppConfig.defaultPageSize,
      ...?queryParameters,
    },
    decoder: (envelope) => PaginatedList<T>(
      items: envelope.dataAsList.map(itemDecoder).toList(growable: false),
      meta: envelope.pagination,
    ),
  );

  Future<Result<T>> _send<T>({
    required String method,
    required String path,
    required ResponseDecoder<T> decoder,
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    String? idempotencyKey,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          headers: <String, dynamic>{
            ApiHeaders.idempotencyKey: ?idempotencyKey,
          },
        ),
      );

      final envelope = ApiEnvelope.fromResponse(response.data);

      // A 2xx with `success: false` is still a business failure.
      if (!envelope.success) {
        return Err<T>(
          BusinessRuleFailure(
            message: envelope.message,
            statusCode: response.statusCode,
          ),
        );
      }

      // A read changes nothing; anything else may change what a screen is
      // showing, here or on the other side of the app.
      if (method != 'GET') live?.announceWrite(path);

      return Ok<T>(decoder(envelope));
    } on DioException catch (error) {
      return Err<T>(ErrorMapper.fromDioException(error));
    } catch (error) {
      // A shape mismatch between client and server lands here.
      return Err<T>(ErrorMapper.fromObject(error));
    }
  }
}
