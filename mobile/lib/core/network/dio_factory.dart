import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../constants/app_constants.dart';
import '../mock/mock_api_interceptor.dart';
import '../storage/token_storage.dart';
import 'auth_interceptor.dart';
import 'logging_interceptor.dart';

/// Builds the configured Dio instances used by the app.
class DioFactory {
  const DioFactory._();

  static BaseOptions _baseOptions() => BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: AppConfig.connectTimeout,
    receiveTimeout: AppConfig.receiveTimeout,
    sendTimeout: AppConfig.sendTimeout,
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
    // Let the error mapper classify every non-2xx instead of Dio throwing
    // an opaque exception for some of them.
    validateStatus: (status) => status != null && status < 400,
    headers: <String, dynamic>{ApiHeaders.clientPlatform: _platformName},
  );

  static String get _platformName {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  /// Shared in demo mode so cart, wishlist and order state survive across the
  /// main client and the refresh client.
  static final MockApiInterceptor _mockInterceptor = MockApiInterceptor();

  /// The shared demo backend: `main` keeps it on the phone
  /// (`keepOnDevice`), and a test puts it back to a known state between
  /// cases (`resetForTesting`).
  static MockApiInterceptor get mockBackend => _mockInterceptor;

  /// A client with no auth interceptor. Used to refresh tokens and to replay a
  /// request after a refresh, which would otherwise recurse forever.
  static Dio createRefreshClient() {
    final dio = Dio(_baseOptions());
    if (AppConfig.enableNetworkLogging) {
      dio.interceptors.add(const LoggingInterceptor());
    }
    if (AppConfig.isDemoMode) {
      dio.interceptors.add(_mockInterceptor);
    }
    return dio;
  }

  /// The main application client.
  ///
  /// [currentLanguageCode] is read per request so the backend can localize its
  /// error messages to whatever language the user has selected.
  static Dio create({
    required TokenStorage tokenStorage,
    required Dio refreshClient,
    required Future<void> Function() onSessionExpired,
    required String Function() currentLanguageCode,
  }) {
    final dio = Dio(_baseOptions());

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers[ApiHeaders.acceptLanguage] = currentLanguageCode();
          handler.next(options);
        },
      ),
    );

    dio.interceptors.add(
      AuthInterceptor(
        tokenStorage: tokenStorage,
        refreshClient: refreshClient,
        onSessionExpired: onSessionExpired,
      ),
    );

    if (AppConfig.enableNetworkLogging) {
      dio.interceptors.add(const LoggingInterceptor());
    }

    // Last in the chain, so auth headers and logging still run exactly as they
    // will against a real server. It resolves the request instead of sending
    // it, and nothing above this line knows the difference.
    if (AppConfig.isDemoMode) {
      dio.interceptors.add(_mockInterceptor);
    }

    return dio;
  }
}
