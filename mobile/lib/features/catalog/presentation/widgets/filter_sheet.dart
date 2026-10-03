import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/localization/app_localizations.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/option_sheet.dart';
import '../../domain/entities.dart';
import '../../domain/product_query.dart';
import '../catalog_providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/western_digits_formatter.dart';

/// Sort picker.
/// The name of a sort order, shared by the sheet and the results bar so the
/// two can never disagree about what is currently applied.
String sortLabel(AppLocalizations l10n, ProductSort sort) => switch (sort) {
  ProductSort.relevance => l10n.sortRelevance,
  ProductSort.newest => l10n.sortNewest,
  ProductSort.priceAsc => l10n.sortPriceLowHigh,
  ProductSort.priceDesc => l10n.sortPriceHighLow,
  ProductSort.bestSelling => l10n.sortBestSelling,
};

class SortSheet extends StatelessWidget {
  const SortSheet({super.key, required this.current});

  final ProductSort current;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return OptionSheet<ProductSort>(
      title: l10n.sortBy,
      options: ProductSort.values,
      current: current,
      labelOf: (sort) => sortLabel(l10n, sort),
    );
  }
}

/// Filter sheet.
///
/// Brand and attribute options are fetched from the backend for the current
/// category, so a new admin-created attribute shows up here with no app
/// release (specification sections 9 and 35).
class FilterSheet extends ConsumerStatefulWidget {
  const FilterSheet({super.key, required this.query});

  final ProductQuery query;

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  late ProductQuery _draft = widget.query;
  late final TextEditingController _minPrice = TextEditingController(
    text: widget.query.minPrice?.toString() ?? '',
  );
  late final TextEditingController _maxPrice = TextEditingController(
    text: widget.query.maxPrice?.toString() ?? '',
  );

  @override
  void initState() {
    super.initState();
    // Saba's brands as they are now: a brand it checked since the filter
    // first opened is offered. Only a list already kept is read again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final kept = brandsProvider(widget.query.categoryId);
      if (mounted && ref.read(kept).hasValue) ref.invalidate(kept);
    });
  }

  @override
  void dispose() {
    _minPrice.dispose();
    _maxPrice.dispose();
    super.dispose();
  }

  void _apply() {
    // "50,000" as people write it: the commas were read as no number at
    // all, and the price was quietly left out of the filter.
    final result = _draft.copyWith(
      minPrice: Formatters.typedNumber(_minPrice.text),
      maxPrice: Formatters.typedNumber(_maxPrice.text),
      clearPriceRange:
          _minPrice.text.trim().isEmpty && _maxPrice.text.trim().isEmpty,
    );
    Navigator.of(context).pop(result);
  }

  void _reset() {
    setState(() {
      _draft = widget.query.clearedFilters();
      _minPrice.clear();
      _maxPrice.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final categoryId = widget.query.categoryId;
    final brands = ref.watch(brandsProvider(categoryId));
    final attributes = categoryId == null
        ? const AsyncValue<List<AttributeDefinition>>.data([])
        : ref.watch(categoryAttributesProvider(categoryId));

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.filters,
                      style: AppTypography.subsectionTitle(context),
                    ),
                  ),
                  TextButton(onPressed: _reset, child: Text(l10n.reset)),
                ],
              ),
            ),
            const _Hairline(),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _Label(text: l10n.priceRange),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minPrice,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [WesternDigitsFormatter()],
                          // The word above, an example inside.
                          decoration: InputDecoration(
                            labelText: l10n.from,
                            hintText: context.exampleOf(25000),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextField(
                          controller: _maxPrice,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [WesternDigitsFormatter()],
                          decoration: InputDecoration(
                            labelText: l10n.to,
                            hintText: context.exampleOf(100000),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  _Label(text: l10n.availability),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.inStockOnly),
                    value: _draft.inStockOnly,
                    onChanged: (value) => setState(
                      () => _draft = _draft.copyWith(inStockOnly: value),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.onSale),
                    value: _draft.onSaleOnly,
                    onChanged: (value) => setState(
                      () => _draft = _draft.copyWith(onSaleOnly: value),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Only when there are brands: the live shop has none (the
                  // store's form sends none), and a heading over nothing
                  // filters nothing.
                  if (brands.value case final items? when items.isNotEmpty) ...[
                    _Label(text: l10n.brands),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final brand in items)
                          FilterChip(
                            selected: _draft.brandIds.contains(brand.id),
                            label: Text(brand.name),
                            onSelected: (selected) => setState(() {
                              final ids = <String>[..._draft.brandIds];
                              if (selected) {
                                ids.add(brand.id);
                              } else {
                                ids.remove(brand.id);
                              }
                              _draft = _draft.copyWith(brandIds: ids);
                            }),
                          ),
                      ],
                    ),
                  ],

                  attributes.maybeWhen(
                    data: (definitions) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final attribute in definitions.where(
                          (a) => a.isFilterable,
                        ))
                          _AttributeFilter(
                            attribute: attribute,
                            selected:
                                _draft.attributes[attribute.name] ?? const [],
                            onChanged: (values) => setState(() {
                              final map = <String, List<String>>{
                                ..._draft.attributes,
                                attribute.name: values,
                              };
                              _draft = _draft.copyWith(attributes: map);
                            }),
                          ),
                      ],
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const _Hairline(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AppButton(label: l10n.apply, onPressed: _apply),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttributeFilter extends StatelessWidget {
  const _AttributeFilter({
    required this.attribute,
    required this.selected,
    required this.onChanged,
  });

  final AttributeDefinition attribute;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (attribute.values.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xl),
        _Label(text: attribute.name),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in attribute.values)
              FilterChip(
                selected: selected.contains(option.value),
                label: Text(option.display),
                onSelected: (isSelected) {
                  final values = <String>[...selected];
                  if (isSelected) {
                    values.add(option.value);
                  } else {
                    values.remove(option.value);
                  }
                  onChanged(values);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: context.textStyles.titleSmall),
    );
  }
}

/// A separating line in the app's own border colour.
///
/// Material's `Divider` brings its own inset, its own theme colour and its own
/// 16-point height around a 1-point line, none of which match the sheets it
/// was sitting in.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: context.market.border);
}
