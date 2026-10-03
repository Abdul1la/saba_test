import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/location/governorate.dart';
import '../../../core/location/governorate_picker.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/session_providers.dart';
import '../../../core/push/push_service.dart';
import '../data/auth_remote_data_source.dart';
import '../data/auth_repository_impl.dart';
import '../domain/auth_repository.dart';
import '../domain/entities.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Who is signed in, as far as this device knows.
///
/// This drives navigation only. It is never treated as permission: every
/// protected call is authorized again by the backend (specification
/// sections 5, 51 and 58).
@immutable
class AuthState {
  const AuthState({required this.status, this.user});

  const AuthState.unknown() : status = AuthStatus.unknown, user = null;
  const AuthState.signedOut()
    : status = AuthStatus.unauthenticated,
      user = null;

  final AuthStatus status;
  final User? user;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;

  UserRole get role => user?.role ?? UserRole.unknown;
  bool get isCustomer => role.isCustomer;
  bool get isMerchant => role.isMerchant;
  bool get isAdmin => role.isAdmin;

  /// A merchant whose store has not been approved yet still signs in, but the
  /// selling surfaces stay hidden until the backend approves them.
  bool get canSell => user?.merchant?.canSell ?? false;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    remote: AuthRemoteDataSource(ref.watch(apiClientProvider)),
    tokenStorage: ref.watch(tokenStorageProvider),
  );
});

/// Owns the session. Everything that needs to know "who is this" watches here.
class AuthController extends AsyncNotifier<AuthState> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async {
    // The network layer reports a dead session through this counter.
    ref.listen<int>(sessionEventsProvider, (previous, next) {
      if (previous != null && next > previous) {
        _handleSessionExpired();
      }
    });

    return _restoreSession();
  }

  Future<AuthState> _restoreSession() async {
    final repository = _repository;

    if (!await repository.hasStoredSession()) {
      return const AuthState.signedOut();
    }

    final result = await repository.fetchCurrentUser();

    return switch (result) {
      Ok<User>(:final value) => AuthState(
        status: AuthStatus.authenticated,
        user: value,
      ),
      // Credentials are stale: drop them and show the signed-out experience.
      Err<User>(failure: AuthenticationFailure()) ||
      Err<User>(failure: AuthorizationFailure()) => await _clearAndSignOut(),
      // Anything else (offline, server down) is surfaced as an error so the
      // splash screen can offer a retry instead of falsely signing the user out.
      Err<User>(:final failure) => throw failure,
    };
  }

  Future<AuthState> _clearAndSignOut() async {
    await _repository.clearSession();
    return const AuthState.signedOut();
  }

  void _handleSessionExpired() {
    if (state.value?.status == AuthStatus.unauthenticated) return;
    state = const AsyncValue<AuthState>.data(AuthState.signedOut());
  }

  /// Retries session restoration after a transport failure.
  Future<void> retry() async {
    state = const AsyncValue<AuthState>.loading();
    state = await AsyncValue.guard(_restoreSession);
  }

  /// By phone, the usual way in Iraq, or by email for those who gave one.
  ///
  /// [code] is the SMS code for the verify-at-sign-in second call; omitted on
  /// a normal sign-in.
  Future<Result<User>> signIn({
    String? email,
    String? phone,
    required String password,
    String? code,
  }) async {
    final result = await _repository.login(
      email: email,
      phone: phone,
      password: password,
      code: code,
    );
    _applyResult(result);
    return result;
  }

  Future<Result<User>> registerCustomer(
    CustomerRegistration registration,
  ) async {
    final result = await _repository.registerCustomer(registration);
    _applyResult(result);
    return result;
  }

  Future<Result<User>> registerMerchant(
    MerchantRegistration registration,
  ) async {
    final result = await _repository.registerMerchant(registration);
    _applyResult(result);
    return result;
  }

  Future<void> signOut() async {
    // This phone's pushes stop first, while the session can still say so;
    // best effort, and never in the way of leaving: whatever fails here,
    // the server moves the address to whoever signs in next anyway.
    try {
      await ref.read(pushDeviceProvider).forget();
    } on Object catch (_) {}
    // Sign out locally regardless of what the server says: the user asked to
    // leave, and the repository clears the keystore either way.
    await _repository.logout();
    state = const AsyncValue<AuthState>.data(AuthState.signedOut());
  }

  /// Drops this device's session without calling the API.
  ///
  /// Used when the session is already gone server-side - the user revoked it
  /// from the sessions screen, so POSTing to /auth/logout would only fail with
  /// a token the backend has already discarded (section 5).
  Future<void> signOutLocally() async {
    await _repository.clearSession();
    state = const AsyncValue<AuthState>.data(AuthState.signedOut());
  }

  Future<Result<User>> updateProfile({
    String? fullName,
    String? governorate,
  }) async {
    final result = await _repository.updateProfile(
      fullName: fullName,
      governorate: governorate,
    );
    _applyResult(result);
    return result;
  }

  /// Re-reads the signed-in user, for example after approval, and hands the
  /// outcome back.
  ///
  /// This returned `void` and `_applyResult` only writes on success, so a
  /// failed refresh vanished: a caller could not tell "the check failed" from
  /// "the check ran and nothing changed".
  Future<Result<User>> refreshUser() async {
    final result = await _repository.fetchCurrentUser();
    _applyResult(result);
    return result;
  }

  Future<Result<void>> deleteAccount() async {
    final result = await _repository.deleteAccount();
    if (result.isOk) {
      state = const AsyncValue<AuthState>.data(AuthState.signedOut());
    }
    return result;
  }

  void _applyResult(Result<User> result) {
    if (result case Ok<User>(:final value)) {
      state = AsyncValue<AuthState>.data(
        AuthState(status: AuthStatus.authenticated, user: value),
      );
    }
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// The signed-in user, or null. Convenient for widgets that only need the user.
final currentUserProvider = Provider<User?>(
  (ref) => ref.watch(authControllerProvider).value?.user,
);

/// The signed-in account's id, or null when no one is signed in.
///
/// Everything that holds one account's data watches this: every repository
/// but sign-in's own, and every list and controller built from them. So a
/// sign-out, or someone else signing in, drops that data at once - on an
/// open screen too - and the next account loads its own. Before, the lists
/// were kept for the whole session: a store that signed in after another
/// opened on the other store's dashboard, orders and bill.
final accountIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider.select((user) => user?.id)),
);

/// The city the shopper shops from: their profile's when signed in, else
/// the one kept on the phone. A new address, "Delivery available" on Home and
/// every "delivers to" line read this one, so they cannot disagree.
///
/// The profile comes first since Home no longer has a city button: a city
/// picked there before would otherwise win over the profile for good, with
/// nothing left on screen to change it.
final shopperCityProvider = Provider<Governorate?>(
  (ref) =>
      ref.watch(currentUserProvider)?.governorate ??
      ref.watch(shopperGovernorateProvider),
);

final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).value?.isAuthenticated ?? false,
);

final currentRoleProvider = Provider<UserRole>(
  (ref) => ref.watch(authControllerProvider).value?.role ?? UserRole.unknown,
);
