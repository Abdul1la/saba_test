import 'package:flutter/material.dart';

import '../../../../core/location/governorate_picker.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/price_text.dart';
import '../../domain/entities.dart';

/// `card/product` — the one card for a product, wherever a product appears:
/// Home, Browse, a category, search, a store, a rail, favourites.
///
/// A square photo with rounded corners, the favourite heart on it and the
/// discount or out-of-stock badge in its corner; then the name on two lines,
/// the store, the price with the original struck through above it, and
/// "Delivery available" when the store brings it to the shopper's city.
/// A soft shadow, no border. The flash sale keeps its own [FlashSaleCard].
///
/// Every row is a fixed box, so the card is a fixed height for its width and
/// a grid never goes ragged: size the grid or rail with [heightFor].
///
/// Presentation only: it reports taps upward and never talks to a repository
/// itself (specification section 18).
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onWishlistToggle,
    this.width,
  });

  final ProductSummary product;
  final VoidCallback onTap;

  /// The heart; null where there is no favourites list to add to.
  final VoidCallback? onWishlistToggle;

  /// Set when the card sits in a horizontal rail.
  final double? width;

  /// The product name, at the size the card draws it.
  ///
  /// Derived from `type/card-title` so it keeps the theme's family, weight and
  /// — the part that matters — Arabic's taller line height.
  static TextStyle nameStyle(BuildContext context) {
    final base = context.textStyles.titleLarge!;
    return base.copyWith(fontSize: 13.5, letterSpacing: -0.2);
  }

  static double _nameHeight(BuildContext context) {
    final style = nameStyle(context);
    return MediaQuery.textScalerOf(context).scale(style.fontSize!) *
        (style.height ?? 1.3) *
        2;
  }

  /// Height of the line that names the store. The flash-sale card uses it
  /// too.
  static double _storeLineHeight(BuildContext context) {
    final text = MediaQuery.textScalerOf(context).scale(11) * 1.4;
    return text < 16 ? 16 : text;
  }

  /// One line: the struck-through price sits beside the price, not on a
  /// line of its own that every card kept empty in case. The currency mark
  /// is a smaller span on the same baseline and makes the line a little
  /// taller, hence 1.35.
  static double _priceHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(16) * 1.35;

  static double _deliveryHeight(BuildContext context) {
    final line = context.textStyles.labelSmall?.height ?? 1.4;
    final text = MediaQuery.textScalerOf(context).scale(12) * line;
    return text < 16 ? 16 : text;
  }

  /// The exact height this card occupies at [width]: a square photo, then
  /// fixed rows. A sum, not an estimate.
  static double heightFor(BuildContext context, double width) {
    const padding = AppSizes.productCardPadding;
    return padding +
        (width - padding * 2) +
        AppSizes.productCardGap +
        _nameHeight(context) +
        AppSpacing.xs +
        _storeLineHeight(context) +
        AppSpacing.xs +
        _priceHeight(context) +
        AppSpacing.xs +
        _deliveryHeight(context) +
        padding;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppElevation.card,
        ),
        child: Material(
          color: context.colors.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.productCardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                // Sizes to its own content rather than stretching to whatever
                // box it is put in, which is what makes [heightFor] the
                // card's height rather than the grid's.
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProductImage(
                    product: product,
                    onWishlistToggle: onWishlistToggle,
                    // "Only a few left" is the product page's to say; on a
                    // card it pushed at the owner of the shop as well.
                    showLowStock: false,
                  ),
                  const SizedBox(height: AppSizes.productCardGap),
                  SizedBox(
                    height: _nameHeight(context),
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: nameStyle(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: _storeLineHeight(context),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      // The store, then where it is: small, and in colour,
                      // because the city decides whether it can come.
                      child: Row(
                        children: [
                          Flexible(
                            flex: 3,
                            child: Text(
                              product.merchantName ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.labelSmall?.copyWith(
                                color: market.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (product.merchantCity case final city?) ...[
                            const SizedBox(width: AppSpacing.xs + 2),
                            Flexible(flex: 2, child: CityLabel(city)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: _priceHeight(context),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      // Shrinks whole rather than cutting a seven-figure
                      // price with its original beside it.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: CardPrice(
                          amount: product.price,
                          originalAmount: product.originalPrice,
                          currencyCode: product.currencyCode,
                          muted: !product.isAvailable,
                          inline: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: _deliveryHeight(context),
                    child: product.deliveryAvailable && product.isAvailable
                        ? Row(
                            children: [
                              SabaIcon(
                                SabaIcons.truck,
                                size: 14,
                                color: market.success,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Flexible(
                                child: Text(
                                  l10n.deliveryAvailable,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textStyles.labelSmall
                                      ?.copyWith(
                                        color: market.success,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `card/flash-sale` — the card the flash-sale rail uses, so a limited offer
/// never reads as one more product in the feed.
///
/// A wide image with the sale's badges, the store above the name, the price
/// beside the name rather than under it, and a full "Add to cart" pill with
/// the favourite ringed beside it: in a flash sale the add is the point, so it
/// is a real button, not a corner square. Built on amber - its outline, its
/// pill and the ring - because a sale is heat, not one more product. Like [ProductCard] it is a fixed
/// height for its width — size the rail with [heightFor].
class FlashSaleCard extends StatelessWidget {
  const FlashSaleCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onWishlistToggle,
    this.onAddToCart,
    this.width = AppSizes.flashSaleCardWidth,
  });

  final ProductSummary product;
  final VoidCallback onTap;
  final VoidCallback? onWishlistToggle;

  /// See [ProductCard.onAddToCart].
  final Future<bool> Function()? onAddToCart;
  final double width;

  static const double _padding = AppSpacing.md;

  /// The action row answers a full 48 but draws 40, so 4 of it is already
  /// space below the buttons; the padding gives that back.
  static const double _bottomPadding = _padding - AppSpacing.xs;

  static const double _priceSize = 17;

  static TextStyle _nameStyle(BuildContext context) =>
      ProductCard.nameStyle(context).copyWith(fontSize: 14.5);

  /// Two lines of name, or the price with its original struck through above
  /// it — whichever is taller.
  static double _nameRowHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = _nameStyle(context);
    final name = scaler.scale(style.fontSize!) * (style.height ?? 1.3) * 2;
    final price = scaler.scale(11) * 1.4 + scaler.scale(_priceSize) * 1.1;
    return name > price ? name : price;
  }

  /// The exact height this card occupies at [width]; a sum of fixed boxes.
  static double heightFor(BuildContext context, double width) {
    return _padding +
        (width - _padding * 2) / AppSizes.flashSaleImageRatio +
        AppSizes.productCardGap +
        ProductCard._storeLineHeight(context) +
        AppSpacing.xs +
        _nameRowHeight(context) +
        AppSpacing.xs +
        AppSizes.minTapTarget +
        _bottomPadding;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final seller = product.merchantName ?? product.brandName ?? '';

    return SizedBox(
      width: width,
      child: Material(
        color: context.colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: market.heat, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              _padding,
              _padding,
              _padding,
              _bottomPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ProductImage(
                  product: product,
                  aspectRatio: AppSizes.flashSaleImageRatio,
                ),
                const SizedBox(height: AppSizes.productCardGap),
                SizedBox(
                  height: ProductCard._storeLineHeight(context),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      seller,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.labelSmall?.copyWith(
                        color: market.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: _nameRowHeight(context),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _nameStyle(context),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // A price is never cut short. Past its share of the
                      // width - a seven-figure price at the largest text
                      // size - it shrinks whole instead.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (width - _padding * 2) * 0.55,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: CardPrice(
                            amount: product.price,
                            originalAmount: product.originalPrice,
                            currencyCode: product.currencyCode,
                            muted: !product.isAvailable,
                            size: _priceSize,
                            alignEnd: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: AppSizes.minTapTarget,
                  child: Row(
                    children: [
                      if (onWishlistToggle != null) ...[
                        _WishlistButton(
                          isActive: product.isWishlisted,
                          onPressed: onWishlistToggle!,
                          ringed: true,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      if (onAddToCart != null)
                        Expanded(
                          child: CornerActionButton(
                            onPressed: product.isAvailable ? onAddToCart : null,
                            tooltip: l10n.addToCart,
                            label: product.isAvailable
                                ? l10n.addToCart
                                : l10n.outOfStock,
                            color: market.heat,
                            onColor: market.onHeat,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The image tile, its badges and the favourite circle.
class _ProductImage extends StatelessWidget {
  const _ProductImage({
    required this.product,
    this.onWishlistToggle,
    this.aspectRatio = AppSizes.productCardImageRatio,
    this.showLowStock = true,
  });

  final ProductSummary product;
  final VoidCallback? onWishlistToggle;
  final double aspectRatio;
  final bool showLowStock;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final discount = product.discountPercentage;
    // The design never shows a stretched stock photo in place of a product:
    // it draws the thing itself in line art on the neutral tile.
    final placeholder = iconForName(product.name, product.id.hashCode);

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // No image is a neutral tile that says so, never a stretched
          // placeholder photo pretending to be the product.
          if ((product.imageUrl ?? '').trim().isEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                color: market.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SabaIcon(placeholder, size: 56, color: market.starEmpty),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.noImage,
                    style: context.textStyles.labelSmall?.copyWith(
                      color: market.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            )
          else
            AppNetworkImage(url: product.imageUrl, radius: AppRadius.input),
          PositionedDirectional(
            top: AppSizes.cardBadgeInset,
            start: AppSizes.cardBadgeInset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (discount != null && discount > 0)
                  DiscountBadge(percentage: discount),
                if (!product.isAvailable)
                  Padding(
                    padding: EdgeInsets.only(
                      top: discount != null && discount > 0 ? AppSpacing.xs : 0,
                    ),
                    child: StockBadge(
                      label: l10n.outOfStock,
                      icon: SabaIcons.close,
                      background: market.surfaceMuted,
                      foreground: market.outOfStock,
                      border: market.borderStrong,
                    ),
                  )
                else if (showLowStock &&
                    product.stockStatus == StockStatus.lowStock)
                  Padding(
                    padding: EdgeInsets.only(
                      top: discount != null && discount > 0 ? AppSpacing.xs : 0,
                    ),
                    child: StockBadge(
                      label: l10n.lowStock,
                      icon: SabaIcons.exclamation,
                      background: market.warningSoft,
                      foreground: market.lowStock,
                    ),
                  ),
              ],
            ),
          ),
          if (onWishlistToggle != null)
            PositionedDirectional(
              top: AppSpacing.sm,
              end: AppSpacing.sm,
              child: _WishlistButton(
                isActive: product.isWishlisted,
                onPressed: onWishlistToggle!,
              ),
            ),
        ],
      ),
    );
  }
}

/// The price block inside a card: the struck-through original above, the price
/// below with its currency mark set smaller.
class CardPrice extends StatelessWidget {
  const CardPrice({
    super.key,
    required this.amount,
    required this.currencyCode,
    this.originalAmount,
    this.muted = false,
    this.size = 16,
    this.alignEnd = false,
    this.inline = false,
  });

  final num amount;
  final String currencyCode;
  final num? originalAmount;

  /// Out of stock: the price is still shown, just held back.
  final bool muted;

  /// The price's size; the currency mark is set at three quarters of it.
  final double size;

  /// Lines both figures up on the trailing side, for a price set beside the
  /// name rather than under it.
  final bool alignEnd;

  /// The struck-through original after the price, on the same line.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final locale = context.l10n.locale.toLanguageTag();
    final hasDiscount = originalAmount != null && originalAmount! > amount;
    final (number, mark) = Formatters.moneyParts(
      amount,
      locale: locale,
      currencyCode: currencyCode,
    );

    final struck = !hasDiscount
        ? null
        : Text(
            Formatters.money(
              originalAmount!,
              locale: locale,
              currencyCode: currencyCode,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.labelSmall?.copyWith(
              color: market.textMuted,
              fontSize: 11,
              decoration: TextDecoration.lineThrough,
              decorationColor: market.textMuted,
            ),
          );
    final price = Text.rich(
      TextSpan(
        text: number,
        children: [
          TextSpan(
            text: ' $mark',
            style: TextStyle(
              fontSize: size * 0.75,
              fontWeight: FontWeight.w600,
              color: muted ? market.outOfStock : market.price,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.theme.extension<MarketplaceTextStyles>()?.price.copyWith(
        fontSize: size,
        height: 1.1,
        color: muted ? market.outOfStock : market.price,
      ),
    );

    if (inline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          price,
          if (struck != null) ...[
            const SizedBox(width: AppSpacing.xs + 2),
            struck,
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [?struck, price],
    );
  }
}

class _WishlistButton extends StatelessWidget {
  const _WishlistButton({
    required this.isActive,
    required this.onPressed,
    this.ringed = false,
  });

  final bool isActive;
  final VoidCallback onPressed;

  /// The flash-sale card's heart: a circle ringed in amber, the height of
  /// the button beside it, rather than a small white one on the photo.
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    final label = isActive
        ? context.l10n.removeFromWishlist
        : context.l10n.addToWishlist;

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onPressed,
          radius: AppSizes.minTapTarget / 2,
          child: SizedBox(
            width: AppSizes.minTapTarget,
            height: AppSizes.minTapTarget,
            child: Center(
              child: Container(
                width: ringed ? AppSizes.cornerAction : AppSizes.cardFavourite,
                height: ringed ? AppSizes.cornerAction : AppSizes.cardFavourite,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  shape: BoxShape.circle,
                  border: ringed
                      ? Border.all(color: context.market.heat, width: 1.5)
                      : null,
                ),
                child: SabaIcon(
                  isActive ? SabaIcons.heartFilled : SabaIcons.heart,
                  size: ringed ? AppSizes.iconMd : AppSizes.iconSm,
                  color: isActive
                      ? context.market.accent
                      : context.colors.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
