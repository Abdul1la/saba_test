import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/router/app_routes.dart';

/// The route access table is the client half of role separation. It never
/// replaces server-side authorization, but a mistake here would show a user a
/// screen they have no business seeing, so it is worth testing directly
/// (specification section 58).
void main() {
  group('RouteAccessTable', () {
    test('public browsing routes are open to everyone', () {
      expect(RouteAccessTable.forLocation(AppRoutes.home), RouteAccess.public);
      expect(
        RouteAccessTable.forLocation(AppRoutes.categories),
        RouteAccess.public,
      );
      expect(
        RouteAccessTable.forLocation(AppRoutes.search),
        RouteAccess.public,
      );
    });

    test('auth screens are guest-only', () {
      expect(
        RouteAccessTable.forLocation(AppRoutes.login),
        RouteAccess.guestOnly,
      );
      expect(
        RouteAccessTable.forLocation(AppRoutes.registerMerchant),
        RouteAccess.guestOnly,
      );
    });

    test('customer-only routes are marked as such', () {
      for (final route in [
        AppRoutes.cart,
        AppRoutes.checkout,
        AppRoutes.orders,
        AppRoutes.wishlist,
        AppRoutes.addresses,
      ]) {
        expect(
          RouteAccessTable.forLocation(route),
          RouteAccess.customerOnly,
          reason: '$route should be customer-only',
        );
      }
    });

    test('merchant routes are merchant-only', () {
      for (final route in [
        AppRoutes.merchantDashboard,
        AppRoutes.merchantProducts,
        AppRoutes.merchantInventory,
        AppRoutes.merchantPayouts,
      ]) {
        expect(
          RouteAccessTable.forLocation(route),
          RouteAccess.merchantOnly,
          reason: '$route should be merchant-only',
        );
      }
    });

    test('parameterised paths resolve through their pattern', () {
      expect(
        RouteAccessTable.forLocation('/product/abc-123'),
        RouteAccess.public,
      );
      expect(
        RouteAccessTable.forLocation('/orders/order-9'),
        RouteAccess.customerOnly,
      );
      expect(
        RouteAccessTable.forLocation('/merchant/orders/order-9'),
        RouteAccess.merchantOnly,
      );
    });

    test('query strings do not change the decision', () {
      expect(
        RouteAccessTable.forLocation('/search?q=phone&sort=newest'),
        RouteAccess.public,
      );
    });

    test('any unlisted /merchant path is merchant-only', () {
      expect(
        RouteAccessTable.forLocation('/merchant/something-new'),
        RouteAccess.merchantOnly,
      );
    });

    test('an unmapped route fails closed rather than open', () {
      // A screen added without an access decision must not be public.
      expect(
        RouteAccessTable.forLocation('/some/new/screen'),
        RouteAccess.authenticated,
      );
    });
  });
}
