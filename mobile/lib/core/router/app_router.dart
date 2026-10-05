import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/core_providers.dart';
import '../../features/addresses/domain/entities.dart';
import '../../features/addresses/presentation/screens/address_form_screen.dart';
import '../../features/addresses/presentation/screens/addresses_screen.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/screens/language_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/auth/presentation/screens/phone_entry_screen.dart';
import '../../features/auth/presentation/screens/register_customer_screen.dart';
import '../../features/auth/presentation/screens/register_merchant_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/verify_phone_screen.dart';
import '../../features/cart/presentation/screens/cart_screen.dart';
import '../../features/catalog/domain/product_query.dart';
import '../../features/catalog/presentation/screens/categories_screen.dart';
import '../../features/catalog/presentation/screens/product_detail_screen.dart';
import '../../features/catalog/presentation/screens/product_list_screen.dart';
import '../../features/catalog/presentation/screens/storefront_screen.dart';
import '../../features/checkout/domain/entities.dart';
import '../../features/checkout/presentation/screens/checkout_screen.dart';
import '../../features/checkout/presentation/screens/order_confirmation_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/merchant/domain/entities.dart';
import '../../features/merchant/presentation/screens/merchant_account_screen.dart';
import '../../features/merchant/presentation/screens/merchant_analytics_screen.dart';
import '../../features/merchant/presentation/screens/merchant_coupons_screen.dart';
import '../../features/merchant/presentation/screens/merchant_dashboard_screen.dart';
import '../../features/merchant/presentation/screens/merchant_inventory_screen.dart';
import '../../features/merchant/presentation/screens/merchant_order_detail_screen.dart';
import '../../features/merchant/presentation/screens/merchant_orders_screen.dart';
import '../../features/merchant/presentation/screens/merchant_product_form_screen.dart';
import '../../features/merchant/presentation/screens/merchant_products_screen.dart';
import '../../features/merchant/presentation/screens/merchant_payouts_screen.dart';
import '../../features/merchant/presentation/screens/merchant_store_settings_screen.dart';
import '../../features/messaging/presentation/screens/messaging_screens.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/orders/presentation/screens/invoice_screen.dart';
import '../../features/orders/presentation/screens/order_detail_screen.dart';
import '../../features/orders/presentation/screens/orders_screen.dart';
import '../../features/profile/presentation/screens/account_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/settings_screen.dart';
import '../../features/returns/presentation/screens/request_return_screen.dart';
import '../../features/returns/presentation/screens/return_detail_screen.dart';
import '../../features/reviews/presentation/screens/merchant_reviews_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/legal/legal_screen.dart';
import '../../features/support/presentation/screens/support_screens.dart';
import '../../features/wishlist/presentation/screens/wishlist_screen.dart';
import 'app_routes.dart';
import 'deep_links.dart';
import 'app_shells.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Survives the splash screen so a link opened from an email is not lost
/// while the session is still being restored. See [PendingDeepLink].
final pendingDeepLinkProvider = Provider<PendingDeepLink>(
  (ref) => PendingDeepLink(),
);

/// How long the splash stays at least on a cold start (the user's call,
/// 2026-10-05). It went by in a frame once the session resolved, and a first
/// launch never showed it at all: it went straight to the language page.
/// The session is checked meanwhile, so a slow check adds nothing to it.
/// Zero in tests (test/flutter_test_config.dart): they start at once, as before.
@visibleForTesting
Duration splashMinimum = const Duration(milliseconds: 1500);

/// Rebuilds the router's redirect whenever the session changes, without
/// recreating the router itself (which would lose navigation history).
class _AuthRefreshNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier();

  // `listen` rather than `watch`: the provider body must not re-run, or the
  // whole navigation stack would be rebuilt on every sign-in.
  ref.listen(authControllerProvider, (_, _) => refreshNotifier.ping());

  // The splash's own time, then the redirect looks again (cancelled first,
  // so it never pings a disposed notifier).
  var splashDone = splashMinimum == Duration.zero;
  if (!splashDone) {
    final splashTimer = Timer(splashMinimum, () {
      splashDone = true;
      refreshNotifier.ping();
    });
    ref.onDispose(splashTimer.cancel);
  }
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refreshNotifier,
    redirect: (context, state) =>
        _redirect(ref, state, splashDone: splashDone),
    // An address the app does not have - one taken out for v1 like
    // /compare, or a mistyped one - lands on Home (a store's owner goes on
    // to their dashboard from there). It said "You do not have permission
    // to do that" on a screen with no way back (BUGS.md 84, 100).
    onException: (context, state, router) {
      // Never from Home itself: a failure there would come straight back.
      if (state.uri.path != AppRoutes.home) router.go(AppRoutes.home);
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.language,
        builder: (context, state) => const LanguageScreen(),
      ),

      // --------------------------------------------------------- auth ------
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) =>
            LoginScreen(phone: state.uri.queryParameters['phone']),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.registerCustomer,
        redirect: (context, state) => _numberFirst(state, merchant: false),
        builder: (context, state) => RegisterCustomerScreen(
          verifiedPhone: state.uri.queryParameters['phone'],
          phoneToken: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        // Declared before `/register/:whatever` would be; go_router matches a
        // literal segment first, so `/register/merchant` is safe beside it.
        path: AppRoutes.registerPhone,
        builder: (context, state) => PhoneEntryScreen(
          isMerchant: state.uri.queryParameters['role'] == 'merchant',
        ),
      ),
      GoRoute(
        path: AppRoutes.registerOtp,
        builder: (context, state) => OtpScreen(
          isMerchant: state.uri.queryParameters['role'] == 'merchant',
          phone: state.uri.queryParameters['phone'] ?? '',
          // Carried as `extra` rather than in the URL: it is transient, and a
          // code belongs in neither a deep link nor a navigation log.
          demoCode: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.registerMerchant,
        redirect: (context, state) => _numberFirst(state, merchant: true),
        builder: (context, state) => RegisterMerchantScreen(
          verifiedPhone: state.uri.queryParameters['phone'],
          phoneToken: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: AppRoutes.verifyPhone,
        // The number and password come as `extra`: the password belongs in no
        // URL. Opened without them - a stray deep link - there is nothing to
        // verify, so it falls back to sign-in.
        redirect: (context, state) =>
            state.extra is (String, String) ? null : AppRoutes.login,
        builder: (context, state) {
          final (phone, password) = state.extra! as (String, String);
          return VerifyPhoneScreen(phone: phone, password: password);
        },
      ),

      // ---------------------------------------------- customer shell -------
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            CustomerShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.categories,
                builder: (context, state) => const CategoriesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.cart,
                builder: (context, state) => const CartScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.orders,
                builder: (context, state) => const OrdersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.account,
                builder: (context, state) => const AccountScreen(),
              ),
            ],
          ),
        ],
      ),

      // ---------------------------------------------- merchant shell -------
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MerchantShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.merchantDashboard,
                builder: (context, state) => const MerchantDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.merchantProducts,
                builder: (context, state) => const MerchantProductsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.merchantOrders,
                builder: (context, state) => MerchantOrdersScreen(
                  initialStatus: state.uri.queryParameters['status'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.merchantAnalytics,
                builder: (context, state) => const MerchantAnalyticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.merchantAccount,
                builder: (context, state) => const MerchantAccountScreen(),
              ),
            ],
          ),
        ],
      ),

      // ------------------------------------------- customer details --------
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) =>
            SearchScreen(initialTerm: state.uri.queryParameters['q']),
      ),
      GoRoute(
        path: AppRoutes.productDetail,
        builder: (context, state) =>
            ProductDetailScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.categoryProducts,
        builder: (context, state) => ProductListScreen(
          initialQuery: ProductQuery(categoryId: state.pathParameters['id']),
          title: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: AppRoutes.storefront,
        builder: (context, state) =>
            StorefrontScreen(merchantId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.wishlist,
        builder: (context, state) => const WishlistScreen(),
      ),
      GoRoute(
        path: AppRoutes.checkout,
        builder: (context, state) {
          final query = state.uri.queryParameters;
          final productId = query['product'];
          return CheckoutScreen(
            buyNow: productId == null
                ? null
                : BuyNowLine(
                    productId: productId,
                    variantId: query['variant'],
                    quantity: int.tryParse(query['quantity'] ?? '') ?? 1,
                  ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.orderConfirmation,
        builder: (context, state) =>
            OrderConfirmationScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: AppRoutes.orderDetail,
        builder: (context, state) =>
            OrderDetailScreen(orderId: state.pathParameters['id']!),
      ),
      // Pushed over the merchant shell rather than inside a branch: it is
      // opened from the orders tab, and a detail screen that kept the bottom
      // bar would offer four ways to abandon the order half-read.
      GoRoute(
        path: AppRoutes.merchantOrderDetail,
        builder: (context, state) =>
            MerchantOrderDetailScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.requestReturn,
        builder: (context, state) =>
            RequestReturnScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.orderInvoice,
        builder: (context, state) =>
            InvoiceScreen(orderId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.returnDetail,
        builder: (context, state) =>
            ReturnDetailScreen(returnId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.merchantReviews,
        builder: (context, state) =>
            MerchantReviewsScreen(merchantId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.addresses,
        builder: (context, state) => const AddressesScreen(),
      ),
      GoRoute(
        path: AppRoutes.addressForm,
        builder: (context, state) => AddressFormScreen(
          address: state.extra is Address ? state.extra! as Address : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.conversations,
        builder: (context, state) => const ConversationsScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) => ConversationScreen(
              conversationId: state.pathParameters['id']!,
              initialDraft: state.extra is String
                  ? state.extra! as String
                  : null,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.legal,
        builder: (context, state) => LegalScreen(
          page:
              LegalPage.fromSlug(state.pathParameters['page']) ??
              LegalPage.terms,
        ),
      ),
      GoRoute(
        path: AppRoutes.supportTickets,
        builder: (context, state) => const SupportTicketsScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const NewSupportTicketScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                SupportTicketScreen(ticketId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),

      // ------------------------------------------- merchant details --------
      GoRoute(
        path: AppRoutes.merchantProductForm,
        builder: (context, state) => MerchantProductFormScreen(
          existing: state.extra is MerchantProductRow
              ? state.extra! as MerchantProductRow
              : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.merchantProductEdit,
        builder: (context, state) =>
            MerchantProductByIdScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.merchantInventory,
        builder: (context, state) => const MerchantInventoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.merchantPayouts,
        builder: (context, state) => const MerchantPayoutsScreen(),
      ),
      GoRoute(
        path: AppRoutes.merchantCoupons,
        builder: (context, state) => const MerchantCouponsScreen(),
      ),
      GoRoute(
        path: AppRoutes.merchantCouponForm,
        builder: (context, state) => MerchantCouponFormScreen(
          coupon: state.extra is MerchantCoupon
              ? state.extra! as MerchantCoupon
              : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.merchantStoreSettings,
        builder: (context, state) => const MerchantStoreSettingsScreen(),
      ),
    ],
  );
});

/// The single place that decides whether a location may be shown.
///
/// Returning a path redirects; returning null allows. This mirrors the
/// backend's rules so the UI stays coherent, but it is the backend that
/// actually enforces them (specification sections 51 and 58).
String? _redirect(Ref ref, GoRouterState state, {required bool splashDone}) {
  // G15 - a link arrives as `saba://search?q=...`, which has no path the
  // router can match. Rewrite it before anything else looks at the location.
  final normalized = normalizeDeepLink(state.uri);
  if (normalized != null) return normalized;

  // The splash first, on every cold start and the first one too, for at
  // least [splashMinimum]. A link that opened the app is kept (below) and
  // followed once it is done.
  if (!splashDone && state.matchedLocation == AppRoutes.splash) return null;

  final auth = ref.read(authControllerProvider);
  final pending = ref.read(pendingDeepLinkProvider);
  final location = state.matchedLocation;

  // Language comes before the session check, not after it. Choosing a
  // language needs no network and no account, and making a first-time user
  // wait on a round trip to pick one means that when the network is down
  // they are shown an error in a language they may not read.
  final onboardingSeen = ref.read(appPreferencesProvider).onboardingSeen;
  // And the language page is shown as it is: it fell through to the session
  // check below, which sent a first launch to the splash and the splash
  // back here, a loop the old error page hid.
  if (!onboardingSeen) {
    return location == AppRoutes.language ? null : AppRoutes.language;
  }

  // Session still resolving, or the check failed for a transport reason: hold
  // on the splash screen, which offers a retry.
  //
  // Remember where the user was actually going. A deep link opens the app
  // cold, so it always arrives during this window; without this the
  // destination - and the token in it - is thrown away.
  if (!auth.hasValue && (auth.isLoading || auth.hasError)) {
    if (location == AppRoutes.splash) return null;
    pending.remember(state.uri.toString());
    return AppRoutes.splash;
  }

  final session = auth.value;
  // Saba's staff have no screens in the app: the web is Saba's admin (Q12,
  // BUGS 145). Their session counts as signed out here, so sign-in stays on
  // screen to say so and sign them back out.
  final isAdmin = session?.isAdmin ?? false;
  final isAuthenticated = (session?.isAuthenticated ?? false) && !isAdmin;
  final isMerchant = session?.isMerchant ?? false;

  final home = isMerchant ? AppRoutes.merchantDashboard : AppRoutes.home;

  // Language is asked once, on the first launch, straight after the splash.
  // A reader who cannot read the app cannot navigate out of it, so this gate
  // comes before everything except the session check itself.
  // Splash has done its job once the session resolved. A remembered deep link
  // wins over the default home; access is still checked on the next pass, so a
  // link to a screen this user may not see still lands on sign-in.
  if (location == AppRoutes.splash) return pending.take() ?? home;

  final access = RouteAccessTable.forLocation(location);

  switch (access) {
    case RouteAccess.public:
      // A merchant landing on a customer shell tab belongs in their own shell.
      if (isMerchant && _isCustomerShellTab(location)) {
        return home;
      }
      return null;

    case RouteAccess.guestOnly:
      return isAuthenticated ? _returnTo(state) ?? home : null;

    case RouteAccess.authenticated:
      return isAuthenticated
          ? null
          : AppRoutes.signInFrom(state.uri.toString());

    case RouteAccess.customerOnly:
      if (!isAuthenticated) return AppRoutes.signInFrom(state.uri.toString());
      return isMerchant ? home : null;

    case RouteAccess.merchantOnly:
      if (!isAuthenticated) return AppRoutes.signInFrom(state.uri.toString());
      return isMerchant ? null : home;
  }
}

/// Where sign-in was opened from, to go back to once signed in.
///
/// Only a page of this app, never another address, and never a sign-in page
/// again. Whether this user may see it is checked on the next pass, so a
/// merchant sent back to the cart still ends on their dashboard.
String? _returnTo(GoRouterState state) {
  final from = state.uri.queryParameters['from'];
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return null;
  }
  final path = Uri.parse(from).path;
  if (RouteAccessTable.forLocation(path) == RouteAccess.guestOnly) return null;
  return from;
}

/// Customer shell tabs that a merchant should not be parked on.
///
/// The public catalog routes (product, category, store, search) stay reachable
/// for everyone, so they are deliberately absent here.
bool _isCustomerShellTab(String location) => const <String>{
  AppRoutes.home,
  AppRoutes.categories,
  AppRoutes.account,
}.contains(location);

/// The sign-up form only with a verified number: its phone and the token
/// the code step gave. Opened bare, #/register/merchant went straight to the
/// form and made a store for a number that never got a code (the tester).
/// The real server must also refuse a sign-up without a valid token
/// (BUGS.md 108): a made-up token still passes here.
String? _numberFirst(GoRouterState state, {required bool merchant}) {
  final query = state.uri.queryParameters;
  final verified =
      (query['phone'] ?? '').isNotEmpty && (query['token'] ?? '').isNotEmpty;
  return verified ? null : AppRoutes.registerPhonePath(merchant: merchant);
}
