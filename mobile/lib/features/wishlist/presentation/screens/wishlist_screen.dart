import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../catalog/domain/entities.dart';
import '../../../catalog/presentation/widgets/connected_product_card.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../wishlist_providers.dart';

/// Everything the customer has saved.
class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final wishlist = ref.watch(wishlistControllerProvider);
    final controller = ref.read(wishlistControllerProvider.notifier);

    return Scaffold(
      appBar: SabaAppBar(title: l10n.wishlist),
      body: SafeArea(
        top: false,
        child: AsyncStateView<List<ProductSummary>>(
          value: wishlist,
          onRetry: () => ref.invalidate(wishlistControllerProvider),
          loadingBuilder: (_) => const ProductGridSkeleton(),
          builder: (items) {
            if (items.isEmpty) {
              return NoResultsView(
                icon: SabaIcons.heart,
                title: l10n.emptyWishlist,
                message: l10n.emptyWishlistMessage,
                actions: [
                  FilledButton(
                    onPressed: () => context.go(AppRoutes.home),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(l10n.startShopping),
                  ),
                ],
              );
            }

            final columns = context.productGridColumns;

            return RefreshIndicator(
              onRefresh: controller.refresh,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth =
                      (constraints.maxWidth -
                          AppSpacing.screenGutter * 2 -
                          AppSpacing.md * (columns - 1)) /
                      columns;

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.md,
                      AppSpacing.screenGutter,
                      AppSpacing.xxl,
                    ),
                    // The card reports the height it needs. This grid used to
                    // guess with childAspectRatio: 0.56, which is the same
                    // mistake that overflowed every card in the catalogue —
                    // a ratio cannot know the text scale the reader has set.
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: AppSpacing.md,
                      mainAxisExtent: ProductCard.heightFor(context, cardWidth),
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        ConnectedProductCard(product: items[index]),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
