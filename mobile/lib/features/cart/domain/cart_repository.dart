import '../../../core/errors/result.dart';
import 'entities.dart';

/// The cart lives in MySQL, not on the device.
///
/// Every mutation returns the recalculated cart so totals, shipping and
/// discounts always come from the server (specification sections 12 and 70).
abstract interface class CartRepository {
  Future<Result<Cart>> fetchCart();

  Future<Result<Cart>> addItem({
    required String productId,
    String? variantId,
    int quantity = 1,
  });

  Future<Result<Cart>> updateQuantity({
    required String itemId,
    required int quantity,
  });

  Future<Result<Cart>> removeItem(String itemId);

  Future<Result<Cart>> saveForLater(String itemId);

  Future<Result<Cart>> moveToCart(String itemId);

  /// Coupons are validated server-side; an invalid code comes back as a
  /// business-rule failure (specification section 39).
  Future<Result<Cart>> applyCoupon(String code);

  Future<Result<Cart>> removeCoupon();

  /// The coupons this customer can use now. The shopper was shown a code
  /// field and told nowhere what might go in it.
  Future<Result<List<CouponOffer>>> availableCoupons();

  /// A store's coupons that can be used now, for anyone looking at it.
  Future<Result<List<CouponOffer>>> storeCoupons(String merchantId);
}
