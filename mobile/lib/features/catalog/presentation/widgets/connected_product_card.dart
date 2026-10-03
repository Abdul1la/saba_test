import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../cart/domain/entities.dart';
import '../../../cart/presentation/cart_providers.dart';
import '../../../wishlist/presentation/wishlist_providers.dart';
import '../../domain/entities.dart';
import 'product_card.dart';

/// A [ProductCard] wired to navigation, the wishlist and the cart.
///
/// Every grid and carousel uses this, so "tap a product" behaves identically
/// everywhere and the wiring exists in exactly one place.
class ConnectedProductCard extends ConsumerWidget {
  const ConnectedProductCard({
    super.key,
    required this.product,
    this.width,
    this.flashSale = false,
  });

  final ProductSummary product;
  final double? width;

  /// Draws a [FlashSaleCard] instead, with the same wiring.
  final bool flashSale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A merchant browsing the catalogue has no cart; everyone else does,
    // signed in or not. A signed-out tap lands on sign-in, which is where
    // it was always going to land.
    final isShopper = !ref.watch(currentRoleProvider).isMerchant;
    final wishlistIds = ref.watch(wishlistIdsProvider);

    // The server owns wishlist membership; the card reflects the controller's
    // current view of it rather than the flag baked into a cached list.
    final resolved = product.copyWith(
      isWishlisted: wishlistIds.contains(product.id) || product.isWishlisted,
    );

    void onTap() => context.push(AppRoutes.productDetailPath(product.id));
    final onWishlistToggle = isShopper
        ? () => _toggleWishlist(context, ref, resolved)
        : null;
    if (flashSale) {
      return FlashSaleCard(
        product: resolved,
        width: width ?? AppSizes.flashSaleCardWidth,
        onTap: onTap,
        onWishlistToggle: onWishlistToggle,
        // Only the flash sale adds from the card: in a sale the add is the
        // point. Its button confirms in place, so no snackbar.
        onAddToCart: isShopper
            ? () => addProductToCart(
                context,
                ref,
                product: product,
                announceSuccess: false,
              )
            : null,
      );
    }

    return ProductCard(
      product: resolved,
      width: width,
      onTap: onTap,
      onWishlistToggle: onWishlistToggle,
    );
  }

  Future<void> _toggleWishlist(
    BuildContext context,
    WidgetRef ref,
    ProductSummary resolved,
  ) async {
    final wasSaved = resolved.isWishlisted;
    final result = await ref
        .read(wishlistControllerProvider.notifier)
        .toggle(resolved);

    if (!context.mounted) return;

    result.fold(
      ok: (_) => AppSnackBar.success(
        context,
        wasSaved
            ? context.l10n.removeFromWishlist
            : context.l10n.addedToWishlist,
      ),
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }
}

/// Adds a product to the cart and reports the outcome.
///
/// A product with variants cannot be added from a card, because the customer
/// has not chosen the options yet — they are sent to the detail screen instead.
/// Returns `true` when the item reached the cart.
Future<bool> addProductToCart(
  BuildContext context,
  WidgetRef ref, {
  required ProductSummary product,
  String? variantId,
  int quantity = 1,
  bool announceSuccess = true,
}) async {
  // It said this was done here and never did it: the product went in with
  // no colour or size, a line the store cannot pack. The options are chosen
  // on the product page, so that is where the button leads.
  if (product.hasOptions && variantId == null) {
    context.push(AppRoutes.productDetailPath(product.id));
    AppSnackBar.info(context, context.l10n.selectVariantFirst);
    return false;
  }

  if (!ref.read(isAuthenticatedProvider)) {
    context.push(AppRoutes.login);
    return false;
  }

  final result = await ref
      .read(cartControllerProvider.notifier)
      .addItem(productId: product.id, variantId: variantId, quantity: quantity);

  if (!context.mounted) return result.isOk;

  return result.fold(
    ok: (Cart _) {
      // A failure always speaks; a success only speaks when nothing else on
      // screen is going to show the customer that it worked.
      if (announceSuccess) {
        AppSnackBar.success(context, context.l10n.addedToCart);
      }
      return true;
    },
    err: (failure) {
      AppSnackBar.failure(context, failure);
      return false;
    },
  );
}
