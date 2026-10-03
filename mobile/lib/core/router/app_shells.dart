import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/cart/presentation/cart_providers.dart';
import '../../features/reviews/presentation/rate_order_providers.dart';
import '../../features/reviews/presentation/widgets/rate_order_sheet.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import '../widgets/saba_nav_bar.dart';

/// The accounts shown the "did it arrive" sheet since the app opened.
///
/// The shell asked each time it was built, and it is built again on the way
/// back from a page outside it: after "Not now", or with a second order
/// delivered, the sheet came straight back on Home and Account (the
/// tester). Once an app opening, as it was meant.
final deliveryAskedProvider = NotifierProvider<DeliveryAsked, Set<String>>(
  DeliveryAsked.new,
);

class DeliveryAsked extends Notifier<Set<String>> {
  /// Cleared at sign-out: signing in again is a new visit.
  @override
  Set<String> build() {
    ref.watch(isAuthenticatedProvider);
    return const <String>{};
  }

  void mark(String account) => state = {...state, account};
}

/// Bottom navigation for the customer experience.
///
/// Customers and merchants get entirely separate shells, so a merchant can
/// never end up inside customer navigation, nor the reverse (specification
/// section 58).
class CustomerShell extends ConsumerStatefulWidget {
  const CustomerShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  @override
  void initState() {
    super.initState();
    // "When the shopper opens the app": this shell is where a signed-in
    // shopper lands, and it is built once. Asked after the first frame so
    // the sheet opens over a drawn screen rather than an empty one.
    WidgetsBinding.instance.addPostFrameCallback((_) => _askAboutDelivery());
  }

  Future<void> _askAboutDelivery() async {
    final account = ref.read(accountIdProvider);
    if (account == null || ref.read(deliveryAskedProvider).contains(account)) {
      return;
    }
    final order = await ref.read(orderToRateProvider.future);
    if (order == null || !mounted) return;
    ref.read(deliveryAskedProvider.notifier).mark(account);
    await RateOrderSheet.show(context, order);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cartCount = ref.watch(cartItemCountProvider);
    final navigationShell = widget.navigationShell;

    // The bar floats over the content rather than reserving a strip of it, so
    // it is stacked on top and every scroll view underneath pads its bottom by
    // `space/nav-safe`.
    return Scaffold(
      body: Stack(
        children: [
          navigationShell,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SabaNavBar(
              selectedIndex: navigationShell.currentIndex,
              onSelected: (index) => navigationShell.goBranch(
                index,
                // Tapping the active tab again pops it back to its root.
                initialLocation: index == navigationShell.currentIndex,
              ),
              destinations: [
                SabaNavDestination(icon: SabaIcons.home, label: l10n.navHome),
                SabaNavDestination(
                  icon: SabaIcons.grid,
                  label: l10n.navCategories,
                ),
                SabaNavDestination(
                  icon: SabaIcons.bag,
                  label: l10n.navCart,
                  badgeCount: cartCount,
                ),
                SabaNavDestination(
                  icon: SabaIcons.receipt,
                  label: l10n.navOrders,
                ),
                SabaNavDestination(
                  icon: SabaIcons.user,
                  label: l10n.navAccount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom navigation for the merchant experience.
class MerchantShell extends StatelessWidget {
  const MerchantShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      body: Stack(
        children: [
          navigationShell,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SabaNavBar(
              selectedIndex: navigationShell.currentIndex,
              onSelected: (index) => navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              ),
              destinations: [
                SabaNavDestination(
                  icon: SabaIcons.barChart,
                  label: l10n.navDashboard,
                ),
                SabaNavDestination(
                  icon: SabaIcons.box,
                  label: l10n.navProducts,
                ),
                SabaNavDestination(
                  icon: SabaIcons.receipt,
                  label: l10n.navOrders,
                ),
                SabaNavDestination(
                  icon: SabaIcons.trendingUp,
                  label: l10n.navAnalytics,
                ),
                SabaNavDestination(
                  icon: SabaIcons.store,
                  label: l10n.navAccount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
