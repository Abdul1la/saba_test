import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/quantity_selector.dart';
import '../../../../core/widgets/saba_nav_bar.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/state_views.dart';
import '../../domain/entities.dart';
import '../cart_providers.dart';
import '../widgets/coupon_offers.dart';
import '../../../../core/utils/western_digits_formatter.dart';
import '../../../../core/widgets/saba_logo.dart';
import '../../../../core/location/governorate_picker.dart';
import '../../../../core/location/governorate.dart';

/// The multi-merchant cart.
///
/// Items are grouped by store, and every figure shown — line totals, shipping,
/// tax and the grand total — is read from the server (section 12).
///
/// The grouping is the whole point of the screen, so the design gives each
/// store its own card with its own header and its own subtotal: a customer
/// buying from two sellers is making two shipments, and the cart says so
/// before checkout does.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final cart = ref.watch(cartControllerProvider);
    final controller = ref.read(cartControllerProvider.notifier);

    return Scaffold(
      body: AsyncStateView<Cart>(
        value: cart,
        onRetry: () => ref.invalidate(cartControllerProvider),
        loadingBuilder: (_) => const ListSkeleton(itemHeight: 92),
        builder: (value) {
          // Everything saved for later, nothing to buy now: the saved items
          // with "Move to cart", not "Your cart is empty" hiding them - the
          // item looked lost (the tester).
          if (value.isEmpty && value.savedForLater.isNotEmpty) {
            return ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                PageTitle(title: l10n.myCart, subtitle: l10n.emptyCart),
                const SizedBox(height: AppSpacing.xl - 2),
                _SavedForLaterSection(items: value.savedForLater),
              ],
            );
          }
          if (value.isEmpty) {
            return SafeArea(
              child: EmptyStateView(
                title: l10n.emptyCart,
                message: l10n.emptyCartMessage,
                icon: SabaIcons.bag,
                actionLabel: l10n.startShopping,
                onAction: () => context.go(AppRoutes.home),
              ),
            );
          }

          // Counted lines, while the nav badge counts units - so "3 items"
          // sat under a badge reading "7", two numbers for one word on screen
          // at once. Cart.itemCount is the getter the badge already reads.
          final itemCount = value.itemCount;

          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(
              // The checkout bar is below the list, not over it; the 180
              // left here was an empty gap above the button (BUGS.md 16).
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                PageTitle(
                  title: l10n.myCart,
                  subtitle: l10n.cartSummary(itemCount, value.groups.length),
                ),
                const SizedBox(height: AppSpacing.xl - 2),
                for (final group in value.groups) ...[
                  _MerchantGroupCard(group: group),
                  const SizedBox(height: AppSpacing.md + 2),
                ],
                _CouponRow(cart: value),
                const SizedBox(height: AppSpacing.md + 2),
                _TotalsCard(totals: value.totals),
                if (value.savedForLater.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _SavedForLaterSection(items: value.savedForLater),
                ],
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: cart.maybeWhen(
        data: (value) => value.isEmpty ? null : _CheckoutBar(cart: value),
        orElse: () => null,
      ),
    );
  }
}

/// One store's items, its header and its own subtotal.
class _MerchantGroupCard extends ConsumerWidget {
  const _MerchantGroupCard({required this.group});

  final CartMerchantGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final market = context.market;
    final locale = l10n.locale.toLanguageTag();

    String money(num amount) => Formatters.money(
      amount,
      locale: locale,
      currencyCode: group.currencyCode,
    );

    final isFreeShipping = group.shippingFee == 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: market.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          // ------------------------------------------------ store header --
          InkWell(
            onTap: () =>
                context.push(AppRoutes.storefrontPath(group.merchantId)),
            child: Container(
              color: market.surfaceMuted,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md + 2,
                AppSpacing.md + 1,
                AppSpacing.md + 2,
                AppSpacing.md + 1,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md - 2),
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: ColoredBox(
                        color: context.colors.surface,
                        child: AppNetworkImage(
                          url: group.logoUrl,
                          radius: AppRadius.md - 2,
                          fallback: const SabaMark(size: 34),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Text(
                      group.merchantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleLarge?.copyWith(
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  SabaIcon(
                    context.isRtl
                        ? SabaIcons.chevronLeft
                        : SabaIcons.chevronRight,
                    size: AppSizes.iconSm,
                    color: context.colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          if (!group.deliversHere) _CannotDeliverBanner(group: group),

          for (final item in group.items)
            _CartItemRow(item: item, city: group.governorate),

          // ----------------------------------------------- store subtotal --
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: market.surfaceMuted.withValues(alpha: 0.4),
              border: Border(top: BorderSide(color: market.surfaceMuted)),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md + 2,
              AppSpacing.sm + 3,
              AppSpacing.md + 2,
              AppSpacing.sm + 3,
            ),
            child: Column(
              children: [
                _GroupLine(
                  label: l10n.storeSubtotal,
                  value: money(group.subtotal),
                ),
                if (group.shippingFee != null) ...[
                  const SizedBox(height: AppSpacing.xs + 1),
                  _GroupLine(
                    label: group.shippingMethodName ?? l10n.shipping,
                    value: isFreeShipping
                        ? l10n.freeShipping
                        : money(group.shippingFee!),
                    // Free shipping is good news, so it is allowed the one
                    // colour on the card.
                    colour: isFreeShipping ? market.success : null,
                  ),
                ],
                if (group.deliversHere && group.estimatedDelivery != null) ...[
                  const SizedBox(height: AppSpacing.xs + 1),
                  Row(
                    children: [
                      SabaIcon(
                        SabaIcons.truck,
                        size: 13,
                        color: context.colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs + 1),
                      Expanded(
                        child: Text(
                          group.estimatedDelivery!,
                          style: context.textStyles.bodySmall?.copyWith(
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A store that will not bring this order, said where it cannot be missed:
/// at the top of its card, with the two ways out. It was one line of small
/// print under the subtotal, and the shopper found out at checkout, at a
/// button that would not work (BUGS.md 14).
class _CannotDeliverBanner extends ConsumerWidget {
  const _CannotDeliverBanner({required this.group});

  final CartMerchantGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final market = context.market;
    final controller = ref.read(cartControllerProvider.notifier);

    Future<void> saveAll() async {
      for (final item in group.items) {
        final result = await controller.saveForLater(item.id);
        if (!context.mounted) return;
        if (result.isErr) {
          result.fold(
            ok: (_) {},
            err: (failure) => AppSnackBar.failure(context, failure),
          );
          return;
        }
      }
    }

    return Container(
      width: double.infinity,
      color: market.warningSoft,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md + 2,
        AppSpacing.md,
        AppSpacing.md + 2,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SabaIcon(
                SabaIcons.alertCircle,
                size: AppSizes.iconSm,
                color: market.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.notInTotal(group.estimatedDelivery ?? ''),
                  style: context.textStyles.titleSmall?.copyWith(
                    color: market.warning,
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: () async {
                  await context.push(AppRoutes.addresses);
                  await controller.refresh();
                },
                child: Text(l10n.changeAddress),
              ),
              TextButton(onPressed: saveAll, child: Text(l10n.saveForLater)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A label / value pair inside a store's subtotal strip.
class _GroupLine extends StatelessWidget {
  const _GroupLine({required this.label, required this.value, this.colour});

  final String label;
  final String value;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.bodyMedium?.copyWith(
              fontSize: 12.5,
              color: colour,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          value,
          style: context.textStyles.labelLarge?.copyWith(
            fontSize: 12.5,
            color: colour ?? context.colors.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// `row/product` — one line in the cart.
class _CartItemRow extends ConsumerWidget {
  const _CartItemRow({required this.item, this.city});

  final CartItem item;

  /// Its store's city, on every line.
  final Governorate? city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final market = context.market;
    final controller = ref.read(cartControllerProvider.notifier);
    final isBusy = ref.watch(busyCartItemsProvider).contains(item.id);
    final available = item.isAvailable;

    return Opacity(
      // Not hidden and not struck through: still a line the customer owns,
      // just one that will not be charged.
      opacity: available ? 1 : 0.9,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md + 2,
          AppSpacing.md,
          AppSpacing.md + 2,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () =>
                  context.push(AppRoutes.productDetailPath(item.productId)),
              borderRadius: BorderRadius.circular(AppRadius.md + 2),
              child: SizedBox(
                width: 64,
                height: 64,
                child: AppNetworkImage(
                  url: item.imageUrl,
                  radius: AppRadius.md + 2,
                  fallbackIcon: iconForName(item.name, item.id.hashCode),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.titleLarge?.copyWith(
                      fontSize: 13.5,
                      height: 1.3,
                      color: available ? null : context.colors.onSurfaceVariant,
                    ),
                  ),
                  if (item.variantLabel != null) ...[
                    const SizedBox(height: AppSpacing.xs + 1),
                    Text(
                      item.variantLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodySmall?.copyWith(
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                  if (city case final city?) ...[
                    const SizedBox(height: AppSpacing.xs),
                    CityLabel(city, size: 11.5),
                  ],
                  const SizedBox(height: AppSpacing.xs + 1),
                  if (available)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            Formatters.money(
                              item.lineTotal,
                              locale: l10n.locale.toLanguageTag(),
                              currencyCode: item.currencyCode,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.theme
                                .extension<MarketplaceTextStyles>()
                                ?.price
                                .copyWith(fontSize: 15, height: 1.2),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        QuantitySelector(
                          quantity: item.quantity,
                          maxQuantity: item.availableQuantity,
                          isBusy: isBusy,
                          onChanged: (quantity) async {
                            final result = await controller.updateQuantity(
                              itemId: item.id,
                              quantity: quantity,
                            );
                            if (!context.mounted) return;
                            result.fold(
                              ok: (_) {},
                              err: (failure) =>
                                  AppSnackBar.failure(context, failure),
                            );
                          },
                        ),
                      ],
                    )
                  else
                    Container(
                      height: AppSizes.cardBadgeHeight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: market.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SabaIcon(
                            SabaIcons.close,
                            size: 12,
                            color: market.outOfStock,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              l10n.outOfStockNotCharged(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.labelMedium?.copyWith(
                                fontSize: 11,
                                color: market.outOfStock,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm - 2),
                  // Two equal halves, so a long word or a larger text size
                  // shortens a label instead of pushing "Remove" off the card.
                  Row(
                    children: [
                      Expanded(
                        child: _RowAction(
                          icon: SabaIcons.bookmark,
                          label: l10n.saveForLater,
                          // The sibling actions on this row fold and report;
                          // this one discarded its Result, so a failure was
                          // indistinguishable from a button that does nothing.
                          onPressed: isBusy
                              ? null
                              : () async {
                                  final result = await controller.saveForLater(
                                    item.id,
                                  );
                                  if (!context.mounted) return;
                                  result.fold(
                                    ok: (_) {},
                                    err: (failure) =>
                                        AppSnackBar.failure(context, failure),
                                  );
                                },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _RowAction(
                          icon: SabaIcons.trash,
                          label: l10n.remove,
                          isDestructive: true,
                          onPressed: isBusy
                              ? null
                              : () => _remove(context, controller),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Removing a line asked "Remove item?" first — two taps and a dialog to
  /// undo one tap, on the one action in the cart that is trivially reversible
  /// and sits beside "Save for later" anyway. It goes at once now, and says
  /// so with a way back, which is both fewer taps and a better net: the
  /// dialog protected against a deliberate press, never against a misplaced
  /// one, because by the time it appeared you had already aimed at Remove.
  Future<void> _remove(BuildContext context, CartController controller) async {
    final result = await controller.removeItem(item.id);
    if (!context.mounted) return;

    result.fold(
      ok: (_) => AppSnackBar.success(
        context,
        context.l10n.itemRemoved,
        actionLabel: context.l10n.undo,
        onAction: () => controller.addItem(
          productId: item.productId,
          variantId: item.variantId,
          quantity: item.quantity,
        ),
      ),
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }
}

/// "Save for later" and "Remove": icon plus word, never an icon alone.
///
/// Soft-filled pills. They were 11.5-point coloured words with a 13-point
/// icon and no shape, and customers did not see that Remove was there at
/// all. Remove is red on a soft red fill; Save for later is quiet on grey.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  final String icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    // Removing is red; saving for later is a second-level action: purple
    // words and outline, never a fill that competes with checkout.
    final (ink, fill, edge) = isDestructive
        ? (context.colors.error, market.errorSoft, null)
        : (
            context.colors.primary,
            context.colors.surface,
            BorderSide(color: context.colors.primary, width: 1.5),
          );

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: ink,
        side: edge,
        disabledBackgroundColor: fill.withValues(alpha: 0.5),
        disabledForegroundColor: ink.withValues(alpha: 0.4),
        // Looks 38 tall, answers a full 48.
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        textStyle: context.textStyles.labelMedium?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      // Shrinks to fit rather than ending in "Save for la…".
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SabaIcon(icon, size: AppSizes.iconSm, color: ink),
            const SizedBox(width: AppSpacing.xs + 2),
            Text(label, maxLines: 1),
          ],
        ),
      ),
    );
  }
}

/// The coupon field, or the coupon once it is on.
class _CouponRow extends ConsumerStatefulWidget {
  const _CouponRow({required this.cart});

  final Cart cart;

  @override
  ConsumerState<_CouponRow> createState() => _CouponRowState();
}

class _CouponRowState extends ConsumerState<_CouponRow> {
  final _controller = TextEditingController();
  bool _isBusy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The typed code, or [offered] - one of the customer's coupons, tapped.
  Future<void> _apply([String? offered]) async {
    final code = (offered ?? _controller.text).trim();
    if (code.isEmpty) return;

    setState(() => _isBusy = true);
    final result = await ref
        .read(cartControllerProvider.notifier)
        .applyCoupon(code);
    if (!mounted) return;
    setState(() => _isBusy = false);

    result.fold(
      ok: (_) {
        _controller.clear();
        AppSnackBar.success(context, context.l10n.couponApplied);
      },
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  Future<void> _remove() async {
    setState(() => _isBusy = true);
    await ref.read(cartControllerProvider.notifier).removeCoupon();
    if (!mounted) return;
    setState(() => _isBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final coupon = widget.cart.coupon;
    final ink = coupon == null || coupon.applies
        ? market.success
        : market.lowStock;
    // A store's coupon is only offered with that store's things in the cart:
    // anything else would be a chip that answers "not valid" when tapped.
    final stores = {for (final group in widget.cart.groups) group.merchantId};
    final offers = coupon == null
        ? [
            for (final offer
                in ref.watch(availableCouponsProvider).value ??
                    const <CouponOffer>[])
              if (offer.merchantId == null || stores.contains(offer.merchantId))
                offer,
          ]
        : const <CouponOffer>[];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      child: coupon == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: AppSizes.buttonHeight,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg + 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: market.border),
                        ),
                        child: Row(
                          children: [
                            SabaIcon(
                              SabaIcons.ticket,
                              size: AppSizes.iconSm,
                              color: context.colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.sm + 2),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                inputFormatters: const [
                                  WesternDigitsFormatter(),
                                ],
                                textCapitalization:
                                    TextCapitalization.characters,
                                style: context.textStyles.bodyMedium?.copyWith(
                                  fontSize: 13.5,
                                ),
                                decoration: InputDecoration(
                                  hintText: l10n.couponCode,
                                  filled: false,
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                // The button was gated on _isBusy; the return
                                // key was not, so it posted the coupon twice.
                                onSubmitted: _isBusy ? null : (_) => _apply(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + 1),
                    // Second level: checkout is this screen's one main action.
                    OutlinedButton(
                      onPressed: _isBusy ? null : _apply,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, AppSizes.buttonHeight),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl - 2,
                        ),
                      ),
                      child: _isBusy
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.colors.primary,
                              ),
                            )
                          : Text(l10n.applyCoupon),
                    ),
                  ],
                ),
                // The field asked for a code and never said where one comes
                // from. The customer's own coupons wait right under it.
                if (offers.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  CouponOfferChips(
                    offers: offers,
                    onApply: _isBusy ? null : _apply,
                  ),
                ],
              ],
            )
          : Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md,
                  0,
                  AppSpacing.xs + 2,
                  0,
                ),
                decoration: BoxDecoration(
                  // Amber while it takes nothing off: green said "applied"
                  // on a cart under its minimum (the tester).
                  color: coupon.applies
                      ? market.successSoft
                      : market.warningSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SabaIcon(SabaIcons.ticket, size: 13, color: ink),
                    const SizedBox(width: AppSpacing.sm - 1),
                    // A store's coupon names the store, which can be long.
                    Flexible(
                      child: Text(
                        coupon.applies || coupon.minOrderAmount == null
                            ? coupon.description ?? coupon.code
                            : '${coupon.code} · ${l10n.onOrdersOver} '
                                  '${Formatters.money(coupon.minOrderAmount!, locale: l10n.locale.toLanguageTag(), currencyCode: widget.cart.totals.currencyCode)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.labelMedium?.copyWith(
                          fontSize: 12,
                          color: ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm - 1),
                    Semantics(
                      button: true,
                      label: l10n.remove,
                      child: InkResponse(
                        onTap: _isBusy ? null : _remove,
                        radius: AppSizes.minTapTarget / 2,
                        child: Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ink.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: SabaIcon(
                            SabaIcons.close,
                            size: 11,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Subtotal, discount, shipping and tax: what the total is made of.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final CartTotals totals;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final locale = l10n.locale.toLanguageTag();

    String money(num amount) => Formatters.money(
      amount,
      locale: locale,
      currencyCode: totals.currencyCode,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: market.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          _SummaryLine(label: l10n.subtotal, value: money(totals.subtotal)),
          // The store's own discounts and the coupon together. Only the
          // first was listed, so with a coupon on, the lines did not add up
          // to the total under them.
          if (totals.hasDiscount)
            _SummaryLine(
              label: l10n.discount,
              value: Formatters.deduction(
                totals.discount + totals.couponDiscount,
                locale: locale,
                currencyCode: totals.currencyCode,
              ),
              colour: market.success,
            ),
          _SummaryLine(label: l10n.shipping, value: money(totals.shipping)),
          if (totals.tax > 0)
            _SummaryLine(label: l10n.tax, value: money(totals.tax)),
          // The total itself is on the bar by the checkout button, the one
          // place it is always in view; it was here as well (BUGS.md 16).
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value, this.colour});

  final String label;
  final String value;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.textStyles.bodyMedium?.copyWith(fontSize: 13.5),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: context.textStyles.labelLarge?.copyWith(
              fontSize: 13.5,
              color: colour ?? context.colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedForLaterSection extends ConsumerWidget {
  const _SavedForLaterSection({required this.items});

  final List<CartItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(cartControllerProvider.notifier);
    // The cart rows above already lock per item while a request is in
    // flight; this section never read the same set.
    final busy = ref.watch(busyCartItemsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: context.l10n.savedForLater),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              0,
              AppSpacing.screenGutter,
              AppSpacing.sm,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: context.colors.surface,
                border: Border.all(color: context.market.border),
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: AppNetworkImage(
                      url: item.imageUrl,
                      radius: AppRadius.md,
                      fallbackIcon: iconForName(item.name, item.id.hashCode),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Saved-for-later rows never read the busy set, so this
                  // stayed live for the whole round trip — two taps, two
                  // requests — and swallowed its failure as well.
                  TextButton(
                    onPressed: busy.contains(item.id)
                        ? null
                        : () async {
                            final result = await controller.moveToCart(item.id);
                            if (!context.mounted) return;
                            result.fold(
                              ok: (_) {},
                              err: (failure) =>
                                  AppSnackBar.failure(context, failure),
                            );
                          },
                    child: Text(context.l10n.moveToCart),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The checkout button, floating clear of the navigation bar.
///
/// The design fades the page into it rather than sitting it on a white bar,
/// so the last card scrolls away under the gradient instead of being cut off
/// by an edge.
class _CheckoutBar extends ConsumerWidget {
  const _CheckoutBar({required this.cart});

  final Cart cart;

  /// Clears every line the shop can no longer sell.
  ///
  /// The bar used to state the problem and stop there, with the button dead
  /// beside it: the customer had to scroll the cart, find each struck line
  /// and remove it by hand before anything would move. One request per line —
  /// carts are small, and a bulk endpoint can replace this when one exists.
  Future<void> _removeUnavailable(
    BuildContext context,
    CartController controller,
  ) async {
    for (final item in cart.allItems.where((item) => !item.isAvailable)) {
      final result = await controller.removeItem(item.id);
      if (!context.mounted) return;
      final stop = result.fold(
        ok: (_) => false,
        err: (failure) {
          AppSnackBar.failure(context, failure);
          return true;
        },
      );
      if (stop) return;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final page = context.theme.scaffoldBackgroundColor;
    final blocked = cart.hasUnavailableItems;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md + 2,
        AppSpacing.screenGutter,
        // Clear of the floating bar, with air between the two.
        SabaNavBar.coveredHeight(context) + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [page, page, page.withValues(alpha: 0)],
          stops: const [0, 0.62, 1],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (blocked)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                l10n.errorInventory,
                textAlign: TextAlign.center,
                style: context.textStyles.labelSmall?.copyWith(
                  color: context.colors.error,
                ),
              ),
            )
          else
            // What you are about to pay, where you decide to pay it. The
            // figure lived in a card in the list, so a cart longer than a
            // screen let you press Checkout having never seen it.
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.grandTotal,
                      style: context.textStyles.bodyMedium?.copyWith(
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    Formatters.money(
                      cart.totals.total,
                      locale: l10n.locale.toLanguageTag(),
                      currencyCode: cart.totals.currencyCode,
                    ),
                    style: context.theme
                        .extension<MarketplaceTextStyles>()
                        ?.price
                        .copyWith(fontSize: 16, height: 1.1),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: blocked
                  ? () => _removeUnavailable(
                      context,
                      ref.read(cartControllerProvider.notifier),
                    )
                  : cart.canCheckout
                  ? () => context.push(AppRoutes.checkout)
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      blocked ? l10n.removeUnavailable : l10n.proceedToCheckout,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.labelLarge?.copyWith(
                        fontSize: 14,
                        color: context.colors.onPrimary,
                      ),
                    ),
                  ),
                  if (!blocked) ...[
                    const SizedBox(width: AppSpacing.sm + 1),
                    SabaIcon(
                      context.isRtl
                          ? SabaIcons.chevronLeft
                          : SabaIcons.chevronRight,
                      size: AppSizes.iconSm,
                      color: context.colors.onPrimary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
