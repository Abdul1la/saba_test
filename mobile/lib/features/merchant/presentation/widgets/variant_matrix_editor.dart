import 'package:flutter/material.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/saba_icons.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/entities.dart';

/// Builds a product's variant matrix (specification section 10).
///
/// The merchant declares option types with their values — Color: Red, Blue;
/// Storage: 128GB, 256GB — and every combination becomes a row with its own
/// SKU, price and stock. Editing an option regenerates the rows, and any row
/// whose combination survives keeps what was typed into it, so adding a colour
/// at the end does not wipe the stock figures already entered.
///
/// Price is optional per row: empty means "inherit the product price", which is
/// the common case where only stock differs.
class VariantMatrixEditor extends StatefulWidget {
  const VariantMatrixEditor({
    super.key,
    required this.onChanged,
    this.initial = const <ProductVariantDraft>[],
  });

  final List<ProductVariantDraft> initial;
  final ValueChanged<List<ProductVariantDraft>> onChanged;

  @override
  State<VariantMatrixEditor> createState() => _VariantMatrixEditorState();
}

class _VariantOption {
  _VariantOption({required this.name, required this.values});

  String name;
  List<String> values;
}

class _RowControllers {
  _RowControllers({
    required this.sku,
    required this.price,
    required this.stock,
  });

  final TextEditingController sku;
  final TextEditingController price;
  final TextEditingController stock;

  void dispose() {
    sku.dispose();
    price.dispose();
    stock.dispose();
  }
}

class _VariantMatrixEditorState extends State<VariantMatrixEditor> {
  final List<_VariantOption> _options = <_VariantOption>[];

  /// Row state keyed by option signature, so it survives regeneration.
  final Map<String, _RowControllers> _controllers = <String, _RowControllers>{};

  List<ProductVariantDraft> _rows = <ProductVariantDraft>[];

  @override
  void initState() {
    super.initState();
    _seedFromInitial();
  }

  /// Recovers the option types from existing variants, so editing a product
  /// that already has variants shows the matrix rather than an empty editor.
  void _seedFromInitial() {
    if (widget.initial.isEmpty) return;
    final byName = <String, List<String>>{};
    for (final variant in widget.initial) {
      for (final entry in variant.options.entries) {
        final values = byName.putIfAbsent(entry.key, () => <String>[]);
        if (!values.contains(entry.value)) values.add(entry.value);
      }
    }
    _options.addAll(
      byName.entries.map((e) => _VariantOption(name: e.key, values: e.value)),
    );
    for (final variant in widget.initial) {
      _controllers[variant.signature] = _RowControllers(
        sku: TextEditingController(text: variant.sku ?? ''),
        price: TextEditingController(text: variant.price?.toString() ?? ''),
        stock: TextEditingController(text: variant.stock.toString()),
      );
    }
    _rows = List<ProductVariantDraft>.from(widget.initial);
  }

  @override
  void dispose() {
    for (final controllers in _controllers.values) {
      controllers.dispose();
    }
    super.dispose();
  }

  /// Cartesian product of every option's values.
  List<Map<String, String>> _combinations() {
    // A combination is keyed by option name, so two options sharing a name
    // collapse into one key: the matrix would then draw more rows than it has
    // distinct signatures, and rows sharing a signature share one set of
    // controllers — typing stock into one silently changed another, and the
    // payload posted the duplicates. Same for repeated values inside one
    // option. First one wins, quietly, rather than producing phantom rows.
    final usable = <_VariantOption>[];
    final seenNames = <String>{};
    for (final option in _options) {
      final name = option.name.trim();
      if (name.isEmpty || option.values.isEmpty) continue;
      if (!seenNames.add(name.toLowerCase())) continue;
      final values = <String>[];
      final seenValues = <String>{};
      for (final value in option.values) {
        if (seenValues.add(value.trim().toLowerCase())) values.add(value);
      }
      usable.add(_VariantOption(name: name, values: values));
    }
    if (usable.isEmpty) return const <Map<String, String>>[];

    var result = <Map<String, String>>[<String, String>{}];
    for (final option in usable) {
      final next = <Map<String, String>>[];
      for (final partial in result) {
        for (final value in option.values) {
          next.add(<String, String>{...partial, option.name.trim(): value});
        }
      }
      result = next;
    }
    return result;
  }

  void _rebuild() {
    final combinations = _combinations();
    final live = <String>{};
    final rows = <ProductVariantDraft>[];
    // An option already saved keeps its id and the stock the form showed.
    // The server matches options by id: these rows were rebuilt without
    // one, so any edit here saved every option as new, deleting the old
    // ones and their stock history (the reviewer's stock reset).
    final saved = <String, ProductVariantDraft>{
      for (final row in [...widget.initial, ..._rows])
        if (row.id != null) row.signature: row,
    };

    for (final options in combinations) {
      final draft = ProductVariantDraft(options: options);
      final key = draft.signature;
      live.add(key);
      final controllers = _controllers.putIfAbsent(
        key,
        () => _RowControllers(
          sku: TextEditingController(),
          price: TextEditingController(),
          // Empty, showing its example: a "0" was typed after (the tester).
          stock: TextEditingController(),
        ),
      );
      rows.add(
        ProductVariantDraft(
          options: options,
          id: saved[key]?.id,
          stockBefore: saved[key]?.stockBefore,
          sku: controllers.sku.text.trim().isEmpty
              ? null
              : controllers.sku.text.trim(),
          price: Formatters.typedNumber(controllers.price.text),
          stock: Formatters.typedWholeNumber(controllers.stock.text) ?? 0,
        ),
      );
    }

    // Drop controllers for combinations that no longer exist.
    for (final key in _controllers.keys.toList()) {
      if (!live.contains(key)) _controllers.remove(key)?.dispose();
    }

    setState(() => _rows = rows);
    widget.onChanged(rows);
  }

  Future<void> _editOption([int? index]) async {
    final existing = index == null ? null : _options[index];

    final result = await showDialog<_OptionResult>(
      context: context,
      builder: (context) => _OptionDialog(
        isNew: index == null,
        initialName: existing?.name ?? '',
        initialValues: existing?.values.join(', ') ?? '',
      ),
    );
    if (result == null) return;

    if (index == null) {
      _options.add(_VariantOption(name: result.name, values: result.values));
    } else {
      _options[index]
        ..name = result.name
        ..values = result.values;
    }
    _rebuild();
  }

  /// True when any live row holds something the merchant typed.
  ///
  /// Stock defaults to "0", so that alone does not count as work worth
  /// warning about.
  bool get _hasTypedData => _controllers.values.any(
    (c) =>
        c.sku.text.trim().isNotEmpty ||
        c.price.text.trim().isNotEmpty ||
        (c.stock.text.trim().isNotEmpty && c.stock.text.trim() != '0'),
  );

  /// Removing an option regenerates the matrix, and [_rebuild] disposes the
  /// controllers of every combination that no longer exists.
  ///
  /// Drawn as an `InputChip`'s small ×, which everywhere else in the app means
  /// "take this filter off" — here it could throw away the SKU, price and
  /// stock for two dozen combinations with no confirmation and no undo. It
  /// now asks, but only when there is something to lose.
  Future<void> _removeOption(int index) async {
    if (_hasTypedData) {
      final l10n = context.l10n;
      final confirmed = await AppDialogs.confirm(
        context,
        title: l10n.removeOptionTitle,
        message: l10n.removeOptionMessage,
        confirmLabel: l10n.remove,
        isDestructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    _options.removeAt(index);
    _rebuild();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Titled by the form section that holds it.
        Text(l10n.variantsHint, style: context.textStyles.labelSmall),
        // An empty matrix is omitted from the payload rather than clearing
        // the variants, and saying nothing let the blank read as "this
        // product has none".
        if (_options.isEmpty && widget.initial.isEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.variantsKeptIfEmpty,
            style: context.textStyles.labelSmall?.copyWith(
              color: context.market.textMuted,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),

        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var i = 0; i < _options.length; i++)
              InputChip(
                label: Text(
                  '${_options[i].name}: ${_options[i].values.length}',
                ),
                onPressed: () => _editOption(i),
                onDeleted: () => _removeOption(i),
              ),
            ActionChip(
              avatar: SabaIcon(SabaIcons.plus, size: 18),
              label: Text(l10n.addOption),
              onPressed: _editOption,
            ),
          ],
        ),

        if (_rows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            '${_rows.length} ${l10n.variants}',
            style: context.textStyles.labelMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _VariantRow(
                label: row.label,
                controllers: _controllers[row.signature]!,
                onChanged: _rebuild,
              ),
            ),
        ],
      ],
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.label,
    required this.controllers,
    required this.onChanged,
  });

  final String label;
  final _RowControllers controllers;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.textStyles.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: l10n.price,
                    hint: l10n.inheritPrice,
                    controller: controllers.price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        Validators.optionalCashPrice(value, l10n),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppTextField(
                    label: l10n.stock,
                    hint: context.exampleOf(5),
                    controller: controllers.stock,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What the option dialog returns. `null` means cancelled or incomplete.
class _OptionResult {
  const _OptionResult(this.name, this.values);

  final String name;
  final List<String> values;
}

/// Owns its own controllers.
///
/// Creating them in the calling method and disposing after `showDialog`
/// returns is a use-after-dispose: the dialog is still in the tree while its
/// exit transition runs, and rebuilds against the disposed controllers.
class _OptionDialog extends StatefulWidget {
  const _OptionDialog({
    required this.isNew,
    required this.initialName,
    required this.initialValues,
  });

  final bool isNew;
  final String initialName;
  final String initialValues;

  @override
  State<_OptionDialog> createState() => _OptionDialogState();
}

class _OptionDialogState extends State<_OptionDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _values = TextEditingController(text: widget.initialValues);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _values.dispose();
    super.dispose();
  }

  List<String> get _parsedValues => _values.text
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList();

  /// An option needs a name and at least one value. Save with either empty
  /// used to close the dialog without a word, dropping what was typed.
  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_OptionResult(_name.text.trim(), _parsedValues));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      titleTextStyle: AppTypography.subsectionTitle(context),
      title: Text(widget.isNew ? l10n.addOption : l10n.editOption),
      // An AlertDialog sizes its content to intrinsic height, so the column
      // needs a bounded width and its own scroll or two text fields can
      // overflow on a short viewport.
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: l10n.optionName,
                  hint: l10n.optionNameHint,
                  controller: _name,
                  isRequired: true,
                  autofocus: widget.isNew,
                  textInputAction: TextInputAction.next,
                  validator: (value) => Validators.required(value, l10n),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: l10n.optionValues,
                  hint: l10n.optionValuesHint,
                  controller: _values,
                  isRequired: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  // "  , ," is not empty text, and still no values.
                  validator: (_) => _parsedValues.isEmpty
                      ? Validators.required('', l10n)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [DialogActions(confirmLabel: l10n.save, onConfirm: _submit)],
    );
  }
}
