import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../domain/entities.dart';

/// How an offer reads, in the reader's language.
extension CouponOfferText on CouponOffer {
  /// "10% off", "5,000 IQD off".
  String title(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    return l10n.amountOff(
      isPercentage
          ? Formatters.percent(value, locale: locale)
          : Formatters.money(value, locale: locale, currencyCode: currencyCode),
    );
  }

  /// Who it is for: "Your first order only", "On orders over 50,000 IQD" -
  /// led by the store, for a store's own coupon, unless [withStore] is off
  /// because the page is that store's already.
  String condition(BuildContext context, {bool withStore = true}) {
    final l10n = context.l10n;
    final String rule;
    final minimum = minOrderAmount;
    if (firstOrderOnly) {
      rule = l10n.firstOrderOnly;
    } else if (minimum != null && minimum > 0) {
      final amount = Formatters.money(
        minimum,
        locale: l10n.locale.toLanguageTag(),
        currencyCode: currencyCode,
      );
      rule = '${l10n.onOrdersOver} $amount';
    } else {
      rule = l10n.onAnyOrder;
    }
    final store = merchantName;
    if (!withStore || store == null) return rule;
    return '${l10n.atStore(store)} · $rule';
  }
}

/// The customer's coupons under the cart's code field. One tap puts one on,
/// so nobody has to know a code, remember it, or type it.
class CouponOfferChips extends StatelessWidget {
  const CouponOfferChips({
    super.key,
    required this.offers,
    required this.onApply,
  });

  final List<CouponOffer> offers;

  /// Null while a coupon is being applied, so a second tap cannot race it.
  final ValueChanged<String>? onApply;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final apply = onApply;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.tapCouponToUse, style: context.textStyles.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final offer in offers)
              Material(
                color: market.accentSoft,
                clipBehavior: Clip.antiAlias,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: market.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: InkWell(
                  onTap: apply == null ? null : () => apply(offer.code),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSizes.minTapTarget - 4,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md + 2,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SabaIcon(
                            SabaIcons.ticket,
                            size: 16,
                            color: market.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            offer.code,
                            style: context.textStyles.labelLarge?.copyWith(
                              color: market.accent,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              // With its minimum, when it has one (the
                              // tester): the chip said only "10% off".
                              (offer.minOrderAmount ?? 0) > 0
                                  ? '${offer.title(context)} · '
                                        '${offer.condition(context, withStore: false)}'
                                  : offer.title(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.labelMedium?.copyWith(
                                color: context.colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The customer's coupons on Home, side by side, each with its code and a
/// Copy button. The same offers wait as one-tap chips in the cart.
class CouponOfferStrip extends StatelessWidget {
  const CouponOfferStrip({
    super.key,
    required this.offers,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.screenGutter,
    ),
    this.withStore = true,
  });

  final List<CouponOffer> offers;

  /// Home runs the strip edge to edge; a page already inside the gutter
  /// passes zero.
  final EdgeInsets padding;

  /// Off on a store's own page, where "At Nova Electronics" says nothing.
  final bool withStore;

  @override
  Widget build(BuildContext context) {
    // A lone offer takes the row; several scroll at a width that shows the
    // next one peeking in.
    final width = offers.length == 1
        ? MediaQuery.sizeOf(context).width - AppSpacing.screenGutter * 2
        : 272.0;

    // ponytail: a Row in a scroll view, not a lazy list, so every card takes
    // the height its text needs at any text size. Fine for the handful of
    // coupons one account holds; a ListView with a measured height if an
    // account ever carries dozens.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < offers.length; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: width,
                child: _CouponCard(offer: offers[index], withStore: withStore),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({required this.offer, this.withStore = true});

  final CouponOffer offer;
  final bool withStore;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: offer.code));
    if (!context.mounted) return;
    AppSnackBar.success(context, context.l10n.couponCopied);
  }

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: market.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: market.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  offer.title(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.titleLarge?.copyWith(
                    fontSize: 19,
                    color: market.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  offer.condition(context, withStore: withStore),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    SabaIcon(
                      SabaIcons.ticket,
                      size: 15,
                      color: context.colors.onSurface,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        offer.code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: context.colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Second level: a rail of these sits on Home, and none of them is
          // the screen's main action.
          OutlinedButton(
            onPressed: () => _copy(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              tapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            ),
            child: Text(context.l10n.copy),
          ),
        ],
      ),
    );
  }
}
