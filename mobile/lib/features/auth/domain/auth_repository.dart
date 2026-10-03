import '../../../core/errors/result.dart';
import 'entities.dart';

/// Contract the presentation layer depends on.
///
/// The UI never sees Dio, JSON or the keystore — only these methods and the
/// domain types they return.
abstract interface class AuthRepository {
  /// Signs in, by phone or by email, and persists the returned token pair.
  ///
  /// [code] is the SMS code for the verify-at-sign-in step: when Saba has
  /// checks on and the account's number was never proven, the first sign-in
  /// is refused with [PhoneNotVerifiedFailure], and the second carries the
  /// code from a fresh [OtpPurpose.verifyPhone] send.
  Future<Result<User>> login({
    String? email,
    String? phone,
    required String password,
    String? code,
  });

  /// Creates a customer account. Can never produce an admin: the role is
  /// assigned by the backend, not requested by the client (section 5).
  Future<Result<User>> registerCustomer(CustomerRegistration registration);

  /// Creates a merchant account whose store starts in `PENDING`.
  Future<Result<User>> registerMerchant(MerchantRegistration registration);

  /// Loads the signed-in user from `/customers/me`.
  Future<Result<User>> fetchCurrentUser();

  /// Revokes the session server-side and clears local tokens.
  Future<Result<void>> logout();

  /// For [OtpPurpose.signUp], a number that already has an account is
  /// refused with a [ConflictFailure]; for [OtpPurpose.passwordReset], a
  /// number with no account is refused.
  Future<Result<OtpChallenge>> sendOtp(
    String phone, {
    OtpPurpose purpose = OtpPurpose.other,
  });

  /// A forgotten password replaced, with the code sent to [phone].
  Future<Result<void>> resetPassword({
    required String phone,
    required String code,
    required String password,
  });

  Future<Result<String>> verifyOtp({
    required String phone,
    required String code,
  });

  /// [governorate] is a `Governorate` code.
  Future<Result<User>> updateProfile({String? fullName, String? governorate});

  Future<Result<void>> deleteAccount();

  /// True when a token pair is present on the device. Says nothing about
  /// whether the backend still considers it valid.
  Future<bool> hasStoredSession();

  /// Drops local credentials without calling the API. Used when a refresh
  /// token has already been rejected.
  Future<void> clearSession();
}
