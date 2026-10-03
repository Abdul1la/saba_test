import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/storage/token_storage.dart';
import '../domain/auth_repository.dart';
import '../domain/entities.dart';
import 'auth_remote_data_source.dart';

/// Coordinates the auth API with secure token storage.
///
/// Tokens are written only after the backend confirms the credentials, and
/// cleared on the way out even if the logout call itself fails — a device
/// should never keep credentials the user asked to drop.
class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({required this.remote, required this.tokenStorage});

  final AuthRemoteDataSource remote;
  final TokenStorage tokenStorage;

  @override
  Future<Result<User>> login({
    String? email,
    String? phone,
    required String password,
    String? code,
  }) async {
    final result = await remote.login(
      email: email,
      phone: phone,
      password: password,
      code: code,
    );
    return _persist(result);
  }

  @override
  Future<Result<User>> registerCustomer(
    CustomerRegistration registration,
  ) async {
    return _persist(await remote.registerCustomer(registration));
  }

  @override
  Future<Result<User>> registerMerchant(
    MerchantRegistration registration,
  ) async {
    return _persist(await remote.registerMerchant(registration));
  }

  @override
  Future<Result<User>> fetchCurrentUser() => remote.fetchCurrentUser();

  @override
  Future<Result<void>> logout() async {
    final tokens = await tokenStorage.read();

    // Revoke the refresh token server-side so the session cannot be resumed
    // from a stolen copy (specification section 5).
    final result = tokens == null
        ? const Result<void>.ok(null)
        : await remote.logout(tokens.refreshToken);

    await tokenStorage.clear();
    return result;
  }

  @override
  Future<Result<OtpChallenge>> sendOtp(
    String phone, {
    OtpPurpose purpose = OtpPurpose.other,
  }) => remote.sendOtp(phone, purpose: purpose);

  @override
  Future<Result<void>> resetPassword({
    required String phone,
    required String code,
    required String password,
  }) => remote.resetPassword(phone: phone, code: code, password: password);

  @override
  Future<Result<String>> verifyOtp({
    required String phone,
    required String code,
  }) => remote.verifyOtp(phone: phone, code: code);

  @override
  Future<Result<User>> updateProfile({String? fullName, String? governorate}) {
    return remote.updateProfile(<String, dynamic>{
      'fullName': ?fullName,
      'governorate': ?governorate,
    });
  }

  @override
  Future<Result<void>> deleteAccount() async {
    final result = await remote.deleteAccount();
    if (result.isOk) await tokenStorage.clear();
    return result;
  }

  @override
  Future<bool> hasStoredSession() async => (await tokenStorage.read()) != null;

  @override
  Future<void> clearSession() => tokenStorage.clear();

  /// Stores the tokens from a successful auth response and returns the user.
  Future<Result<User>> _persist(Result<AuthPayload> result) async {
    return switch (result) {
      Ok<AuthPayload>(:final value) => await _saveTokens(value),
      Err<AuthPayload>(:final failure) => Err<User>(failure),
    };
  }

  Future<Result<User>> _saveTokens(AuthPayload payload) async {
    if (!payload.tokens.isValid) {
      // A 2xx without a usable token pair is a contract violation, not a
      // successful sign-in.
      return const Err<User>(ParsingFailure());
    }
    await tokenStorage.save(payload.tokens);
    return Ok<User>(payload.user);
  }
}
