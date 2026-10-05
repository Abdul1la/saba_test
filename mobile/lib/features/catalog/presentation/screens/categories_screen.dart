import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/paged_state.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/filter_chip_row.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/shop_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../domain/entities.dart';
import '../../domain/product_query.dart';
import '../catalog_providers.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/subcategory_circles.dart';
import 'product_list_screen.dart';

/// Browse — things you can buy, with the categories across the top.
///
/// This was a grid of categories: a screen whose entire content was a menu to
/// another screen. Every visit cost a tap before anything buyable appeared,
/// and the tap led somewhere the app could have shown in the first place.
///
/// The categories are still here and still first — they are now a strip rather
/// than a page, and choosing one filters the products underneath instead of
/// pushing a new screen. Nothing was lost; the directory just stopped being a
/// destination.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  /// null is "All". Held here rather than in the query so the strip can be
  /// drawn before the products have loaded.
  String? _categoryId;

  /// One of [_categoryId]'s sub-categories, null for all of it.
  String? _subcategoryId;
  ProductSort _sort = ProductSort.relevance;

  /// The strip reads the categories again when the app is reopened: a
  /// category Saba added, hid or renamed shows then. The grid keeps its
  /// place, and is read again only on a pull, which reads the strip too.
  late final _reopened = AppLifecycleListener(
    onResume: () => ref.invalidate(categoryTreeProvider),
  );

  @override
  void initState() {
    super.initState();
    _reopened;
  }

  @override
  void dispose() {
    _reopened.dispose();
    super.dispose();
  }

  /// The same sheet the results screen uses, so sorting means the same thing
  /// wherever you do it. Passing an empty callback instead would have drawn
  /// the sort control in the results bar and left it doing nothing.
  Future<void> _openSort() async {
    final selected = await AppDialogs.bottomSheet<ProductSort>(
      context,
      isScrollControlled: false,
      builder: (_) => SortSheet(current: _sort),
    );
    if (selected != null) setState(() => _sort = selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tree = ref.watch(categoryTreeProvider);
    final query = ProductQuery(
      categoryId: _subcategoryId ?? _categoryId,
      sort: _sort,
    );
    final state = ref.watch(productListProvider(query));
    final notifier = ref.read(productListProvider(query).notifier);

    // The chosen category's sub-categories, as pictures above its products.
    final parent = _categoryId == null
        ? null
        : tree.value?.where((c) => c.id == _categoryId).firstOrNull;
    final subcategories = parent == null || parent.children.isEmpty
        ? null
        : SubcategoryCircles(
            parent: parent,
            selectedId: _subcategoryId,
            onSelected: (id) => setState(() => _subcategoryId = id),
          );

    return Scaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            PageTitle(title: l10n.browse),
            ShopHeader(hint: l10n.searchProductsAndStores),
            // The strip keeps its place while the categories load, so the
            // screen does not jump once they arrive. "All" is always on it:
            // it was drawn only with the categories, so while they loaded,
            // or when reading them again failed (a weak signal, coming back
            // to the app), the whole strip went and "All" with it. The
            // categories last read stay meanwhile.
            SizedBox(
              height: AppSizes.filterChipHeight + AppSpacing.md,
              child: _CategoryStrip(
                categories: tree.value ?? const <Category>[],
                selectedId: _categoryId,
                onSelected: (id) => setState(() {
                  _categoryId = id;
                  _subcategoryId = null;
                }),
              ),
            ),
            Expanded(
              child: AsyncStateView<PagedState<ProductSummary>>(
                value: state,
                onRetry: () => ref.invalidate(productListProvider(query)),
                loadingBuilder: (_) => const ProductGridSkeleton(itemCount: 8),
                builder: (paged) {
                  if (paged.items.isEmpty) {
                    final empty = NoResultsView(
                      icon: SabaIcons.grid,
                      title: l10n.emptyTitle,
                      // Says which category is empty rather than implying the
                      // whole shop is.
                      message: l10n.emptyProducts,
                    );
                    // An empty sub-category keeps its row: "All" is one tap away.
                    if (subcategories == null) return empty;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.screenGutter,
                            AppSpacing.md + 2,
                            AppSpacing.screenGutter,
                            0,
                          ),
                          child: subcategories,
                        ),
                        Expanded(child: empty),
                      ],
                    );
                  }

                  return ResultsGrid(
                    paged: paged,
                    query: query,
                    onLoadMore: notifier.loadMore,
                    // The strip too, on a pull.
                    onRefresh: () {
                      ref.invalidate(categoryTreeProvider);
                      return notifier.refresh();
                    },
                    onRetryLoadMore: notifier.retryLoadMore,
                    onSort: _openSort,
                    onQueryChanged: (next) => setState(() {
                      // A filter that changed the category starts it afresh.
                      if (next.categoryId != query.categoryId) {
                        _categoryId = next.categoryId;
                        _subcategoryId = null;
                      }
                      _sort = next.sort;
                    }),
                    top: subcategories,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The categories, as a strip.
class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      children: [
        // "All" first, and selected by default, so the screen opens on
        // something to buy rather than on a question.
        _CategoryChip(
          label: context.l10n.all,
          icon: SabaIcons.grid,
          isSelected: selectedId == null,
          onTap: () => onSelected(null),
        ),
        for (var index = 0; index < categories.length; index++) ...[
          const SizedBox(width: AppSpacing.sm),
          _CategoryChip(
            label: categories[index].name,
            icon: iconForName(categories[index].name, index),
            imageUrl: categories[index].imageUrl,
            isSelected: categories[index].id == selectedId,
            onTap: () => onSelected(categories[index].id),
          ),
        ],
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    this.imageUrl,
    required this.isSelected,
    required this.onTap,
  });

  final String label;

  /// Drawn when the category has no picture, or it has not loaded.
  final String icon;

  /// The picture Saba's admin uploads for the category.
  final String? imageUrl;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final radius = BorderRadius.circular(AppRadius.pill);
    final foreground = isSelected ? market.onDark : context.colors.onSurface;

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? context.colors.onSurface : market.surfaceMuted,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: AppSizes.filterChipHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg - 2),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipOval(
                  child: SizedBox.square(
                    dimension: AppSizes.iconSm + 4,
                    child: AppNetworkImage(
                      url: imageUrl,
                      radius: 0,
                      fallback: Center(
                        child: SabaIcon(
                          icon,
                          size: AppSizes.iconSm,
                          color: foreground,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelLarge?.copyWith(
                    color: foreground,
                    fontSize: 13,
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
