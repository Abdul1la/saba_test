import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../reviews/presentation/widgets/report_dialog.dart';
import '../../../../core/location/store_delivery.dart';
import '../../../../core/widgets/saba_logo.dart';
import '../../../../core/location/governorate_picker.dart';
import '../../../../core/location/governorate.dart';

import '../../../messaging/presentation/widgets/message_store_button.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/option_selector.dart';
import '../../../../core/widgets/quantity_selector.dart';
import '../../../../core/widgets/search_pill.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/sticky_bar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/price_text.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../addresses/presentation/address_providers.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../cart/presentation/cart_providers.dart';
import '../../../merchant/presentation/widgets/store_preview_bar.dart';
import '../../../wishlist/presentation/wishlist_providers.dart';
import '../../domain/entities.dart';
import '../catalog_providers.dart';
import '../../../home/presentation/widgets/home_sections.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  /// Option name to chosen value, for example `{'Color': 'Black'}`.
  final Map<String, String> _selection = <String, String>{};

  int _quantity = 1;
  bool _isAddingToCart = false;

  /// The variant matching the full selection, or null while it is incomplete.
  ProductVariant? _resolvedVariant(Product product) {
    if (!product.hasVariants) return null;
    if (_selection.length != product.variantOptions.length) return null;
    return product.variantFor(_selection);
  }

  bool _isSelectionComplete(Product product) =>
      !product.hasVariants ||
      _selection.length == product.variantOptions.length;

  Future<void> _addToCart(Product product, {bool buyNow = false}) async {
    if (!ref.read(isAuthenticatedProvider)) {
      context.push(AppRoutes.login);
      return;
    }

    // A product with options cannot be added until they are all chosen; the
    // server would reject an ambiguous line anyway.
    if (!_isSelectionComplete(product)) {
      AppSnackBar.info(context, context.l10n.selectVariantFirst);
      return;
    }

    if (buyNow) {
      // This product alone. It used to go into the cart first and check out
      // the whole cart, so everything else in it was bought too, and the
      // product stayed in the cart afterwards.
      context.push(
        AppRoutes.buyNowPath(
          productId: product.id,
          variantId: _resolvedVariant(product)?.id,
          quantity: _quantity,
        ),
      );
      return;
    }

    setState(() => _isAddingToCart = true);

    final result = await ref
        .read(cartControllerProvider.notifier)
        .addItem(
          productId: product.id,
          variantId: _resolvedVariant(product)?.id,
          quantity: _quantity,
        );

    if (!mounted) return;
    setState(() => _isAddingToCart = false);

    result.fold(
      ok: (_) {
        // Adding is not the end of the errand, so the way on travels with
        // the confirmation instead of being left to a hunt for the tab.
        AppSnackBar.success(
          context,
          context.l10n.addedToCart,
          actionLabel: context.l10n.cart,
          // `go`, not `push`. The cart is a branch of the shell, and pushing
          // a shell branch imperatively leaves go_router with a stack it
          // cannot draw — the screen came up blank. Switching to the tab is
          // what the control means anyway.
          onAction: () => context.go(AppRoutes.cart),
        );
      },
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(productProvider(widget.productId));
    // Their own product: a preview of what a buyer sees, with nothing to
    // buy it with. A merchant could put their own phone in a cart, and it
    // worked.
    final isMine = ref.watch(isMyStoreProvider(product.value?.merchant?.id));

    // No such product, or not for sale: said so, with a way back. It drew a
    // blank page priced "0.00 $" with an Add to cart button - the only
    // dollar sign in the app.
    if (product.error is NotFoundFailure) {
      final l10n = context.l10n;
      return Scaffold(
        appBar: SabaAppBar(title: l10n.productNotFound),
        body: EmptyStateView(
          icon: SabaIcons.search,
          title: l10n.productNotFound,
          message: l10n.productNotFoundMessage,
          actionLabel: l10n.navHome,
          onAction: () => context.go(AppRoutes.home),
        ),
      );
    }

    return Scaffold(
      appBar: isMine
          ? PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: StorePreviewBar(
                notListed: !(product.value?.isListed ?? true),
              ),
            )
          : null,
      body: AsyncStateView<Product>(
        value: product,
        onRetry: () => ref.invalidate(productProvider(widget.productId)),
        loadingBuilder: (_) => const _ProductDetailSkeleton(),
        builder: (value) => _buildContent(value, isMine: isMine),
      ),
      bottomNavigationBar: isMine
          ? null
          : product.maybeWhen(
              data: (value) => _BuyBar(
                product: value,
                noDeliveryTo: _noDeliveryTo(value),
                variant: _resolvedVariant(value),
                quantity: _quantity,
                isLoading: _isAddingToCart,
                onAddToCart: () => _addToCart(value),
                onBuyNow: () => _addToCart(value, buyNow: true),
              ),
              orElse: () => null,
            ),
    );
  }

  /// The shopper's city, named, when [product]'s store does not deliver
  /// there; null when it does, or either city is not known.
  String? _noDeliveryTo(Product product) {
    final city = ref.watch(deliveryCityProvider);
    final delivery = product.merchant?.delivery;
    if (city == null || delivery == null) return null;
    return delivery.to(city, storeCity: product.merchant?.governorate) == null
        ? city.label(context)
        : null;
  }

  /// The variant option drawn as colour swatches beside the image, if any.
  ///
  /// The catalogue stores options as plain strings, so an option only becomes
  /// swatches when it is named colour *and* every one of its values is a
  /// colour we can draw. Anything else stays a row of boxes, which is the
  /// same component and reads correctly either way.
  MapEntry<String, List<String>>? _colourOption(Product product) {
    for (final entry in product.variantOptions.entries) {
      if (isColourOption(
        entry.key,
        entry.value,
        colours: product.optionColours,
      )) {
        return entry;
      }
    }
    return null;
  }

  /// Whether a value can be bought at all, given the rest of the selection.
  ///
  /// An unavailable value stays visible and struck through rather than
  /// disappearing, because a row that changes length makes the customer think
  /// the product changed.
  bool _isValueAvailable(Product product, String option, String value) {
    if (!product.hasVariants) return true;
    final probe = Map<String, String>.from(_selection)..[option] = value;
    return product.variants.any((variant) {
      final matches = probe.entries.every(
        (entry) => variant.options[entry.key] == entry.value,
      );
      return matches && variant.stockStatus.isPurchasable;
    });
  }

  List<OptionValue> _valuesFor(Product product, String option) => [
    for (final value in product.variantOptions[option]!)
      OptionValue(
        value: value,
        isAvailable: _isValueAvailable(product, option, value),
      ),
  ];

  Widget _buildContent(Product product, {required bool isMine}) {
    final l10n = context.l10n;
    final variant = _resolvedVariant(product);
    final wishlistIds = ref.watch(wishlistIdsProvider);
    final isWishlisted =
        wishlistIds.contains(product.id) || product.isWishlisted;
    // The city the parcel would go to, not the one they browse from.
    final shopperCity = ref.watch(deliveryCityProvider);

    // A chosen variant overrides the product-level price and stock.
    // A chosen option's discount is its own, or none: it fell back to the
    // product's, and a 129,000 option with no original price wore the base
    // price's "−20%".
    final price = variant?.price ?? product.price;
    final originalPrice = variant == null
        ? product.originalPrice
        : variant.originalPrice;
    final discount = variant == null
        ? product.discountPercentage
        : variant.discountPercentage;
    final stockStatus = variant?.stockStatus ?? product.stockStatus;
    final available = variant?.availableQuantity ?? product.availableQuantity;
    // Never more chosen than there is: the stock can drop under a number
    // picked earlier, when the product is fetched again or the option
    // changes.
    if (available != null && available > 0 && _quantity > available) {
      _quantity = available;
    }

    final merchant = product.merchant;
    // What the store asks to bring it to the shopper's city; null when it
    // does not go there, or the city is not known.
    final terms = switch ((merchant?.delivery, shopperCity)) {
      (final delivery?, final city?) => delivery.to(
        city,
        storeCity: merchant?.governorate,
      ),
      _ => null,
    };

    const gap = SizedBox(height: AppSpacing.md);
    final hasOptions = product.variantOptions.isNotEmpty;

    return CustomScrollView(
      slivers: [
        // 1 - the pictures, square, edge to edge.
        SliverToBoxAdapter(
          child: _Gallery(
            media: product.media,
            name: product.name,
            isWishlisted: isWishlisted,
            onWishlistToggle: isMine
                ? null
                : () => _toggleWishlist(product, isWishlisted),
            onReport: isMine
                ? null
                : () => reportToSaba(
                    context,
                    ref,
                    target: ReportTarget.product,
                    id: product.id,
                  ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            0,
          ),
          sliver: SliverList.list(
            children: [
              // 2 - what it is, and what it costs.
              _Block(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: AppTypography.nameTitle(context)),
                    if (product.brand != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.brand!.name,
                        style: context.textStyles.bodySmall,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    _PriceLine(
                      amount: price,
                      originalAmount: originalPrice,
                      discount: discount,
                      currencyCode: product.currencyCode,
                    ),
                  ],
                ),
              ),
              // 3 - the facts, as pills; only the ones that are true.
              gap,
              _Block(
                child: _FactPills(
                  // "Only a few left" is a nudge for a buyer; told to the
                  // owner about their own shelf it is just noise.
                  stock: isMine ? null : stockStatus,
                  category: product.categoryName,
                  city: merchant?.governorate,
                  deliveryFee: terms?.$1,
                  // Said at the top, not only in the delivery block below
                  // the fold (the tester).
                  noDeliveryTo: isMine ? null : _noDeliveryTo(product),
                  warranty: product.warranty,
                ),
              ),
              // 4 - the choices, each under its own name.
              if (hasOptions || !isMine) ...[
                gap,
                _Block(
                  child: _Options(
                    product: product,
                    selection: _selection,
                    valuesFor: (option) => _valuesFor(product, option),
                    isColour: (option) => option == _colourOption(product)?.key,
                    onSelected: (option, value) =>
                        setState(() => _selection[option] = value),
                    onSizeGuide: product.sizeGuide == null
                        ? null
                        : () => _showSizeGuide(product.sizeGuide!),
                    showHint: !isMine && !_isSelectionComplete(product),
                    quantity: isMine
                        ? null
                        : QuantitySelector(
                            quantity: _quantity,
                            maxQuantity: available,
                            onChanged: (value) =>
                                setState(() => _quantity = value),
                          ),
                  ),
                ),
              ],
              // 5 - what it is, in the store's words.
              if (product.description != null &&
                  product.description!.isNotEmpty) ...[
                gap,
                _Block(child: _Description(text: product.description!)),
              ],
              // 6 - whether it can come, and what if it is not right.
              if (merchant != null) ...[
                gap,
                _Block(
                  child: _DeliveryBlock(
                    delivery: merchant.delivery,
                    storeCity: merchant.governorate,
                    shopperCity: shopperCity,
                  ),
                ),
              ],
              // 7 - who sells it.
              if (merchant != null) ...[
                gap,
                _Block(
                  child: _SellerBlock(
                    merchant: merchant,
                    productName: product.name,
                    isMine: isMine,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),

        // 8 - one rail, not three. The same shop sold the same eight
        // products under "frequently bought together", "related" and
        // "similar".
        SliverToBoxAdapter(
          child: _RelatedRail(
            title: l10n.relatedProducts,
            provider: relatedProductsProvider(product.id),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: AppSpacing.sectionGap),
        ),
      ],
    );
  }

  void _showSizeGuide(String guide) {
    AppDialogs.bottomSheet<void>(
      context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sm,
            AppSpacing.screenGutter,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sheetContext.l10n.sizeGuide,
                style: AppTypography.subsectionTitle(sheetContext),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(guide, style: sheetContext.textStyles.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleWishlist(Product product, bool isWishlisted) async {
    if (!ref.read(isAuthenticatedProvider)) {
      context.push(AppRoutes.login);
      return;
    }

    final summary = ProductSummary(
      id: product.id,
      name: product.name,
      price: product.price,
      currencyCode: product.currencyCode,
      stockStatus: product.stockStatus,
      imageUrl: product.imageUrls.isEmpty ? null : product.imageUrls.first,
      originalPrice: product.originalPrice,
      discountPercentage: product.discountPercentage,
      merchantId: product.merchant?.id,
      merchantName: product.merchant?.storeName,
      merchantCity: product.merchant?.governorate,
      brandName: product.brand?.name,
      isWishlisted: isWishlisted,
      hasOptions: product.hasVariants,
    );

    final result = await ref
        .read(wishlistControllerProvider.notifier)
        .toggle(summary);

    if (!mounted) return;
    result.fold(
      ok: (_) => AppSnackBar.success(
        context,
        isWishlisted
            ? context.l10n.removeFromWishlist
            : context.l10n.addedToWishlist,
      ),
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }
}

/// One block of the page: a card with room inside and a soft shadow.
class _Block extends StatelessWidget {
  const _Block({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg + 2),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppElevation.card,
      ),
      child: child,
    );
  }
}

/// The pictures: square, the full width, filling it; dots under them, and
/// back and favourite over them in white circles, which read on any
/// photograph. The page begins with the product rather than a bar above it.
class _Gallery extends StatefulWidget {
  const _Gallery({
    required this.media,
    required this.name,
    required this.isWishlisted,
    required this.onWishlistToggle,
    required this.onReport,
  });

  final List<ProductMedia> media;
  final String name;
  final bool isWishlisted;

  /// Null for the owner previewing their own product.
  final VoidCallback? onWishlistToggle;

  /// Reports the product to Saba (Apple 1.2); null for its owner.
  final VoidCallback? onReport;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final placeholder = iconForName(widget.name, widget.name.hashCode);
    final media = widget.media;

    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: market.surfaceMuted,
            child: media.isEmpty
                ? Center(
                    child: SabaIcon(
                      placeholder,
                      size: 96,
                      color: market.borderStrong,
                    ),
                  )
                : PageView.builder(
                    controller: _controller,
                    itemCount: media.length,
                    onPageChanged: (index) => setState(() => _index = index),
                    itemBuilder: (context, index) => AppNetworkImage(
                      url: media[index].url,
                      radius: 0,
                      fallbackIcon: placeholder,
                    ),
                  ),
          ),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
            start: AppSpacing.screenGutter,
            end: AppSpacing.screenGutter,
            child: Row(
              children: [
                CircleIconButton(
                  icon: context.isRtl
                      ? SabaIcons.chevronRight
                      : SabaIcons.chevronLeft,
                  tooltip: l10n.back,
                  onPressed: () => context.popOrGo(),
                ),
                const Spacer(),
                if (widget.onReport case final report?) ...[
                  CircleIconButton(
                    icon: SabaIcons.flag,
                    tooltip: l10n.reportProduct,
                    onPressed: report,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                if (widget.onWishlistToggle != null)
                  CircleIconButton(
                    icon: widget.isWishlisted
                        ? SabaIcons.heartFilled
                        : SabaIcons.heart,
                    tooltip: widget.isWishlisted
                        ? l10n.removeFromWishlist
                        : l10n.addToWishlist,
                    onPressed: widget.onWishlistToggle,
                  ),
                // No share button until Saba has a domain, a public product
                // page and the deep link files: it copied a link to a domain
                // this project never set up, which opens nothing (BUGS.md
                // 180, BACKEND_READY.md "Sharing a product").
              ],
            ),
          ),
          if (media.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.md,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < media.length; i++)
                        AnimatedContainer(
                          duration: AppMotion.chipExpand,
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          width: i == _index ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? context.colors.onSurface
                                : market.borderStrong,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The price, large, in navy; the original struck through beside it, and
/// the discount as a small amber pill.
class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.amount,
    required this.originalAmount,
    required this.discount,
    required this.currencyCode,
  });

  final num amount;
  final num? originalAmount;
  final num? discount;
  final String currencyCode;

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

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm + 2,
      runSpacing: AppSpacing.xs,
      children: [
        Text.rich(
          TextSpan(
            text: number,
            children: [
              TextSpan(text: ' $mark', style: const TextStyle(fontSize: 17)),
            ],
          ),
          style: context.theme
              .extension<MarketplaceTextStyles>()
              ?.price
              .copyWith(fontSize: 30, height: 1.1, letterSpacing: -0.9),
        ),
        if (hasDiscount)
          Text(
            Formatters.money(
              originalAmount!,
              locale: locale,
              currencyCode: currencyCode,
            ),
            style: context.textStyles.bodyMedium?.copyWith(
              fontSize: 14,
              color: market.originalPrice,
              decoration: TextDecoration.lineThrough,
              decorationColor: market.originalPrice,
            ),
          ),
        if (discount != null && discount! > 0)
          DiscountBadge(percentage: discount!, pill: true),
      ],
    );
  }
}

/// The facts a buyer checks first, as pills: stock, category, the store's
/// city, delivery, warranty. Only the ones that are known - never an empty
/// pill.
class _FactPills extends StatelessWidget {
  const _FactPills({
    required this.stock,
    required this.category,
    required this.city,
    required this.deliveryFee,
    required this.warranty,
    this.noDeliveryTo,
  });

  /// The shopper's city, when the store does not deliver there.
  final String? noDeliveryTo;

  final StockStatus? stock;
  final String? category;
  final Governorate? city;

  /// What it costs to bring it to the shopper's city; null when the store
  /// does not go there, or the city is not known.
  final num? deliveryFee;
  final String? warranty;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final neutral = (market.surfaceMuted, context.colors.onSurface);

    final pills = <(String, String, (Color, Color))>[
      if (noDeliveryTo case final city?)
        (
          SabaIcons.alertCircle,
          l10n.noDeliveryTo(city),
          (market.errorSoft, context.colors.error),
        ),
      ?switch (stock) {
        StockStatus.inStock => (
          SabaIcons.check,
          l10n.inStock,
          (market.successSoft, market.success),
        ),
        StockStatus.lowStock => (
          SabaIcons.exclamation,
          l10n.lowStock,
          (market.warningSoft, market.lowStock),
        ),
        StockStatus.outOfStock => (
          SabaIcons.close,
          l10n.outOfStock,
          (market.errorSoft, context.colors.error),
        ),
        _ => null,
      },
      if ((category ?? '').trim().isNotEmpty)
        (SabaIcons.grid, category!.trim(), neutral),
      if (city != null)
        (
          SabaIcons.mapPin,
          city!.label(context),
          (market.accentSoft, market.accent),
        ),
      if (deliveryFee case final fee?)
        fee <= 0
            ? (
                SabaIcons.truck,
                l10n.freeDelivery,
                (market.successSoft, market.success),
              )
            : (
                SabaIcons.truck,
                '${l10n.deliveryFee}: ${Formatters.money(fee, locale: l10n.locale.toLanguageTag(), currencyCode: 'IQD')}',
                neutral,
              ),
      if ((warranty ?? '').trim().isNotEmpty)
        (SabaIcons.shield, warranty!.trim(), neutral),
    ];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (icon, label, (fill, ink)) in pills)
          _FactPill(icon: icon, label: label, fill: fill, ink: ink),
      ],
    );
  }
}

class _FactPill extends StatelessWidget {
  const _FactPill({
    required this.icon,
    required this.label,
    required this.fill,
    required this.ink,
  });

  final String icon;
  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SabaIcon(icon, size: 14, color: ink),
          const SizedBox(width: AppSpacing.xs + 2),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.labelMedium?.copyWith(
                color: ink,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Each option under its own name - colour, storage - then how many, and
/// what to do before adding it.
class _Options extends StatelessWidget {
  const _Options({
    required this.product,
    required this.selection,
    required this.valuesFor,
    required this.isColour,
    required this.onSelected,
    required this.onSizeGuide,
    required this.showHint,
    required this.quantity,
  });

  final Product product;
  final Map<String, String> selection;
  final List<OptionValue> Function(String option) valuesFor;
  final bool Function(String option) isColour;
  final void Function(String option, String value) onSelected;
  final VoidCallback? onSizeGuide;
  final bool showHint;

  /// Null for the owner, who buys nothing here.
  final Widget? quantity;

  static bool _isSizeOption(String name) {
    final lower = name.toLowerCase();
    return lower.contains('size') || lower.contains('مقاس');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labelStyle = context.textStyles.titleMedium?.copyWith(fontSize: 15);
    final options = product.variantOptions.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, name) in options.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: name,
                    children: [
                      if (selection[name] case final chosen?)
                        TextSpan(
                          text: '  $chosen',
                          style: context.textStyles.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  style: labelStyle,
                ),
              ),
              // Only shown when the seller actually supplied one.
              if (_isSizeOption(name) && onSizeGuide != null)
                _UnderlinedLink(label: l10n.sizeGuide, onTap: onSizeGuide!),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (isColour(name))
            ColourSwatchColumn(
              inRow: true,
              values: valuesFor(name),
              colours: product.optionColours,
              selected: selection[name],
              onSelected: (value) => onSelected(name, value),
            )
          else
            OptionSelector(
              values: valuesFor(name),
              selected: selection[name],
              onSelected: (value) => onSelected(name, value),
            ),
        ],
        if (showHint) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              SabaIcon(
                SabaIcons.info,
                size: AppSizes.iconSm,
                color: context.colors.primary,
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Expanded(
                child: Text(
                  l10n.selectVariantFirst,
                  style: context.textStyles.bodySmall?.copyWith(
                    color: context.colors.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (quantity != null) ...[
          if (options.isNotEmpty) const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: Text(l10n.quantity, style: labelStyle)),
              quantity!,
            ],
          ),
        ],
      ],
    );
  }
}

/// A quiet secondary action: a label with a rule under it, not a button.
class _UnderlinedLink extends StatelessWidget {
  const _UnderlinedLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A link, so purple.
    final colour = context.colors.primary;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colour, width: 1.5)),
        ),
        child: Text(
          label,
          style: context.textStyles.labelLarge?.copyWith(
            fontSize: 12.5,
            color: colour,
          ),
        ),
      ),
    );
  }
}

/// The description, clamped to four lines, with "Read more" only when there
/// is more to read.
class _Description extends StatefulWidget {
  const _Description({required this.text});

  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _expanded = false;

  static const int _lines = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = context.textStyles.bodyMedium?.copyWith(height: 1.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.description, style: AppTypography.subsectionTitle(context)),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: widget.text, style: style),
              maxLines: _lines,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: constraints.maxWidth);
            final isLong = painter.didExceedMaxLines;
            painter.dispose();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSize(
                  duration: AppMotion.chipExpand,
                  alignment: Alignment.topCenter,
                  child: Text(
                    widget.text,
                    maxLines: _expanded ? null : _lines,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                if (isLong) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _UnderlinedLink(
                    label: _expanded ? l10n.readLess : l10n.readMore,
                    onTap: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Whether the store brings it to the shopper's city - said in green when it
/// does, plainly when it does not - and Saba's return rule.
class _DeliveryBlock extends StatelessWidget {
  const _DeliveryBlock({
    required this.delivery,
    required this.storeCity,
    required this.shopperCity,
  });

  final StoreDelivery? delivery;
  final Governorate? storeCity;
  final Governorate? shopperCity;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final delivery = this.delivery;
    final shopperCity = this.shopperCity;

    Widget line(String icon, String text, Color ink, Color fill) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.action),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SabaIcon(icon, size: AppSizes.iconSm, color: ink),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: context.textStyles.labelLarge?.copyWith(
                color: ink,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );

    Widget? reach;
    if (delivery != null && shopperCity != null) {
      final city = shopperCity.label(context);
      reach = switch (delivery.to(shopperCity, storeCity: storeCity)) {
        null => line(
          SabaIcons.alertCircle,
          l10n.noDeliveryTo(city),
          context.colors.error,
          market.errorSoft,
        ),
        (final fee, final time) => line(
          SabaIcons.truck,
          [
            l10n.deliversTo(city),
            if (fee <= 0)
              l10n.freeDelivery
            else
              Formatters.money(
                fee,
                locale: l10n.locale.toLanguageTag(),
                currencyCode: 'IQD',
              ),
            time.label(context),
          ].join(' · '),
          market.success,
          market.successSoft,
        ),
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.delivery, style: AppTypography.subsectionTitle(context)),
        const SizedBox(height: AppSpacing.sm + 2),
        if (reach != null) ...[reach, const SizedBox(height: AppSpacing.md)],
        // Saba's rule, the same at every store: not a store's own words.
        Row(
          children: [
            SabaIcon(
              SabaIcons.refresh,
              size: AppSizes.iconSm,
              color: context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${l10n.returnPolicy}: ${l10n.returnRuleShort}',
                style: context.textStyles.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Who sells it: logo, name, rating, city - and a way to ask them, on its
/// own line so a small phone at a large text size never squeezes the name
/// out (BUGS.md 137).
class _SellerBlock extends StatelessWidget {
  const _SellerBlock({
    required this.merchant,
    required this.productName,
    required this.isMine,
  });

  final ProductMerchant merchant;
  final String productName;

  /// The owner reading their own product: nobody to message.
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final city = merchant.governorate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => context.push(AppRoutes.storefrontPath(merchant.id)),
          borderRadius: BorderRadius.circular(AppRadius.action),
          child: Row(
            children: [
              AppNetworkImage(
                url: merchant.logoUrl,
                width: 52,
                height: 52,
                radius: AppRadius.action,
                fallback: const SabaMark(size: 52),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.soldBy, style: context.textStyles.bodySmall),
                    Text(
                      merchant.storeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (merchant.rating case final rating?)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SabaIcon(
                                SabaIcons.starFilled,
                                size: 12,
                                color: context.market.star,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                rating.toStringAsFixed(1),
                                style: context.textStyles.labelMedium,
                              ),
                            ],
                          ),
                        if (city != null) CityLabel(city, size: 12),
                      ],
                    ),
                  ],
                ),
              ),
              SabaIcon(
                context.isRtl ? SabaIcons.chevronLeft : SabaIcons.chevronRight,
                size: AppSizes.iconSm,
                color: context.colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
        // A question about this goes to the one who sells it.
        if (!isMine) ...[
          const SizedBox(height: AppSpacing.md),
          MessageStoreButton(
            merchantId: merchant.id,
            about: l10n.aboutTopic(productName),
          ),
        ],
      ],
    );
  }
}

/// A row that opens another screen: a title, one plain sentence, a chevron.
class _RelatedRail extends ConsumerWidget {
  const _RelatedRail({required this.title, required this.provider});

  final String title;
  final FutureProvider<List<ProductSummary>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(provider);

    return products.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: title),
            ProductRail(products: items),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// The sticky buy bar: what it costs, then the two ways to act on it.
class _BuyBar extends StatelessWidget {
  const _BuyBar({
    required this.product,
    required this.quantity,
    required this.isLoading,
    required this.onAddToCart,
    required this.onBuyNow,
    this.variant,
    this.noDeliveryTo,
  });

  /// The shopper's city, when the store does not deliver there: nothing
  /// can be bought, and the bar says why.
  final String? noDeliveryTo;

  final Product product;
  final ProductVariant? variant;
  final int quantity;
  final bool isLoading;
  final VoidCallback onAddToCart;
  final VoidCallback onBuyNow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = variant?.stockStatus ?? product.stockStatus;
    final isOpen = product.merchant?.isOpen ?? true;
    final canBuy = status.isPurchasable && isOpen && noDeliveryTo == null;
    final unit = variant?.price ?? product.price;

    final total = Formatters.money(
      unit * quantity,
      locale: l10n.locale.toLanguageTag(),
      currencyCode: product.currencyCode,
    );

    // The total on its own line, the two buttons under it at half the width
    // each. In one row the total took its share first and the buttons split
    // what was left, so "Add to cart" arrived as "Add ..." with the two
    // buttons touching. A button that cannot say what it does is not a
    // button.
    return StickyBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isOpen || noDeliveryTo != null)
            Text(
              !isOpen
                  ? l10n.storeClosedBuyNote
                  : l10n.noDeliveryTo(noDeliveryTo!),
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            )
          else
            Row(
              children: [
                Text(
                  l10n.total,
                  style: context.textStyles.labelSmall?.copyWith(fontSize: 12),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    total,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: context.theme
                        .extension<MarketplaceTextStyles>()
                        ?.price
                        .copyWith(fontSize: 18, height: 1.1),
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.addToCart,
                  icon: SabaIcons.bag,
                  variant: AppButtonVariant.secondary,
                  onPressed: canBuy && !isLoading ? onAddToCart : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: AppButton(
                  label: l10n.buyNow,
                  onPressed: canBuy && !isLoading ? onBuyNow : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductDetailSkeleton extends StatelessWidget {
  const _ProductDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 300, radius: 0),
          Padding(
            padding: EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120, height: 14),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(height: 22),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 180, height: 16),
                SizedBox(height: AppSpacing.lg),
                SkeletonBox(width: 140, height: 28),
                SizedBox(height: AppSpacing.xl),
                SkeletonBox(height: 14),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(height: 14),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 220, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The first few reviews, on the product page.
///
/// Two of them: enough to judge the tone, not enough to bury the rest of the
/// page. "See all" still goes to the full list, with its sorting and its star
/// filter, for anyone who wants to dig.
