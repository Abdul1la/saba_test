/// Every route in the app, in one place.
///
/// Paths and names are constants so navigation never relies on a string typed
/// at a call site. Access control is declared here too — see [RouteAccess] —
/// and enforced by the redirect in `app_router.dart`.
class AppRoutes {
  const AppRoutes._();

  // ---------------------------------------------------------------- system --
  static const String splash = '/splash';
  static const String language = '/language';

  // ------------------------------------------------------------------ auth --
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String registerCustomer = '/register';
  static const String registerMerchant = '/register/merchant';
  static const String registerPhone = '/register/phone';
  static const String registerOtp = '/register/otp';

  /// Verify-at-sign-in: a right password on a number Saba never checked. The
  /// password rides in `extra`, never here, so this path carries nothing on
  /// its own.
  static const String verifyPhone = '/sign-in/verify';

  // ------------------------------------------------- customer shell tabs ---
  static const String home = '/home';
  static const String categories = '/categories';
  static const String cart = '/cart';
  static const String orders = '/orders';
  static const String account = '/account';

  // ------------------------------------------------------ customer detail ---
  static const String search = '/search';
  static const String productDetail = '/product/:id';
  static const String categoryProducts = '/category/:id';
  static const String storefront = '/store/:id';
  static const String wishlist = '/wishlist';
  static const String checkout = '/checkout';
  static const String orderConfirmation = '/checkout/confirmation/:orderId';
  static const String orderDetail = '/orders/:id';
  static const String requestReturn = '/orders/:id/return';
  static const String orderInvoice = '/orders/:id/invoice';
  static const String returnDetail = '/returns/:id';
  static const String merchantReviews = '/store/:id/reviews';
  static const String addresses = '/addresses';
  static const String addressForm = '/addresses/form';
  static const String notifications = '/notifications';
  static const String conversations = '/messages';
  static const String conversationDetail = '/messages/:id';
  static const String supportTickets = '/support';
  static const String supportTicketDetail = '/support/:id';
  static const String newSupportTicket = '/support/new';
  static const String profile = '/account/profile';
  static const String settings = '/account/settings';
  static const String legal = '/legal/:page';

  // --------------------------------------------------- merchant shell tabs ---
  static const String merchantDashboard = '/merchant';
  static const String merchantProducts = '/merchant/products';
  static const String merchantOrders = '/merchant/orders';
  static const String merchantAnalytics = '/merchant/analytics';
  static const String merchantAccount = '/merchant/account';

  // ------------------------------------------------------ merchant detail ---
  static const String merchantProductForm = '/merchant/products/form';

  /// One of the store's products, opened for editing by its id: where its
  /// "approved" or "not approved" notification leads.
  static const String merchantProductEdit = '/merchant/products/edit/:id';
  static const String merchantInventory = '/merchant/inventory';
  static const String merchantOrderDetail = '/merchant/orders/:id';
  static const String merchantPayouts = '/merchant/payouts';
  static const String merchantStoreSettings = '/merchant/store';
  static const String merchantCoupons = '/merchant/coupons';
  static const String merchantCouponForm = '/merchant/coupons/form';

  // --------------------------------------------------------------- helpers ---
  static String productDetailPath(String id) => '/product/$id';
  static String categoryProductsPath(String id) => '/category/$id';
  static String storefrontPath(String id) => '/store/$id';
  static String orderDetailPath(String id) => '/orders/$id';
  static String orderConfirmationPath(String orderId) =>
      '/checkout/confirmation/$orderId';
  static String requestReturnPath(String orderId) => '/orders/$orderId/return';
  static String merchantReviewsPath(String id) => '/store/$id/reviews';
  static String orderInvoicePath(String orderId) => '/orders/$orderId/invoice';
  static String returnDetailPath(String id) => '/returns/$id';

  static String conversationPath(String id) => '/messages/$id';

  /// Checkout for one product alone - "Buy now" - with the cart untouched.
  static String buyNowPath({
    required String productId,
    String? variantId,
    int quantity = 1,
  }) => Uri(
    path: checkout,
    queryParameters: <String, String>{
      'product': productId,
      'variant': ?variantId,
      'quantity': '$quantity',
    },
  ).toString();

  /// Sign-in that comes back to [from] afterwards, not to Home.
  /// Sign-in with [phone] already in the field: "Sign in instead" on a
  /// number that has an account made the person type it again.
  static String signInWith(String phone) => Uri(
    path: login,
    queryParameters: <String, String>{'phone': phone},
  ).toString();

  static String signInFrom(String from) => Uri(
    path: login,
    queryParameters: <String, String>{'from': from},
  ).toString();
  static String supportTicketPath(String id) => '/support/$id';
  static String legalPath(String page) => '/legal/$page';
  static String merchantOrderDetailPath(String id) => '/merchant/orders/$id';
  static String merchantProductEditPath(String id) =>
      '/merchant/products/edit/$id';

  /// The orders list already filtered. A dashboard row that says "7 orders to
  /// confirm" and then opens all thirty-eight is a row that lied about where
  /// it was going.
  /// The role travels through phone and OTP as a query parameter rather than
  /// as screen state, so the two steps survive a process death mid-signup and
  /// still know which form to open at the end.
  static String registerPhonePath({required bool merchant}) =>
      '$registerPhone?role=${merchant ? 'merchant' : 'customer'}';

  static String registerOtpPath({
    required bool merchant,
    required String phone,
  }) =>
      '$registerOtp?role=${merchant ? 'merchant' : 'customer'}'
      '&phone=${Uri.encodeComponent(phone)}';

  /// The sign-up form, reached only with a verified number in hand.
  static String registerPath({
    required bool merchant,
    required String phone,
    required String token,
  }) =>
      '${merchant ? registerMerchant : registerCustomer}'
      '?phone=${Uri.encodeComponent(phone)}'
      '&token=${Uri.encodeComponent(token)}';

  static String merchantOrdersPath({String? status}) =>
      status == null || status.isEmpty
      ? merchantOrders
      : '$merchantOrders?status=$status';
}

/// Who may open a route.
enum RouteAccess {
  /// Anyone, signed in or not: the public storefront.
  public,

  /// Only while signed out. Signing in bounces away from these.
  guestOnly,

  /// Any signed-in user.
  authenticated,

  /// Signed-in customers only.
  customerOnly,

  /// Signed-in merchants only.
  merchantOnly,
}

/// Declarative access table used by the router's redirect.
///
/// Keeping this as data rather than scattered `if` statements means a new
/// screen cannot accidentally ship without an access decision.
class RouteAccessTable {
  const RouteAccessTable._();

  static const Map<String, RouteAccess> _rules = <String, RouteAccess>{
    AppRoutes.splash: RouteAccess.public,
    AppRoutes.language: RouteAccess.public,

    AppRoutes.login: RouteAccess.guestOnly,
    AppRoutes.forgotPassword: RouteAccess.guestOnly,
    AppRoutes.registerCustomer: RouteAccess.guestOnly,
    AppRoutes.registerMerchant: RouteAccess.guestOnly,
    AppRoutes.registerPhone: RouteAccess.guestOnly,
    AppRoutes.registerOtp: RouteAccess.guestOnly,
    AppRoutes.verifyPhone: RouteAccess.guestOnly,

    AppRoutes.home: RouteAccess.public,
    AppRoutes.categories: RouteAccess.public,
    AppRoutes.search: RouteAccess.public,
    AppRoutes.productDetail: RouteAccess.public,
    AppRoutes.categoryProducts: RouteAccess.public,
    AppRoutes.storefront: RouteAccess.public,

    AppRoutes.notifications: RouteAccess.authenticated,
    AppRoutes.conversations: RouteAccess.authenticated,
    AppRoutes.conversationDetail: RouteAccess.authenticated,
    AppRoutes.supportTickets: RouteAccess.authenticated,
    AppRoutes.supportTicketDetail: RouteAccess.authenticated,
    AppRoutes.newSupportTicket: RouteAccess.authenticated,
    AppRoutes.profile: RouteAccess.authenticated,
    AppRoutes.settings: RouteAccess.authenticated,
    AppRoutes.account: RouteAccess.public,
    // Read before there is an account: sign-up links to them.
    AppRoutes.legal: RouteAccess.public,

    AppRoutes.cart: RouteAccess.customerOnly,
    AppRoutes.checkout: RouteAccess.customerOnly,
    AppRoutes.orderConfirmation: RouteAccess.customerOnly,
    AppRoutes.orders: RouteAccess.customerOnly,
    AppRoutes.orderDetail: RouteAccess.customerOnly,
    AppRoutes.requestReturn: RouteAccess.customerOnly,
    AppRoutes.orderInvoice: RouteAccess.customerOnly,
    AppRoutes.returnDetail: RouteAccess.customerOnly,
    AppRoutes.merchantReviews: RouteAccess.public,
    AppRoutes.wishlist: RouteAccess.customerOnly,
    AppRoutes.addresses: RouteAccess.customerOnly,
    AppRoutes.addressForm: RouteAccess.customerOnly,

    AppRoutes.merchantDashboard: RouteAccess.merchantOnly,
    AppRoutes.merchantProducts: RouteAccess.merchantOnly,
    AppRoutes.merchantProductForm: RouteAccess.merchantOnly,
    AppRoutes.merchantProductEdit: RouteAccess.merchantOnly,
    AppRoutes.merchantInventory: RouteAccess.merchantOnly,
    AppRoutes.merchantOrders: RouteAccess.merchantOnly,
    AppRoutes.merchantOrderDetail: RouteAccess.merchantOnly,
    AppRoutes.merchantAnalytics: RouteAccess.merchantOnly,
    AppRoutes.merchantPayouts: RouteAccess.merchantOnly,
    AppRoutes.merchantStoreSettings: RouteAccess.merchantOnly,
    AppRoutes.merchantCoupons: RouteAccess.merchantOnly,
    AppRoutes.merchantCouponForm: RouteAccess.merchantOnly,
    AppRoutes.merchantAccount: RouteAccess.merchantOnly,
  };

  /// Resolves the rule for a concrete location such as `/product/42`.
  ///
  /// Defaults to [RouteAccess.authenticated] for anything unlisted, so an
  /// unmapped route fails closed rather than open.
  static RouteAccess forLocation(String location) {
    final path = location.split('?').first;

    final exact = _rules[path];
    if (exact != null) return exact;

    for (final entry in _rules.entries) {
      if (_matches(entry.key, path)) return entry.value;
    }

    // Anything under /merchant is merchant-only even if it was not listed.
    if (path.startsWith('/merchant')) return RouteAccess.merchantOnly;

    return RouteAccess.authenticated;
  }

  /// Matches a concrete path against a pattern containing `:params`.
  static bool _matches(String pattern, String path) {
    if (!pattern.contains(':')) return false;
    final patternSegments = pattern.split('/');
    final pathSegments = path.split('/');
    if (patternSegments.length != pathSegments.length) return false;
    for (var i = 0; i < patternSegments.length; i++) {
      final segment = patternSegments[i];
      if (segment.startsWith(':')) continue;
      if (segment != pathSegments[i]) return false;
    }
    return true;
  }
}
