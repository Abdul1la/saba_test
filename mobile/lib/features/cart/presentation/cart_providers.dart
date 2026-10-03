import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/result.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/cart_repository_impl.dart';
import '../domain/cart_repository.dart';
import '../domain/entities.dart';

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  ref.watch(accountIdProvider);
  return CartRepositoryImpl(ref.watch(apiClientProvider));
});

/// Tracks which cart lines have a request in flight, so each row can disable
/// its own stepper without freezing the whole screen.
class BusyCartItems extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void start(String itemId) => state = <String>{...state, itemId};

  void finish(String itemId) =>
      state = state.where((id) => id != itemId).toSet();
}

final busyCartItemsProvider = NotifierProvider<BusyCartItems, Set<String>>(
  BusyCartItems.new,
);

/// Owns the cart.
///
/// Every mutation replaces local state with the cart the server returned, so
/// quantities, stock and money are never guessed on the device.
class CartController extends AsyncNotifier<Cart> {
  CartRepository get _repository => ref.read(cartRepositoryProvider);

  @override
  Future<Cart> build() async {
    // The cart belongs to an account. Signing out empties it locally and
    // signing in loads the server-side cart.
    final isAuthenticated = ref.watch(accountIdProvider) != null;
    final isCustomer = ref.watch(currentRoleProvider).isCustomer;
    // Product names and options come back in the reader's language.
    ref.watch(acceptLanguageProvider);

    if (!isAuthenticated || !isCustomer) return const Cart.empty();

    return (await _repository.fetchCart()).unwrap();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () async => (await _repository.fetchCart()).unwrap(),
    );
  }

  Future<Result<Cart>> addItem({
    required String productId,
    String? variantId,
    int quantity = 1,
  }) {
    return _apply(
      () => _repository.addItem(
        productId: productId,
        variantId: variantId,
        quantity: quantity,
      ),
    );
  }

  Future<Result<Cart>> updateQuantity({
    required String itemId,
    required int quantity,
  }) {
    return _withBusy(
      itemId,
      () => _apply(
        () => _repository.updateQuantity(itemId: itemId, quantity: quantity),
      ),
    );
  }

  Future<Result<Cart>> removeItem(String itemId) =>
      _withBusy(itemId, () => _apply(() => _repository.removeItem(itemId)));

  Future<Result<Cart>> saveForLater(String itemId) =>
      _withBusy(itemId, () => _apply(() => _repository.saveForLater(itemId)));

  Future<Result<Cart>> moveToCart(String itemId) =>
      _withBusy(itemId, () => _apply(() => _repository.moveToCart(itemId)));

  Future<Result<Cart>> applyCoupon(String code) =>
      _apply(() => _repository.applyCoupon(code));

  Future<Result<Cart>> removeCoupon() =>
      _apply(() => _repository.removeCoupon());

  /// Called after a successful checkout, when the server has emptied the cart.
  void clearLocally() {
    state = const AsyncValue<Cart>.data(Cart.empty());
  }

  Future<Result<Cart>> _apply(Future<Result<Cart>> Function() action) async {
    final result = await action();
    if (result case Ok<Cart>(:final value)) {
      state = AsyncValue<Cart>.data(value);
    }
    // Failures leave the last known-good cart on screen; the caller surfaces
    // the message.
    return result;
  }

  Future<Result<Cart>> _withBusy(
    String itemId,
    Future<Result<Cart>> Function() action,
  ) async {
    final busy = ref.read(busyCartItemsProvider.notifier)..start(itemId);
    try {
      return await action();
    } finally {
      busy.finish(itemId);
    }
  }
}

final cartControllerProvider = AsyncNotifierProvider<CartController, Cart>(
  CartController.new,
);

/// The coupons this customer can use right now, for the cart and Home.
///
/// Empty when signed out: offers belong to an account - a first-order
/// coupon is only for an account that has not ordered yet. A failure is
/// empty too; an offer strip is a shortcut, never a reason for an error.
final availableCouponsProvider = FutureProvider<List<CouponOffer>>((ref) async {
  if (ref.watch(accountIdProvider) == null) return const <CouponOffer>[];
  final result = await ref.watch(cartRepositoryProvider).availableCoupons();
  return result.fold(ok: (offers) => offers, err: (_) => const <CouponOffer>[]);
});

/// A store's live coupons, on its page. Public: a visitor sees them too.
final storeCouponsProvider = FutureProvider.family<List<CouponOffer>, String>((
  ref,
  merchantId,
) async {
  final result = await ref
      .watch(cartRepositoryProvider)
      .storeCoupons(merchantId);
  return result.fold(ok: (offers) => offers, err: (_) => const <CouponOffer>[]);
});

/// Badge count for the bottom navigation bar.
final cartItemCountProvider = Provider<int>(
  (ref) => ref.watch(cartControllerProvider).value?.itemCount ?? 0,
);
