import 'package:dio/dio.dart';

import '../config/api_endpoints.dart';
import '../constants/app_constants.dart';
import '../storage/token_storage.dart';

/// Attaches the access token to outgoing requests and transparently refreshes
/// it when the server answers 401.
///
/// Extends [QueuedInterceptor] so the callbacks run one at a time. That gives
/// single-flight refresh for free: if ten requests fail with 401 at once, the
/// first one refreshes and the other nine notice the token already changed and
/// simply retry.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.tokenStorage,
    required this.refreshClient,
    required this.onSessionExpired,
  });

  final TokenStorage tokenStorage;

  /// A bare Dio with no auth interceptor, used for the refresh call and for
  /// replaying the original request. Prevents infinite interceptor recursion.
  final Dio refreshClient;

  /// Invoked when the refresh token itself is rejected: the session is over.
  final Future<void> Function() onSessionExpired;

  /// Endpoints that must never carry (or try to refresh) a token.
  static const Set<String> _anonymousPaths = <String>{
    ApiEndpoints.login,
    ApiEndpoints.registerCustomer,
    ApiEndpoints.registerMerchant,
    ApiEndpoints.refreshToken,
  };

  bool _isAnonymous(RequestOptions options) =>
      _anonymousPaths.any((path) => options.path.endsWith(path));

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isAnonymous(options)) {
      return handler.next(options);
    }

    var tokens = await tokenStorage.read();

    // Proactive refresh: if we already know the access token is expired, renew
    // it before spending a round trip on a guaranteed 401.
    if (tokens != null && tokens.isAccessTokenExpired) {
      tokens = await _refreshTokens(tokens);
    }

    if (tokens != null && tokens.accessToken.isNotEmpty) {
      options.headers[ApiHeaders.authorization] =
          'Bearer ${tokens.accessToken}';
    }
    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final isUnauthorized = response?.statusCode == 401;

    if (!isUnauthorized || _isAnonymous(err.requestOptions)) {
      return handler.next(err);
    }

    // The token this request actually used.
    final usedToken =
        (err.requestOptions.headers[ApiHeaders.authorization] as String?)
            ?.replaceFirst('Bearer ', '');

    final current = await tokenStorage.read();
    if (current == null) {
      await onSessionExpired();
      return handler.next(err);
    }

    // Another queued request already refreshed: just replay with the new token.
    if (usedToken != null && usedToken != current.accessToken) {
      return _replay(err, current.accessToken, handler);
    }

    final refreshed = await _refreshTokens(current);
    if (refreshed == null) {
      await onSessionExpired();
      return handler.next(err);
    }
    return _replay(err, refreshed.accessToken, handler);
  }

  /// Exchanges the refresh token for a new pair. Returns `null` when the
  /// refresh token itself is rejected, which means the session is over.
  Future<AuthTokens?> _refreshTokens(AuthTokens current) async {
    if (current.refreshToken.isEmpty) return null;
    try {
      final response = await refreshClient.post<dynamic>(
        ApiEndpoints.refreshToken,
        data: <String, dynamic>{'refreshToken': current.refreshToken},
      );

      final body = response.data;
      final payload = body is Map && body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : (body is Map ? Map<String, dynamic>.from(body) : null);
      if (payload == null) return null;

      final tokens = AuthTokens.fromJson(payload);
      if (!tokens.isValid) return null;

      // The backend rotates refresh tokens, so persist the whole new pair.
      await tokenStorage.save(tokens);
      return tokens;
    } on DioException {
      await tokenStorage.clear();
      return null;
    }
  }

  Future<void> _replay(
    DioException err,
    String accessToken,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    options.headers[ApiHeaders.authorization] = 'Bearer $accessToken';
    try {
      final response = await refreshClient.fetch<dynamic>(options);
      return handler.resolve(response);
    } on DioException catch (error) {
      return handler.next(error);
    }
  }
}
