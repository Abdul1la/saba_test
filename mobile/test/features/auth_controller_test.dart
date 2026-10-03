import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/errors/failure.dart';
import 'package:saba_marketplace/core/errors/result.dart';
import 'package:saba_marketplace/core/providers/session_providers.dart';
import 'package:saba_marketplace/features/auth/domain/auth_repository.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';

const _customer = User(
  id: 'u1',
  fullName: 'Amina Saleh',
  email: 'amina@example.com',
  role: UserRole.customer,
  status: AccountStatus.active,
);

const _merchant = User(
  id: 'u2',
  fullName: 'Omar Ali',
  email: 'omar@example.com',
  role: UserRole.merchant,
  status: AccountStatus.active,
  merchant: MerchantSummary(
    id: 'm1',
    storeName: 'Omar Electronics',
    status: MerchantStatus.pending,
  ),
);

/// A repository stub the controller can be driven against, so the session
/// logic is tested without a server.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    this.storedSession = false,
    this.currentUserResult = const Result<User>.ok(_customer),
    this.loginResult = const Result<User>.ok(_customer),
  });

  bool storedSession;
  Result<User> currentUserResult;
  Result<User> loginResult;

  int clearSessionCalls = 0;
  int logoutCalls = 0;

  @override
  Future<bool> hasStoredSession() async => storedSession;

  @override
  Future<Result<User>> fetchCurrentUser() async => currentUserResult;

  @override
  Future<Result<User>> login({
    String? email,
    String? phone,
    required String password,
    String? code,
  }) async => loginResult;

  @override
  Future<void> clearSession() async {
    clearSessionCalls++;
    storedSession = false;
  }

  @override
  Future<Result<void>> logout() async {
    logoutCalls++;
    storedSession = false;
    return const Result<void>.ok(null);
  }

  @override
  Future<Result<User>> registerCustomer(
    CustomerRegistration registration,
  ) async => const Result<User>.ok(_customer);

  @override
  Future<Result<User>> registerMerchant(
    MerchantRegistration registration,
  ) async => const Result<User>.ok(_merchant);

  @override
  Future<Result<OtpChallenge>> sendOtp(
    String phone, {
    OtpPurpose purpose = OtpPurpose.other,
  }) async => const Result<OtpChallenge>.ok(OtpChallenge(expiresInSeconds: 60));

  @override
  Future<Result<String>> verifyOtp({
    required String phone,
    required String code,
  }) async => const Result<String>.ok('token');

  @override
  Future<Result<User>> updateProfile({
    String? fullName,
    String? governorate,
  }) async => const Result<User>.ok(_customer);

  @override
  Future<Result<void>> deleteAccount() async => const Result<void>.ok(null);

  @override
  Future<Result<void>> resetPassword({
    required String phone,
    required String code,
    required String password,
  }) async => const Result<void>.ok(null);
}

ProviderContainer _containerWith(_FakeAuthRepository repository) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    // Matches the app: no silent auto-retry, so a failure is observable.
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('starts signed out when no token is stored', () async {
    final container = _containerWith(_FakeAuthRepository());

    final state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.unauthenticated);
    expect(state.isAuthenticated, isFalse);
  });

  test('restores the session when a stored token is still valid', () async {
    final container = _containerWith(_FakeAuthRepository(storedSession: true));

    final state = await container.read(authControllerProvider.future);

    expect(state.isAuthenticated, isTrue);
    expect(state.user?.email, 'amina@example.com');
    expect(state.isCustomer, isTrue);
  });

  test('clears stale credentials when the server rejects them', () async {
    final repository = _FakeAuthRepository(
      storedSession: true,
      currentUserResult: const Result<User>.err(AuthenticationFailure()),
    );
    final container = _containerWith(repository);

    final state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.unauthenticated);
    expect(repository.clearSessionCalls, 1);
  });

  test(
    'surfaces a transport failure instead of signing the user out',
    () async {
      // Being offline is not a reason to discard a perfectly good session.
      final repository = _FakeAuthRepository(
        storedSession: true,
        currentUserResult: const Result<User>.err(NetworkFailure()),
      );
      final container = _containerWith(repository);

      Object? caught;
      try {
        await container.read(authControllerProvider.future);
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<NetworkFailure>());
      expect(repository.clearSessionCalls, 0);
    },
  );

  test('signing in publishes the authenticated session', () async {
    final container = _containerWith(_FakeAuthRepository());
    await container.read(authControllerProvider.future);

    final result = await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'amina@example.com', password: 'Secret123');

    expect(result.isOk, isTrue);
    expect(container.read(isAuthenticatedProvider), isTrue);
    expect(container.read(currentRoleProvider), UserRole.customer);
    expect(container.read(currentUserProvider)?.id, 'u1');
  });

  test('a failed sign-in leaves the session untouched', () async {
    final repository = _FakeAuthRepository(
      loginResult: const Result<User>.err(
        ValidationFailure(
          message: 'Invalid credentials',
          fieldErrors: [FieldError(field: 'email', message: 'Unknown email')],
        ),
      ),
    );
    final container = _containerWith(repository);
    await container.read(authControllerProvider.future);

    final result = await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'nobody@example.com', password: 'Secret123');

    expect(result.isErr, isTrue);
    expect(result.failureOrNull?.messageForField('email'), 'Unknown email');
    expect(container.read(isAuthenticatedProvider), isFalse);
  });

  test(
    'a merchant session reports pending approval as unable to sell',
    () async {
      final repository = _FakeAuthRepository(
        storedSession: true,
        currentUserResult: const Result<User>.ok(_merchant),
      );
      final container = _containerWith(repository);

      final state = await container.read(authControllerProvider.future);

      expect(state.isMerchant, isTrue);
      // The store exists but is not approved, so selling stays disabled.
      expect(state.canSell, isFalse);
    },
  );

  test('signing out clears the session', () async {
    final repository = _FakeAuthRepository(storedSession: true);
    final container = _containerWith(repository);
    await container.read(authControllerProvider.future);
    expect(container.read(isAuthenticatedProvider), isTrue);

    await container.read(authControllerProvider.notifier).signOut();

    expect(container.read(isAuthenticatedProvider), isFalse);
    expect(repository.logoutCalls, 1);
  });

  test('a rejected refresh token ends the session', () async {
    final container = _containerWith(_FakeAuthRepository(storedSession: true));
    await container.read(authControllerProvider.future);
    expect(container.read(isAuthenticatedProvider), isTrue);

    // This is what the auth interceptor does once a refresh definitively fails.
    container.read(sessionEventsProvider.notifier).reportExpired();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(isAuthenticatedProvider), isFalse);
  });
}
