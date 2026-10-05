/// Every REST path the app talks to, relative to `AppConfig.apiBaseUrl`.
///
/// Mirrors the versioned API surface defined in the platform specification
/// (section 53). Paths live in exactly one place so a backend change never has
/// to be hunted down across the UI.
class ApiEndpoints {
  const ApiEndpoints._();

  // ----------------------------------------------------------------- auth ---
  static const String registerCustomer = '/auth/register/customer';
  static const String registerMerchant = '/auth/register/merchant';
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String refreshToken = '/auth/refresh';

  /// Phone verification, which stands in front of both registrations.
  static const String sendOtp = '/auth/otp/send';
  static const String verifyOtp = '/auth/otp/verify';
  static const String resetPassword = '/auth/reset-password';

  // ------------------------------------------------------------ customers ---
  static const String me = '/customers/me';
  static const String addresses = '/customers/me/addresses';
  static String address(String id) => '/customers/me/addresses/$id';
  static String defaultAddress(String id) =>
      '/customers/me/addresses/$id/default';

  // -------------------------------------------------------------- catalog ---
  static const String categories = '/categories';
  static String category(String id) => '/categories/$id';
  static String categoryChildren(String id) => '/categories/$id/children';
  static String categoryAttributes(String id) => '/categories/$id/attributes';
  static const String brands = '/brands';
  static String brand(String id) => '/brands/$id';
  static const String attributes = '/attributes';

  static const String products = '/products';
  static String product(String id) => '/products/$id';
  static String productVariants(String id) => '/products/$id/variants';
  static String relatedProducts(String id) => '/products/$id/related';

  // ----------------------------------------------------------------- home ---
  static const String homeSections = '/home/sections';
  static const String homeBanners = '/home/banners';
  static const String flashSales = '/promotions/flash-sales';

  // --------------------------------------------------------------- search ---
  static const String search = '/search';
  static const String searchSuggestions = '/search/suggestions';
  static const String searchHistory = '/search/history';
  static const String popularSearches = '/search/popular';
  static const String searchFilters = '/search/filters';

  // ----------------------------------------------------------------- cart ---
  static const String cart = '/cart';
  static const String cartItems = '/cart/items';
  static String cartItem(String id) => '/cart/items/$id';
  static String saveCartItemForLater(String id) =>
      '/cart/items/$id/save-for-later';
  static String moveCartItemToCart(String id) => '/cart/items/$id/move-to-cart';
  static const String cartCoupon = '/cart/coupon';
  static const String cartSummary = '/cart/summary';

  // ------------------------------------------------------------- wishlist ---
  /// Items of the customer's default wishlist. Named lists use [wishlistItems].
  static const String wishlistDefaultItems = '/wishlist/items';
  static String wishlistDefaultItem(String productId) =>
      '/wishlist/items/$productId';

  static const String wishlists = '/wishlist';
  static String wishlist(String id) => '/wishlist/$id';
  static String wishlistItems(String id) => '/wishlist/$id/items';
  static String wishlistItem(String listId, String itemId) =>
      '/wishlist/$listId/items/$itemId';
  static String shareWishlist(String id) => '/wishlist/$id/share';

  // ------------------------------------------------------------- checkout ---
  static const String checkoutSession = '/checkout/session';
  static const String checkoutShippingOptions = '/checkout/shipping-options';
  static const String checkoutPaymentMethods = '/checkout/payment-methods';
  static const String checkoutReview = '/checkout/review';
  static const String checkoutPlaceOrder = '/checkout/place-order';

  // --------------------------------------------------------------- orders ---
  static const String orders = '/orders';
  static String order(String id) => '/orders/$id';
  static String orderTimeline(String id) => '/orders/$id/timeline';
  static String orderInvoice(String id) => '/orders/$id/invoice';

  /// The delivered order this shopper has not rated yet, if any.
  static const String ratingDue = '/orders/rating-due';

  /// Stars for each store in one order, and one comment for it.
  static String rateOrder(String id) => '/orders/$id/rating';
  static String skipRating(String id) => '/orders/$id/rating-skipped';

  /// "Did you receive it?", answered for one store's part.
  static String orderReceived(String id) => '/orders/$id/received';
  static String cancelOrder(String id) => '/orders/$id/cancel';

  // ------------------------------------------------------ returns/refunds ---
  static const String returns = '/returns';
  static String returnRequest(String id) => '/returns/$id';
  static const String refunds = '/refunds';

  // -------------------------------------------------------------- reviews ---
  static String reportReview(String id) => '/reviews/$id/report';

  // ------------------------------------------------- merchants (public) ---
  static String merchantStore(String id) => '/merchants/$id/store';
  static String merchantProducts(String id) => '/merchants/$id/products';
  static String merchantReviews(String id) => '/merchants/$id/reviews';

  /// Every city with an open, approved store: Home's city chips. Their own
  /// source, because Home's stores rail shows only the featured ones.
  static const String storeCities = '/stores/cities';

  // ------------------------------------------------ merchant (own store) ---
  static const String merchantDashboard = '/merchants/me/dashboard';
  static const String merchantProfile = '/merchants/me';
  static const String merchantStoreSettings = '/merchants/me/store';

  static const String merchantOwnProducts = '/merchants/me/products';
  static const String merchantBrands = '/merchants/me/brands';
  static String merchantOwnProduct(String id) => '/merchants/me/products/$id';
  static String merchantProductVisibility(String id) =>
      '/merchants/me/products/$id/visibility';
  static String merchantProductSubmit(String id) =>
      '/merchants/me/products/$id/submit';
  static const String merchantProductCounts = '/merchants/me/products/counts';
  static String merchantProductStock(String id) =>
      '/merchants/me/products/$id/stock';
  static String merchantProductFlashSale(String id) =>
      '/merchants/me/products/$id/flash-sale';
  static const String merchantInventory = '/merchants/me/inventory';
  static String merchantInventoryAdjust(String id) =>
      '/merchants/me/inventory/$id/adjust';
  static const String merchantOrders = '/merchants/me/orders';
  static String merchantOrder(String id) => '/merchants/me/orders/$id';
  static const String merchantOrderCounts = '/merchants/me/orders/counts';

  /// A store's answer to a return request.
  static const String merchantReturns = '/merchants/me/returns';
  static String merchantReturn(String id) => '/merchants/me/returns/$id';

  static String merchantOrderStatus(String id) =>
      '/merchants/me/orders/$id/status';
  static const String merchantPromotions = '/merchants/me/promotions';
  static const String merchantCoupons = '/merchants/me/coupons';
  static String merchantCoupon(String id) => '/merchants/me/coupons/$id';

  /// A store's coupons that a shopper can use now, for its store page.
  static String storeCoupons(String merchantId) =>
      '/merchants/$merchantId/coupons';
  static const String merchantAnalytics = '/merchants/me/analytics';
  static const String merchantBills = '/merchants/me/bills';
  static const String merchantStoreOpen = '/merchants/me/store/open';
  static const String merchantDeletion = '/merchants/me/deletion';

  // -------------------------------------------------------------- support ---
  static const String supportTickets = '/support/tickets';
  static String supportTicket(String id) => '/support/tickets/$id';
  static String supportTicketMessages(String id) =>
      '/support/tickets/$id/messages';

  // ------------------------------------------------------------ messaging ---
  static const String conversations = '/messages/conversations';
  static String conversation(String id) => '/messages/conversations/$id';
  static String conversationPhotos(String id) =>
      '/messages/conversations/$id/photos';
  static String conversationMessages(String id) =>
      '/messages/conversations/$id/messages';
  static String markConversationRead(String id) =>
      '/messages/conversations/$id/read';
  static String conversationBlock(String id) =>
      '/messages/conversations/$id/block';

  /// A product, a store or a chat reported to Saba.
  static const String reports = '/reports';

  // -------------------------------------------------------- notifications ---
  static const String notifications = '/notifications';

  /// The server's live changes: text/event-stream, one line per change.
  static const String events = '/events';

  /// This phone's push address: PUT at sign-in, DELETE at sign-out.
  static const String devices = '/devices';
  static String notification(String id) => '/notifications/$id';
  static const String markAllNotificationsRead = '/notifications/read-all';
  static const String unreadCount = '/notifications/unread-count';

  // -------------------------------------------------------------- coupons ---
  /// The coupons the signed-in customer can use right now.
  static const String coupons = '/coupons';
  static const String validateCoupon = '/coupons/validate';

  // ---------------------------------------------------------------- media ---
  /// Multipart upload. The backend validates the file, generates the storage
  /// key and returns `{ id, url, thumbnailUrl }`. Not part of specification
  /// section 53; added because section 56 requires server-issued storage keys.
  static const String mediaUpload = '/media/upload';

  /// Removes an uploaded file the caller owns.
  static String media(String id) => '/media/$id';
}
