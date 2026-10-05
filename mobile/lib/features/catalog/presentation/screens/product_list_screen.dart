import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/providers/paged_state.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../domain/entities.dart';
import '../../domain/product_query.dart';
import '../catalog_providers.dart';
import '../widgets/connected_product_card.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/product_card.dart';
import '../widgets/subcategory_circles.dart';
import '../../../../core/widgets/saba_nav_bar.dart';

/// Paginated product results.
///
/// Used for a category, a merchant's catalogue and search results alike: the
/// only difference is the [initialQuery] handed in.
///
/// The chrome is shared with search on purpose. Both are the same thing to a
/// customer — a list they are narrowing — so both get the same header, the
/// same removable filter chips and the same no-results screen.
class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key, required this.initialQuery, this.title});

  final ProductQuery initialQuery;
  final String? title;

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  late ProductQuery _query = widget.initialQuery;

  /// The category this list opened on (a Home tile): its sub-categories are
  /// offered above the grid.
  late final String? _parentId = widget.initialQuery.categoryId;

  /// The sub-category circles while the list is within [_parentId], else null.
  Widget? _subcategories() {
    final parent = _parentId == null
        ? null
        : ref
              .watch(categoryTreeProvider)
              .value
              ?.where((category) => category.id == _parentId)
              .firstOrNull;
    if (parent == null || parent.children.isEmpty) return null;
    final chosen = _query.categoryId;
    final within =
        chosen == parent.id || parent.children.any((c) => c.id == chosen);
    if (!within) return null;
    return SubcategoryCircles(
      parent: parent,
      selectedId: chosen == parent.id ? null : chosen,
      onSelected: (id) => setState(
        () => _query = _query.copyWith(categoryId: id ?? parent.id),
      ),
    );
  }

  Future<void> _openSort() async {
    final selected = await AppDialogs.bottomSheet<ProductSort>(
      context,
      isScrollControlled: false,
      builder: (_) => SortSheet(current: _query.sort),
    );
    if (selected != null) {
      setState(() => _query = _query.copyWith(sort: selected));
    }
  }

  Future<void> _openFilters() async {
    final updated = await AppDialogs.bottomSheet<ProductQuery>(
      context,
      builder: (_) => FilterSheet(query: _query),
    );
    if (updated != null) setState(() => _query = updated);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productListProvider(_query));
    final notifier = ref.read(productListProvider(_query).notifier);

    return Scaffold(
      body: Column(
        children: [
          ResultsHeader(
            query: _query.search ?? widget.title,
            hint: widget.title ?? context.l10n.products,
            filterCount: _query.activeFilterCount,
            onQueryTap: () =>
                context.push('${AppRoutes.search}?q=${_query.search ?? ''}'),
            onFilters: _openFilters,
            onClear: _query.search == null
                ? null
                : () => setState(
                    () => _query = _query.copyWith(clearSearch: true),
                  ),
            chips: buildFilterChips(
              context,
              query: _query,
              onChanged: (next) => setState(() => _query = next),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                AsyncStateView<PagedState<ProductSummary>>(
                  value: state,
                  onRetry: () => ref.invalidate(productListProvider(_query)),
                  loadingBuilder: (_) =>
                      const ProductGridSkeleton(itemCount: 8),
                  builder: (paged) => ResultsGrid(
                    paged: paged,
                    query: _query,
                    onLoadMore: notifier.loadMore,
                    onRefresh: notifier.refresh,
                    onRetryLoadMore: notifier.retryLoadMore,
                    onSort: _openSort,
                    onQueryChanged: (next) => setState(() => _query = next),
                    top: _subcategories(),
                  ),
                ),
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 0,
                  child: FloatingFilterButton(
                    count: _query.activeFilterCount,
                    onPressed: _openFilters,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The chips for whatever is currently filtering a list, plus "Clear all".
///
/// Shared by the list and search screens so a filter is described the same
/// way wherever it is switched on.
List<Widget> buildFilterChips(
  BuildContext context, {
  required ProductQuery query,
  required ValueChanged<ProductQuery> onChanged,
}) {
  final l10n = context.l10n;
  final locale = l10n.locale.toLanguageTag();

  final filters = query.activeFilters(
    money: (amount) => Formatters.money(amount, locale: locale),
    priceUpTo: l10n.upTo,
    priceFrom: l10n.from,
    priceBetween: l10n.priceRange,
    inStock: l10n.inStock,
    onSale: l10n.onSale,
    brandsLabel: l10n.brands,
    comma: l10n.comma,
  );

  if (filters.isEmpty) return const <Widget>[];

  return <Widget>[
    for (final filter in filters)
      ActiveFilterChip(
        label: filter.label,
        onRemove: () => onChanged(filter.remove()),
      ),
    ClearAllChip(onPressed: () => onChanged(query.clearedFilters())),
  ];
}

/// The results themselves: a count, a sort, then the grid.
class ResultsGrid extends StatelessWidget {
  const ResultsGrid({
    super.key,
    required this.paged,
    required this.query,
    required this.onLoadMore,
    required this.onRefresh,
    required this.onRetryLoadMore,
    required this.onSort,
    required this.onQueryChanged,
    this.top,
  });

  final PagedState<ProductSummary> paged;
  final ProductQuery query;
  final VoidCallback onLoadMore;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetryLoadMore;
  final VoidCallback onSort;
  final ValueChanged<ProductQuery> onQueryChanged;

  /// Above the count, scrolling with the grid: a category's sub-categories.
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final columns = context.productGridColumns;

    if (paged.items.isEmpty && !paged.isLoadingMore) {
      final empty = _EmptyResults(query: query, onQueryChanged: onQueryChanged);
      // An empty sub-category keeps its row, so "All" is one tap away.
      if (top == null) return empty;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md + 2,
              AppSpacing.screenGutter,
              0,
            ),
            child: top,
          ),
          Expanded(child: empty),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth =
            (constraints.maxWidth -
                AppSpacing.screenGutter * 2 -
                AppSpacing.md * (columns - 1)) /
            columns;

        return PagedListView<ProductSummary>(
          state: paged,
          // A product grid keeps its place when a product is closed.
          reloadOnReturn: false,
          onLoadMore: onLoadMore,
          onRefresh: onRefresh,
          onRetryLoadMore: onRetryLoadMore,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md + 2,
            AppSpacing.screenGutter,
            SabaNavBar.clearance(context),
          ),
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?top,
              ResultsBar(
                count: paged.total,
                sortLabel: sortLabel(l10n, query.sort),
                onSort: onSort,
              ),
            ],
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            mainAxisExtent: ProductCard.heightFor(context, cardWidth),
          ),
          itemBuilder: (context, product, _) =>
              ConnectedProductCard(product: product),
        );
      },
    );
  }
}

/// A dead end, turned into live paths where it can be.
class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.query, required this.onQueryChanged});

  final ProductQuery query;
  final ValueChanged<ProductQuery> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtered = query.hasActiveFilters;

    return NoResultsView(
      icon: filtered ? SabaIcons.sort : SabaIcons.zoomOut,
      title: filtered ? l10n.noResultsFiltered : l10n.emptySearch,
      // Names the cause. The exact counts each relaxation would return need
      // the server to report them, which it does not yet — see WORK-LOG F26.
      message: filtered
          ? l10n.noResultsFilteredMessage
          : l10n.emptySearchMessage,
      actions: [
        if (filtered)
          FilledButton(
            onPressed: () => onQueryChanged(query.clearedFilters()),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: Text(l10n.clearAll),
          ),
        AppButton(
          label: l10n.startShopping,
          variant: AppButtonVariant.secondary,
          onPressed: () => context.go(AppRoutes.home),
        ),
      ],
    );
  }
}
