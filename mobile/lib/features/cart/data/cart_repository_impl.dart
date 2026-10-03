import '../../../core/config/api_endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/json_reader.dart';
import '../../catalog/domain/entities.dart';
import '../domain/cart_repository.dart';
import '../domain/entities.dart';
import '../../../core/location/governorate.dart';

/// Maps cart JSON into domain objects.
class CartMappers {
  const CartMappers._();

  static Cart cart(Map<String, dynamic> json) {
    final totalsJson = Json.objectOrNull(json, const ['totals', 'summary']);
    final couponJson = Json.objectOrNull(json, const [
      'coupon',
      'appliedCoupon',
    ]);

    return Cart(
      id: Json.str(json, const ['id', 'cartId']),
      groups: Json.mapList(
        Json.objects(json, const ['groups', 'merchantGroups', 'sellers']),
        group,
      ),
      totals: totalsJson == null
          ? const CartTotals.empty()
          : totals(totalsJson),
      savedForLater: Json.mapList(
        Json.objects(json, const ['savedForLater', 'saved']),
        (entry) => item(entry, isSavedForLater: true),
      ),
      coupon: couponJson == null ? null : coupon(couponJson),
    );
  }

  static CartMerchantGroup group(Map<String, dynamic> json) {
    final merchantJson = Json.objectOrNull(json, const ['merchant', 'store']);
    return CartMerchantGroup(
      merchantId: merchantJson == null
          ? Json.str(json, const ['merchantId'])
          : Json.str(merchantJson, const ['id', 'merchantId']),
      merchantName: merchantJson == null
          ? Json.str(json, const ['merchantName', 'storeName'])
          : Json.str(merchantJson, const ['storeName', 'name']),
      items: Json.mapList(
        Json.objects(json, const ['items', 'cartItems']),
        (entry) => item(entry),
      ),
      subtotal: Json.number(json, const ['subtotal', 'itemsTotal']),
      currencyCode: Json.str(json, const [
        'currencyCode',
        'currency',
      ], fallback: AppConfig.fallbackCurrencyCode),
      logoUrl: merchantJson == null
          ? Json.strOrNull(json, const ['logoUrl'])
          : Json.strOrNull(merchantJson, const ['logoUrl', 'logo']),
      governorate: merchantJson == null
          ? null
          : Governorate.fromApi(
              merchantJson['governorate'] ?? merchantJson['city'],
            ),
      shippingFee: Json.numberOrNull(json, const ['shippingFee', 'shipping']),
      shippingMethodName: Json.strOrNull(json, const [
        'shippingMethodName',
        'shippingMethod',
      ]),
      freeShippingThreshold: Json.numberOrNull(json, const [
        'freeShippingThreshold',
      ]),
      estimatedDelivery: Json.strOrNull(json, const [
        'estimatedDelivery',
        'deliveryEstimate',
      ]),
      deliversHere: Json.boolean(json, const ['deliversHere'], fallback: true),
    );
  }

  static CartItem item(
    Map<String, dynamic> json, {
    bool isSavedForLater = false,
  }) {
    final quantity = Json.integerOrNull(json, const [
      'availableQuantity',
      'stock',
    ]);
    return CartItem(
      id: Json.str(json, const ['id', 'cartItemId']),
      productId: Json.str(json, const ['productId', 'product_id']),
      name: Json.str(json, const ['name', 'productName', 'title']),
      unitPrice: Json.number(json, const ['unitPrice', 'price']),
      quantity: Json.integer(json, const ['quantity', 'qty'], fallback: 1),
      lineTotal: Json.number(json, const ['lineTotal', 'total', 'subtotal']),
      currencyCode: Json.str(json, const [
        'currencyCode',
        'currency',
      ], fallback: AppConfig.fallbackCurrencyCode),
      stockStatus: StockStatus.fromApi(
        json['stockStatus'] ?? json['stock_status'],
        quantity: quantity,
      ),
      variantId: Json.strOrNull(json, const ['variantId', 'productVariantId']),
      variantLabel: Json.strOrNull(json, const [
        'variantLabel',
        'variantName',
        'variant',
      ]),
      imageUrl: Json.strOrNull(json, const ['imageUrl', 'image', 'thumbnail']),
      originalUnitPrice: Json.numberOrNull(json, const [
        'originalUnitPrice',
        'originalPrice',
      ]),
      availableQuantity: quantity,
      isSavedForLater:
          isSavedForLater || Json.boolean(json, const ['isSavedForLater']),
    );
  }

  static CartTotals totals(Map<String, dynamic> json) => CartTotals(
    subtotal: Json.number(json, const ['subtotal', 'itemsTotal']),
    total: Json.number(json, const ['total', 'grandTotal']),
    currencyCode: Json.str(json, const [
      'currencyCode',
      'currency',
    ], fallback: AppConfig.fallbackCurrencyCode),
    discount: Json.number(json, const ['discount', 'discountTotal']),
    shipping: Json.number(json, const ['shipping', 'shippingTotal']),
    tax: Json.number(json, const ['tax', 'taxTotal']),
    couponDiscount: Json.number(json, const ['couponDiscount']),
  );

  static AppliedCoupon coupon(Map<String, dynamic> json) => AppliedCoupon(
    code: Json.str(json, const ['code', 'couponCode']),
    discountAmount: Json.number(json, const ['discountAmount', 'discount']),
    description: Json.strOrNull(json, const ['description', 'label']),
    applies: Json.boolean(json, const ['applies'], fallback: true),
    minOrderAmount: Json.numberOrNull(json, const ['minOrderAmount']),
  );

  static CouponOffer couponOffer(Map<String, dynamic> json) => CouponOffer(
    code: Json.str(json, const ['code', 'couponCode']),
    isPercentage: Json.str(json, const [
      'discountType',
      'type',
    ], fallback: 'PERCENTAGE').toUpperCase().startsWith('PERCENT'),
    value: Json.number(json, const ['value', 'discountValue']),
    currencyCode: Json.strOrNull(json, const ['currencyCode', 'currency']),
    minOrderAmount: Json.numberOrNull(json, const [
      'minOrderAmount',
      'minimumOrderAmount',
    ]),
    firstOrderOnly: Json.boolean(json, const [
      'firstOrderOnly',
      'isFirstOrder',
    ], fallback: false),
    merchantId: Json.strOrNull(json, const ['merchantId', 'storeId']),
    merchantName: Json.strOrNull(json, const ['merchantName', 'storeName']),
  );
}

/// Every mutation returns the recalculated cart, so the client never has to
/// guess what a change did to the totals.
class CartRepositoryImpl implements CartRepository {
  const CartRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<Cart>> fetchCart() =>
      client.get<Cart>(ApiEndpoints.cart, decoder: _decode);

  @override
  Future<Result<Cart>> addItem({
    required String productId,
    String? variantId,
    int quantity = 1,
  }) {
    return client.post<Cart>(
      ApiEndpoints.cartItems,
      data: <String, dynamic>{
        'productId': productId,
        'variantId': ?variantId,
        'quantity': quantity,
      },
      decoder: _decode,
    );
  }

  @override
  Future<Result<Cart>> updateQuantity({
    required String itemId,
    required int quantity,
  }) {
    return client.patch<Cart>(
      ApiEndpoints.cartItem(itemId),
      data: <String, dynamic>{'quantity': quantity},
      decoder: _decode,
    );
  }

  @override
  Future<Result<Cart>> removeItem(String itemId) =>
      client.delete<Cart>(ApiEndpoints.cartItem(itemId), decoder: _decode);

  @override
  Future<Result<Cart>> saveForLater(String itemId) => client.post<Cart>(
    ApiEndpoints.saveCartItemForLater(itemId),
    decoder: _decode,
  );

  @override
  Future<Result<Cart>> moveToCart(String itemId) => client.post<Cart>(
    ApiEndpoints.moveCartItemToCart(itemId),
    decoder: _decode,
  );

  @override
  Future<Result<Cart>> applyCoupon(String code) => client.post<Cart>(
    ApiEndpoints.cartCoupon,
    data: <String, dynamic>{'code': code},
    decoder: _decode,
  );

  @override
  Future<Result<Cart>> removeCoupon() =>
      client.delete<Cart>(ApiEndpoints.cartCoupon, decoder: _decode);

  @override
  Future<Result<List<CouponOffer>>> availableCoupons() =>
      client.get<List<CouponOffer>>(
        ApiEndpoints.coupons,
        decoder: (envelope) =>
            Json.mapList(envelope.dataAsList, CartMappers.couponOffer),
      );

  @override
  Future<Result<List<CouponOffer>>> storeCoupons(String merchantId) =>
      client.get<List<CouponOffer>>(
        ApiEndpoints.storeCoupons(merchantId),
        decoder: (envelope) =>
            Json.mapList(envelope.dataAsList, CartMappers.couponOffer),
      );

  static Cart _decode(ApiEnvelope envelope) =>
      CartMappers.cart(envelope.dataAsMap);
}
