import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_dimensions.dart';
import '../utils/context_extensions.dart';

/// A shimmering placeholder block.
///
/// Skeletons keep the layout stable while data loads, which avoids the content
/// jump a bare spinner causes (specification section 59).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.xs,
  });

  const SkeletonBox.circle({super.key, required double size})
    : width = size,
      height = size,
      radius = AppRadius.pill;

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.market.skeletonBase,
      highlightColor: context.market.skeletonHighlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.market.skeletonBase,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Placeholder shaped like a product card, used by grids while loading.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AspectRatio(
          aspectRatio: AppSizes.productCardImageRatio,
          child: SkeletonBox(height: double.infinity, radius: AppRadius.md),
        ),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonBox(height: 13),
        const SizedBox(height: AppSpacing.xs),
        const SkeletonBox(width: 110, height: 13),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonBox(width: 70, height: 16),
      ],
    );
  }
}

/// A grid of product skeletons matching the real grid's column count.
///
/// [itemExtent] must be the height the real grid will use — pass
/// `ProductCard.heightFor(context, cardWidth)`. It guessed with a ratio of
/// its own before, so every card jumped the moment the data arrived.
/// Core cannot import a feature, so the number comes in from the caller.
class ProductGridSkeleton extends StatelessWidget {
  const ProductGridSkeleton({super.key, this.itemCount = 6, this.itemExtent});

  final int itemCount;
  final double? itemExtent;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: context.productGridColumns,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        mainAxisExtent: itemExtent ?? _fallbackExtent(context),
      ),
      itemCount: itemCount,
      itemBuilder: (_, _) => const ProductCardSkeleton(),
    );
  }

  /// Only for a caller that cannot measure yet. Derived from the card's own
  /// proportions rather than picked, so it is close even when it is a guess.
  static double _fallbackExtent(BuildContext context) {
    final width = context.screenWidth / context.productGridColumns;
    return width / AppSizes.productCardImageRatio + 116;
  }
}

/// A vertical run of list-row skeletons.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.itemCount = 6, this.itemHeight = 72});

  final int itemCount;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, _) => Row(
        children: [
          SkeletonBox(
            width: itemHeight,
            height: itemHeight,
            radius: AppRadius.sm,
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 14),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 140, height: 12),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 80, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder for a horizontally scrolling home-page section.
class HorizontalSectionSkeleton extends StatelessWidget {
  const HorizontalSectionSkeleton({super.key, this.height = 250});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (_, _) =>
            const SizedBox(width: 155, child: ProductCardSkeleton()),
      ),
    );
  }
}
