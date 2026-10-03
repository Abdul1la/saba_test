import 'package:flutter/material.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/rating_stars.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/entities.dart';

/// One review, with its photos and the seller's reply.
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review, this.onReport});

  final Review review;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final market = context.market;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: market.surfaceMuted,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  (review.authorName ?? '?').characters.first.toUpperCase(),
                  style: context.textStyles.labelLarge?.copyWith(
                    color: market.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            review.authorName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.labelLarge?.copyWith(
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (review.isVerifiedPurchase) ...[
                          const SizedBox(width: AppSpacing.sm - 2),
                          // A bought-it badge is what separates a review from
                          // an opinion, so it sits on the name, not below it.
                          SabaIcon(
                            SabaIcons.shield,
                            size: 13,
                            color: market.success,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs - 1),
                    Row(
                      children: [
                        RatingStars(rating: review.rating.toDouble(), size: 13),
                        const SizedBox(width: AppSpacing.sm - 2),
                        Flexible(
                          child: Text(
                            Formatters.date(review.createdAt, locale: locale),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onReport != null)
                IconButton(
                  onPressed: onReport,
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.reportReview,
                  icon: SabaIcon(
                    SabaIcons.flag,
                    size: AppSizes.iconSm,
                    color: market.textMuted,
                  ),
                ),
            ],
          ),
          if (review.variantLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(review.variantLabel!, style: context.textStyles.labelSmall),
          ],
          if (review.title != null && review.title!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              review.title!,
              style: context.textStyles.titleSmall?.copyWith(fontSize: 14),
            ),
          ],
          if (review.body != null && review.body!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs + 1),
            Text(
              review.body!,
              style: context.textStyles.bodyMedium?.copyWith(
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
          ],
          if (review.photoUrls.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.photoUrls.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) => AppNetworkImage(
                  url: review.photoUrls[index],
                  width: 76,
                  height: 76,
                  radius: AppRadius.md,
                  fallbackIcon: SabaIcons.image,
                ),
              ),
            ),
          ],
          if (review.merchantResponse != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: market.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.action),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SabaIcon(
                        SabaIcons.store,
                        size: 13,
                        color: market.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.xs + 1),
                      Expanded(
                        child: Text(
                          review.merchantResponse!.merchantName ??
                              l10n.merchantReplied,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.labelMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs + 1),
                  Text(
                    review.merchantResponse!.body,
                    style: context.textStyles.bodySmall?.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
