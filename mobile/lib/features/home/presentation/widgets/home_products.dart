import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/location/governorate.dart';
import '../../../../core/location/governorate_picker.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../catalog/domain/product_query.dart';
import '../../../catalog/presentation/catalog_providers.dart';
import '../../../catalog/presentation/widgets/connected_product_card.dart';
import '../../../catalog/presentation/widgets/filter_sheet.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../home_providers.dart';

/// "All cities", then each city that has a store, right above "All
/// products", the grid it filters: under the search bar it sat far from it.
/// The one picked is filled with the accent; it filters that grid and
/// nothing else - not the flash sale, the coupons or the featured stores,
/// and where the shopper is delivered to stays their own city.
class HomeCityChips extends ConsumerWidget {
  const HomeCityChips({super.key, required this.cities});

  final List<Governorate> cities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = Governorate.fromApi(
      ref.watch(homeProductsControllerProvider).governorate,
    );
    final controller = ref.read(homeProductsControllerProvider.notifier);

    return SizedBox(
      height: AppSizes.minTapTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        itemCount: cities.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CityChip(
              label: context.l10n.allCities,
              icon: SabaIcons.globe,
              isSelected: picked == null,
              onTap: () => controller.selectCity(null),
            );
          }
          final city = cities[index - 1];
          return _CityChip(
            label: city.label(context),
            icon: SabaIcons.mapPin,
            isSelected: picked == city,
            onTap: () => controller.selectCity(city),
          );
        },
      ),
    );
  }
}

class _CityChip extends StatelessWidget {
  const _CityChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final shape = StadiumBorder(
      side: isSelected ? BorderSide.none : BorderSide(color: market.border),
    );
    final ink = isSelected ? market.onAccent : context.colors.onSurface;

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? market.accent : context.colors.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The icon marks the one picked, as in the design: the rest
                // are words only, so the row reads at a glance.
                if (isSelected) ...[
                  SabaIcon(icon, size: AppSizes.iconSm, color: ink),
                  const SizedBox(width: AppSpacing.xs + 2),
                ],
                Text(
                  label,
                  style: context.textStyles.titleSmall?.copyWith(
                    color: ink,
                    fontSize: 14,
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

/// Every product on Saba, after the stores: a Filters button, how many were
/// found, and a grid of [ProductCard]s. Built as it scrolls into
/// view and fetched a page at a time, so a long list stays smooth.
///
/// Follows the city chip and the Filters sheet; the count follows both.
class HomeAllProducts extends ConsumerWidget {
  const HomeAllProducts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final query = ref.watch(homeProductsQueryProvider);
    final filters = ref.watch(homeProductsControllerProvider);
    final paged = ref.watch(productListProvider(query));
    final notifier = ref.read(productListProvider(query).notifier);
    // Every city with a store: their own list, not the stores rail's, which
    // shows only the featured ones.
    final cities = ref.watch(storeCitiesProvider).value ?? const [];

    Future<void> openFilters() async {
      final updated = await AppDialogs.bottomSheet<ProductQuery>(
        context,
        builder: (_) => FilterSheet(query: filters),
      );
      if (updated != null) {
        ref.read(homeProductsControllerProvider.notifier).applyFilters(updated);
      }
    }

    return SliverMainAxisGroup(
      slivers: [
        if (cities.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sectionGap),
              child: HomeCityChips(cities: cities),
            ),
          ),
        SliverToBoxAdapter(child: SectionHeader(title: l10n.allProducts)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              0,
              AppSpacing.screenGutter,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                _FiltersButton(
                  count: filters.activeFilterCount,
                  onPressed: openFilters,
                ),
                const Spacer(),
                if (paged.value case final state?)
                  Text(
                    l10n.productsFound(state.total),
                    style: context.textStyles.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        ...paged.when(
          data: (state) => [
            if (state.items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    l10n.emptyProducts,
                    textAlign: TextAlign.center,
                    style: context.textStyles.bodyMedium,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenGutter,
                ),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = context.productGridColumns;
                    final width =
                        (constraints.crossAxisExtent -
                            AppSpacing.md * (columns - 1)) /
                        columns;
                    return SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisSpacing: AppSpacing.md,
                        mainAxisExtent: ProductCard.heightFor(context, width),
                      ),
                      itemCount: state.items.length,
                      itemBuilder: (context, index) {
                        // The next page is asked for a few cards before the
                        // end, so it is usually there before it is reached.
                        // loadMore ignores a call while one is in flight.
                        if (index >= state.items.length - 4 &&
                            state.hasMore &&
                            state.loadMoreFailure == null) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => notifier.loadMore(),
                          );
                        }
                        return ConnectedProductCard(
                          product: state.items[index],
                        );
                      },
                    );
                  },
                ),
              ),
            if (state.isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            if (state.loadMoreFailure != null)
              SliverToBoxAdapter(
                child: Center(
                  child: TextButton(
                    onPressed: notifier.loadMore,
                    child: Text(l10n.retry),
                  ),
                ),
              ),
          ],
          loading: () => const [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
          error: (error, _) => [
            SliverToBoxAdapter(
              child: AppErrorView(
                failure: ErrorMapper.fromObject(error),
                compact: true,
                onRetry: () => ref.invalidate(productListProvider(query)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Filters", outlined, with how many are on when any are.
class _FiltersButton extends StatelessWidget {
  const _FiltersButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final radius = BorderRadius.circular(AppRadius.action);

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: market.border),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SabaIcon(
                  SabaIcons.sliders,
                  size: AppSizes.iconMd,
                  color: context.colors.onSurface,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  context.l10n.filters,
                  style: context.textStyles.titleSmall?.copyWith(fontSize: 15),
                ),
                if (count > 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Badge(label: Text('$count'), backgroundColor: market.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
