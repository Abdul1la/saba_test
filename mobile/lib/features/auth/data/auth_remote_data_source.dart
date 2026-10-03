import '../../../core/config/api_endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/token_storage.dart';
import '../domain/entities.dart';
import 'auth_mappers.dart';

/// The result of a successful sign-in or registration: the user plus the token
/// pair the repository is responsible for storing.
class AuthPayload {
  const AuthPayload({required this.user, required this.tokens});

  final User user;
  final AuthTokens tokens;
}

/// Talks to `/auth/*`. Knows about endpoints and JSON, nothing else.
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._client);

  final ApiClient _client;

  Future<Result<AuthPayload>> login({
    String? email,
    String? phone,
    required String password,
    String? code,
  }) {
    return _client.post<AuthPayload>(
      ApiEndpoints.login,
      data: <String, dynamic>{
        'email': ?email,
        'phone': ?phone,
        'password': password,
        // Only the verify-at-sign-in second call carries it.
        'code': ?code,
      },
      decoder: (envelope) => _payload(envelope.dataAsMap),
    );
  }

  Future<Result<AuthPayload>> registerCustomer(
    CustomerRegistration registration,
  ) {
    return _client.post<AuthPayload>(
      ApiEndpoints.registerCustomer,
      data: registration.toJson(),
      decoder: (envelope) => _payload(envelope.dataAsMap),
    );
  }

  Future<Result<AuthPayload>> registerMerchant(
    MerchantRegistration registration,
  ) {
    return _client.post<AuthPayload>(
      ApiEndpoints.registerMerchant,
      data: registration.toJson(),
      decoder: (envelope) => _payload(envelope.dataAsMap),
    );
  }

  /// Asks for an SMS code. Nothing is created yet - the account does not
  /// exist until the registration call that carries the token this produces.
  ///
  /// [purpose] tells the server which rule applies: a sign-up is refused for
  /// a number that has an account, a reset for one that has none.
  Future<Result<OtpChallenge>> sendOtp(
    String phone, {
    OtpPurpose purpose = OtpPurpose.other,
  }) {
    return _client.post<OtpChallenge>(
      ApiEndpoints.sendOtp,
      data: <String, dynamic>{'phone': phone, 'purpose': ?purpose.apiValue},
      decoder: (envelope) =>
          OtpChallenge.fromJson(envelope.dataAsMap, demo: AppConfig.isDemoMode),
    );
  }

  /// A new password for the account on [phone], with the code sent to it.
  Future<Result<void>> resetPassword({
    required String phone,
    required String code,
    required String password,
  }) => _client.command(
    ApiEndpoints.resetPassword,
    data: <String, dynamic>{
      'phone': phone,
      'token': code,
      'password': password,
    },
  );

  /// Exchanges a correct code for the short-lived token registration needs.
  Future<Result<String>> verifyOtp({
    required String phone,
    required String code,
  }) {
    return _client.post<String>(
      ApiEndpoints.verifyOtp,
      data: <String, dynamic>{'phone': phone, 'code': code},
      decoder: (envelope) =>
          (envelope.dataAsMap['verificationToken'] ?? '').toString(),
    );
  }

  Future<Result<User>> fetchCurrentUser() {
    return _client.get<User>(
      ApiEndpoints.me,
      decoder: (envelope) => UserMapper.fromJson(envelope.dataAsMap),
    );
  }

  Future<Result<void>> logout(String refreshToken) {
    return _client.command(
      ApiEndpoints.logout,
      data: <String, dynamic>{'refreshToken': refreshToken},
    );
  }

  Future<Result<User>> updateProfile(Map<String, dynamic> changes) {
    return _client.patch<User>(
      ApiEndpoints.me,
      data: changes,
      decoder: (envelope) => UserMapper.fromJson(envelope.dataAsMap),
    );
  }

  Future<Result<void>> deleteAccount() =>
      _client.command(ApiEndpoints.me, method: 'DELETE');

  static AuthPayload _payload(Map<String, dynamic> data) => AuthPayload(
    user: UserMapper.fromJson(data),
    tokens: AuthTokens.fromJson(data),
  );
}
