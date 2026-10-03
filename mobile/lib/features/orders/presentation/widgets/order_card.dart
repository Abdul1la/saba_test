import 'package:flutter/material.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_network_image.dart';

/// `card/order` — the one card for an order, in the shopper's My Orders and
/// the store's orders list.
///
/// The number and its status badge, a muted line or two of facts, then what
/// it costs. Each side adds what it needs: the shopper a photo of what was
/// bought, the store the lines to pack and the buttons that move it on.
/// The badge is always an `OrderStatusChip` or a `StatusBadge` of the same
/// tones, so a status is the same colour on both sides.
class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.orderNumber,
    required this.badge,
    required this.facts,
    required this.total,
    required this.currencyCode,
    required this.onTap,
    this.showPhoto = false,
    this.imageUrl,
    this.footnote,
    this.items = const <(String, int)>[],
    this.actions,
  });

  final String orderNumber;
  final Widget badge;

  /// One muted line each, under the number.
  final List<String> facts;
  final num total;
  final String currencyCode;
  final VoidCallback onTap;

  /// A photo of the first thing in it, [imageUrl]: the shopper's side
  /// shows one, a bag when there is no photo.
  final bool showPhoto;
  final String? imageUrl;

  /// Beside the total: how it is paid.
  final Widget? footnote;

  /// Name and quantity of each line; the first three are shown.
  final List<(String, int)> items;

  /// Under everything: the store's buttons.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final locale = context.l10n.locale.toLanguageTag();
    final radius = BorderRadius.circular(AppRadius.card);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                orderNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.titleMedium?.copyWith(fontSize: 14.5),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            badge,
          ],
        ),
        for (final fact in facts) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            fact,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.labelSmall,
          ),
        ],
        if (items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: market.border),
          const SizedBox(height: AppSpacing.sm),
          for (final (name, quantity) in items.take(3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodyMedium?.copyWith(
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('×$quantity', style: context.textStyles.labelSmall),
                ],
              ),
            ),
          if (items.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '+${items.length - 3}',
                style: context.textStyles.labelSmall,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: market.border),
        ],
        const SizedBox(height: AppSpacing.sm + 2),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: footnote ?? const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              Formatters.money(
                total,
                locale: locale,
                currencyCode: currencyCode,
              ),
              style: context.textStyles.titleMedium?.copyWith(fontSize: 15),
            ),
          ],
        ),
        if (actions != null) ...[
          const SizedBox(height: AppSpacing.md),
          actions!,
        ],
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppElevation.card,
      ),
      child: Material(
        color: context.colors.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md + 2),
            child: !showPhoto
                ? body
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppNetworkImage(
                        url: imageUrl,
                        width: 64,
                        height: 64,
                        radius: AppRadius.md,
                        fallbackIcon: SabaIcons.bag,
                      ),
                      const SizedBox(width: AppSpacing.md + 2),
                      Expanded(child: body),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
