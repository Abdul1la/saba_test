import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/option_sheet.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../catalog/domain/entities.dart';
import '../../../catalog/presentation/catalog_providers.dart';
import '../../../media/domain/entities.dart';
import '../../../media/presentation/media_providers.dart';
import '../../../media/presentation/widgets/media_upload_field.dart';
import '../../domain/entities.dart';
import '../merchant_providers.dart';
import '../widgets/variant_matrix_editor.dart';

/// Create or edit a product.
///
/// The category list and its attribute definitions come from the API, so a
/// category an administrator added this morning is selectable here without an
/// app release (specification sections 9 and 24).
class MerchantProductFormScreen extends ConsumerStatefulWidget {
  const MerchantProductFormScreen({super.key, this.existing});

  final MerchantProductRow? existing;

  @override
  ConsumerState<MerchantProductFormScreen> createState() =>
      _MerchantProductFormScreenState();
}

class _MerchantProductFormScreenState
    extends ConsumerState<MerchantProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _nameAr = TextEditingController();
  final _description = TextEditingController();
  late final _price = TextEditingController(
    text: widget.existing?.price.toString() ?? '',
  );
  final _originalPrice = TextEditingController();
  // Empty for a new product, with "e.g. 12" in it: a real "0" there made
  // 1,200 typed after it read "01,200" (the tester).
  late final _stock = TextEditingController(
    text: widget.existing?.stock.toString() ?? '',
  );
  final _warranty = TextEditingController();

  String? _categoryId;

  /// The chosen category's name, kept apart from the tree: a product may sit
  /// in a category Saba has hidden since, which the tree no longer lists but
  /// the product keeps (the admin's categories page).
  String? _categoryName;

  /// Save was pressed with no category chosen.
  bool _categoryMissing = false;

  final _brand = TextEditingController();
  final _brandFocus = FocusNode();

  /// The brand the product had when the form loaded, as the box showed it:
  /// a save leaves the brand alone while the box still says this.
  String _brandShown = '';

  /// The last brand picked from the list.
  Brand? _pickedBrand;
  bool _isSubmitting = false;
  Failure? _failure;

  /// The fields that show the server's refusal under themselves.
  static const _fieldsShown = {
    'name',
    'nameAr',
    'description',
    'categoryId',
    'brandId',
    'brandName',
    'price',
    'originalPrice',
    'stock',
  };

  List<ProductVariantDraft> _variants = const <ProductVariantDraft>[];

  /// The stock the form showed when it loaded a saved product: the server
  /// changes the stock only when the box differs from it (the reviewer:
  /// every save set it again, putting back what sold while the form was
  /// open). Null for a new product.
  int? _stockBefore;

  /// Slots are keyed per product, so editing two products in a session cannot
  /// spill one product's uploads into the other.
  late final String _slotKey = widget.existing?.id ?? 'new';
  late final MediaSlot _imageSlot = MediaSlot(
    id: 'product-images-$_slotKey',
    constraints: MediaConstraints.productImages,
  );
  bool get _isEditing => widget.existing != null;

  /// The product is fetched before the form is drawn, and this says so.
  ///
  /// The screen used to build itself out of the list row it was handed — a
  /// name, a SKU, a price and a stock level — so the merchant edited a
  /// product without being shown its description, its category, its variants
  /// or the rest of its photographs. The one image the row carried was
  /// seeded into the picker, which made the save send a one-image list: a
  /// product with three photographs came back with one.
  bool _loading = false;
  Failure? _loadFailure;

  /// Only set once the record is in, because the variant editor reads its
  /// starting rows once and the form must not be typed into before then.
  List<ProductVariantDraft> _initialVariants = const <ProductVariantDraft>[];

  @override
  void initState() {
    super.initState();
    // The categories and brands as Saba keeps them now, read again when the
    // form opens: kept from an earlier visit, they missed a category Saba
    // hid and a brand it checked since. Only a list already kept is read
    // again; a first one is being read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final kept in [categoryTreeProvider, merchantBrandsProvider]) {
        if (ref.read(kept).hasValue) ref.invalidate(kept);
      }
    });
    final existing = widget.existing;
    if (existing == null) return;
    _loading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(existing.id));
  }

  Future<void> _load(String id) async {
    final result = await ref.read(merchantRepositoryProvider).product(id);
    if (!mounted) return;
    result.fold(
      ok: (product) {
        setState(() {
          _fillFields(product);
          _loading = false;
        });
        // The pickers are Riverpod state that the form watches, so they are
        // seeded in the frame after the form exists rather than in the same
        // one it is built in — changing both at once leaves the tree being
        // measured and read for semantics at the same time.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fillMedia(product);
        });
      },
      // Editing what could not be read means saving a product built from a
      // list row, which is how the photographs were lost. The form refuses
      // to open rather than do that quietly.
      err: (failure) => setState(() {
        _loading = false;
        _loadFailure = failure;
      }),
    );
  }

  void _fillFields(Product product) {
    _nameAr.text = product.nameAr ?? '';
    // A product saved with its Arabic name keeps its English one apart; an
    // older one has only the English.
    _name.text = product.nameEn ?? (product.nameAr == null ? product.name : '');
    _description.text = product.description ?? '';
    _price.text = product.price.toString();
    _originalPrice.text = product.originalPrice?.toString() ?? '';
    _stockBefore = product.availableQuantity ?? 0;
    _stock.text = '$_stockBefore';
    _warranty.text = product.warranty ?? '';
    _categoryId = product.categoryId;
    _categoryName = product.categoryName;
    _brandShown =
        product.brand?.nameIn(Localizations.localeOf(context).languageCode) ??
        '';
    _brand.text = _brandShown;

    _initialVariants = <ProductVariantDraft>[
      for (final variant in product.variants)
        ProductVariantDraft(
          id: variant.id,
          options: variant.options,
          sku: variant.sku,
          price: variant.price,
          stock: variant.availableQuantity ?? 0,
          stockBefore: variant.availableQuantity ?? 0,
        ),
    ];
    _variants = _initialVariants;
  }

  /// Every photograph, not just the one the shelf row showed.
  void _fillMedia(Product product) {
    final images = <UploadedMedia>[
      for (final media in product.media)
        UploadedMedia(id: media.url, url: media.url, kind: MediaKind.image),
    ];
    if (images.isNotEmpty) {
      ref.read(mediaUploadProvider(_imageSlot).notifier).setExisting(images);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _nameAr,
      _description,
      _price,
      _originalPrice,
      _stock,
      _warranty,
      _brand,
    ]) {
      controller.dispose();
    }
    _brandFocus.dispose();
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  /// Flattens the category tree so subcategories are selectable too, each
  /// with the name of the category it sits under.
  List<(Category, String?)> _flatten(
    List<Category> categories, [
    String? parent,
  ]) {
    final result = <(Category, String?)>[];
    for (final category in categories) {
      result.add((category, parent));
      result.addAll(_flatten(category.children, category.name));
    }
    return result;
  }

  /// A sheet like every other choice in the app, not a drop-down menu.
  Future<void> _pickCategory(List<(Category, String?)> flat) async {
    final picked = await AppDialogs.bottomSheet<(Category, String?)>(
      context,
      builder: (_) => OptionSheet<(Category, String?)>(
        title: context.l10n.category,
        options: flat,
        current: flat.where((entry) => entry.$1.id == _categoryId).firstOrNull,
        labelOf: (entry) => entry.$1.name,
        subtitleOf: (entry) => entry.$2,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _categoryId = picked.$1.id;
      _categoryName = picked.$1.name;
      _categoryMissing = false;
    });
  }

  /// What the brand box asks of the save: unchanged keeps the product's own,
  /// empty takes it off, a brand picked from the list goes by its id, and
  /// any other name by the name.
  ({String? id, String? name, bool clear}) _brandChoice() {
    final typed = _brand.text.trim();
    if (typed == _brandShown) return (id: null, name: null, clear: false);
    if (typed.isEmpty) return (id: null, name: null, clear: true);
    final language = Localizations.localeOf(context).languageCode;
    if (_pickedBrand case final picked? when picked.nameIn(language) == typed) {
      return (id: picked.id, name: null, clear: false);
    }
    return (id: null, name: typed, clear: false);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _failure = null);

    // Said on the field, beside the other errors, rather than in a snackbar
    // that is gone before the merchant has found which field it meant.
    final fieldsValid = _formKey.currentState?.validateAndReveal() ?? false;
    setState(() => _categoryMissing = _categoryId == null);
    if (_categoryMissing || !fieldsValid) return;

    // `uploadedMedia` returns only the finished items, so saving mid-upload
    // created the product with whatever happened to have landed — no warning,
    // no failure, just fewer pictures than the merchant is looking at.
    final images = ref.read(mediaUploadProvider(_imageSlot).notifier);
    if (images.isUploading) {
      AppSnackBar.info(context, context.l10n.waitForUploads);
      return;
    }

    setState(() => _isSubmitting = true);

    final brand = _brandChoice();
    final draft = ProductDraft(
      id: widget.existing?.id,
      name: _name.text.trim(),
      nameAr: _nameAr.text.trim(),
      description: _optional(_description),
      categoryId: _categoryId!,
      brandId: brand.id,
      brandName: brand.name,
      clearBrand: brand.clear,
      price: Formatters.typedNumber(_price.text) ?? 0,
      originalPrice: Formatters.typedNumber(_originalPrice.text),
      stock: Formatters.typedWholeNumber(_stock.text) ?? 0,
      stockBefore: _stockBefore,
      warranty: _optional(_warranty),
      imageUrls: <String>[
        for (final media
            in ref.read(mediaUploadProvider(_imageSlot).notifier).uploadedMedia)
          media.url,
      ],
      variants: _variants,
    );

    final result = await ref
        .read(merchantRepositoryProvider)
        .saveProduct(draft);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    result.fold(
      ok: (_) {
        // Everything that counts the shelf, not only the shelf: the filter
        // pills, the dashboard's to-do list and the stock page read it too.
        ref
          ..invalidate(merchantProductsProvider)
          ..invalidate(merchantProductCountsProvider)
          ..invalidate(merchantDashboardProvider)
          ..invalidate(merchantInventoryProvider);
        AppSnackBar.success(context, context.l10n.productSaved);
        // To the shelf, not back to a form still holding what was just
        // saved: a second tap on Save made a second identical product.
        context.go(AppRoutes.merchantProducts);
      },
      err: (failure) {
        // The stock moved while the form was open (an order, or the stock
        // page): nothing was saved. Said, and the product read again, so
        // the form shows what is there now.
        if (failure is ConflictFailure && widget.existing != null) {
          AppSnackBar.failure(context, failure);
          setState(() => _loading = true);
          _load(widget.existing!.id);
          return;
        }
        setState(() => _failure = failure);
        // A refusal on a field this form draws is shown on it; one on
        // something else - the photos, the options - had nowhere to show,
        // and the save failed without a word (M3, against the real server).
        final elsewhere = failure.fieldErrors
            .where((error) => !_fieldsShown.contains(error.field))
            .firstOrNull;
        if (failure.fieldErrors.isEmpty) {
          AppSnackBar.failure(context, failure);
        } else {
          _formKey.currentState?.validateAndReveal();
          if (elsewhere != null) AppSnackBar.error(context, elsewhere.message);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final categories = ref.watch(categoryTreeProvider);
    final market = context.market;
    // One colour per section: the theme's ink on its own soft fill.
    final blue = (market.info, market.infoSoft);
    final green = (market.success, market.successSoft);
    final purple = (market.accent, market.accentSoft);
    final amber = (market.warning, market.warningSoft);
    return Scaffold(
      appBar: SabaAppBar(
        // A form is a flow you are inside, so it closes rather than going
        // back — which is what the design draws on every product frame.
        leadingIcon: SabaIcons.close,
        title: _isEditing ? l10n.editProduct : l10n.addProduct,
        backFallback: AppRoutes.merchantProducts,
      ),
      // The product is fetched before the form is drawn. The variant editor
      // reads its starting rows once, and a field that fills itself under
      // someone mid-sentence is worse than a short wait.
      body: SafeArea(
        child: _loading
            ? const ListSkeleton(itemHeight: 72)
            : _loadFailure != null
            ? AppErrorView(
                failure: _loadFailure!,
                onRetry: () {
                  setState(() {
                    _loadFailure = null;
                    _loading = true;
                  });
                  _load(widget.existing!.id);
                },
              )
            : ContentContainer(
                maxWidth: 720,
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.screenGutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Fixing a rejected product without Saba's reason
                        // in front of you is fixing it blind.
                        if (widget.existing case final row?
                            when row.isRejected &&
                                (row.rejectionReason ?? '').isNotEmpty) ...[
                          _RejectionNote(reason: row.rejectionReason!),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        // Saba approved what shoppers read; changing it
                        // takes the product off the shop until Saba looks
                        // again (backend 2af9579). Said before, not after.
                        if (widget.existing?.isApproved ?? false) ...[
                          const _ReviewNote(),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        _FormSection(
                          icon: SabaIcons.pencil,
                          title: l10n.productBasics,
                          tint: blue,
                          children: [
                            AppTextField(
                              label: l10n.nameInArabic,
                              hint: context.exampleOf(
                                context.l10n.exProductNameAr,
                              ),
                              controller: _nameAr,
                              isRequired: true,
                              // The English interface lays a field out left
                              // to right, so an Arabic name started off the
                              // wrong edge and its first word was cut off.
                              textDirection: TextDirection.rtl,
                              textInputAction: TextInputAction.next,
                              serverError: _failure?.messageForField('nameAr'),
                              validator: (value) =>
                                  Validators.arabicName(value, l10n),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            AppTextField(
                              label: l10n.nameInEnglish,
                              hint: context.exampleOf(
                                context.l10n.exProductNameEn,
                              ),
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              serverError: _failure?.messageForField('name'),
                              validator: (value) =>
                                  Validators.optionalMinLength(value, 3, l10n),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            // This used to open blank on edit, because the screen only
                            // had the list row, so "blank means leave it alone" was the
                            // best it could do — and a merchant could not then clear a
                            // description at all. The form now arrives holding the real
                            // one, so the field is what it looks like: required, showing
                            // what is there, and editable.
                            AppTextField(
                              label: l10n.description,
                              hint: context.exampleOf(
                                context.l10n.exProductDescription,
                              ),
                              controller: _description,
                              isRequired: true,
                              maxLines: 5,
                              maxLength: 5000,
                              serverError: _failure?.messageForField(
                                'description',
                              ),
                              validator: (value) =>
                                  Validators.minLength(value, 10, l10n),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            categories.when(
                              data: (tree) {
                                final flat = _flatten(tree);
                                final chosen = flat
                                    .where(
                                      (entry) => entry.$1.id == _categoryId,
                                    )
                                    .firstOrNull;
                                return PickerField(
                                  label: l10n.category,
                                  // A category Saba hid since is not in the
                                  // tree; the product keeps it, and says so.
                                  value: chosen?.$1.name ?? _categoryName,
                                  hint: l10n.selectCategory,
                                  errorText: _categoryMissing
                                      ? l10n.selectCategory
                                      : _failure?.messageForField('categoryId'),
                                  onTap: () => _pickCategory(flat),
                                );
                              },
                              loading: () => const LinearProgressIndicator(),
                              error: (_, _) => Text(
                                l10n.errorGeneric,
                                style: context.textStyles.bodySmall,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _BrandField(
                              controller: _brand,
                              focusNode: _brandFocus,
                              brands:
                                  ref.watch(merchantBrandsProvider).value ??
                                  const <Brand>[],
                              onPicked: (brand) => _pickedBrand = brand,
                              serverError:
                                  _failure?.messageForField('brandName') ??
                                  _failure?.messageForField('brandId'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _FormSection(
                          icon: SabaIcons.coin,
                          title: l10n.priceAndStock,
                          tint: green,
                          // One column, as the rest of the form. The two
                          // prices sat side by side at half width, and Stock
                          // under them at full width: two widths, no reason.
                          children: [
                            AppTextField(
                              label: l10n.price,
                              hint: context.exampleOf(12500),
                              helper: l10n.priceStepHint,
                              controller: _price,
                              isRequired: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              serverError: _failure?.messageForField('price'),
                              validator: (value) =>
                                  Validators.cashPrice(value, l10n),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            AppTextField(
                              label: l10n.originalPrice,
                              hint: context.exampleOf(15000),
                              controller: _originalPrice,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              serverError: _failure?.messageForField(
                                'originalPrice',
                              ),
                              validator: (value) =>
                                  Validators.optionalCashPrice(value, l10n),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            // A product with options has no stock of its
                            // own: each option carries its own count, and the
                            // product's is their sum. Two boxes that
                            // disagreed - 12 here, 5/4/3 below - is how the
                            // shelf and the page came apart.
                            if (_variants.isEmpty)
                              AppTextField(
                                label: l10n.stock,
                                hint: context.exampleOf(12),
                                controller: _stock,
                                isRequired: true,
                                keyboardType: TextInputType.number,
                                serverError: _failure?.messageForField('stock'),
                                validator: (value) =>
                                    Validators.number(value, l10n),
                              )
                            else
                              Text(
                                l10n.stockIsPerOption,
                                style: context.textStyles.labelSmall,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _FormSection(
                          icon: SabaIcons.shield,
                          title: l10n.productPolicies,
                          tint: amber,
                          children: [
                            AppTextField(
                              label: l10n.warranty,
                              hint: context.exampleOf(context.l10n.exWarranty),
                              controller: _warranty,
                              maxLines: 2,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            // One rule for every store, so not a field.
                            Text(
                              l10n.returnRuleStore,
                              style: context.textStyles.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _FormSection(
                          icon: SabaIcons.camera,
                          title: l10n.productImages,
                          tint: purple,
                          children: [
                            Text(
                              l10n.productImagesHint,
                              style: context.textStyles.labelSmall,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            MediaUploadField(
                              slot: _imageSlot,
                              label: l10n.productImages,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _FormSection(
                          icon: SabaIcons.sliders,
                          title: l10n.variants,
                          tint: blue,
                          children: [
                            VariantMatrixEditor(
                              // It showed an empty matrix for a product that has
                              // variants, so the merchant either left it alone or
                              // rebuilt it from memory.
                              initial: _initialVariants,
                              onChanged: (variants) =>
                                  setState(() => _variants = variants),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        // One button that says what it does, and one line
                        // saying what happens next. It used to read "Save
                        // draft" with "Pending approval" under it: two
                        // different answers to "what am I about to do".
                        AppButton(
                          label: _isEditing
                              ? l10n.saveChanges
                              : l10n.sendForApproval,
                          isLoading: _isSubmitting,
                          onPressed: _submit,
                        ),
                        if (!_isEditing) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            l10n.sendForApprovalHint,
                            textAlign: TextAlign.center,
                            style: context.textStyles.labelSmall,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The brand, typed or picked (the admin's brands page): as the store types,
/// the brands whose name holds it, in either language. A name not on the
/// list is sent as typed, and Saba checks it with the product.
class _BrandField extends StatelessWidget {
  const _BrandField({
    required this.controller,
    required this.focusNode,
    required this.brands,
    required this.onPicked,
    this.serverError,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<Brand> brands;
  final ValueChanged<Brand> onPicked;
  final String? serverError;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;

    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<Brand>(
        textEditingController: controller,
        focusNode: focusNode,
        displayStringForOption: (brand) => brand.nameIn(language),
        optionsBuilder: (value) {
          final typed = value.text.trim().toLowerCase();
          if (typed.isEmpty) return const <Brand>[];
          return brands.where(
            (brand) =>
                brand.name.toLowerCase().contains(typed) ||
                (brand.nameAr?.toLowerCase().contains(typed) ?? false),
          );
        },
        onSelected: onPicked,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
            AppTextField(
              label: l10n.brand,
              controller: controller,
              focusNode: focusNode,
              hint: l10n.brandHint,
              helper: l10n.brandHelp,
              serverError: serverError,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => onSubmitted(),
            ),
        // As wide as the box, under it.
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(AppRadius.card),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 240,
                maxWidth: constraints.maxWidth,
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final brand in options)
                    ListTile(
                      title: Text(brand.nameIn(language)),
                      onTap: () => onSelected(brand),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One titled card of the form, with its own colour, so a long form reads as
/// six short ones instead of one grey column of eighteen fields.
class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.icon,
    required this.title,
    required this.tint,
    required this.children,
  });

  final String icon;
  final String title;

  /// `(ink, fill)` for the icon tile.
  final (Color, Color) tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: market.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.$2,
                  borderRadius: BorderRadius.circular(AppRadius.xs + 2),
                ),
                child: SabaIcon(
                  icon,
                  size: AppSizes.iconSm + 2,
                  color: tint.$1,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.subsectionTitle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ],
      ),
    );
  }
}

/// Saba's reason for sending a product back, above the form that fixes it.
/// What sends an approved product back to Saba, and what does not.
class _ReviewNote extends StatelessWidget {
  const _ReviewNote();

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: market.infoSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SabaIcon(SabaIcons.info, size: AppSizes.iconMd, color: market.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              context.l10n.editApprovedNote,
              style: context.textStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectionNote extends StatelessWidget {
  const _RejectionNote({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = context.colors.error;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.market.errorSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SabaIcon(SabaIcons.alert, size: AppSizes.iconMd, color: error),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.sabaSaidNo,
                  style: context.textStyles.titleSmall?.copyWith(color: error),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${l10n.rejectionReason}: $reason',
                  style: context.textStyles.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.fixAndResend, style: context.textStyles.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The store's product with this id, opened in the form: where its
/// "approved" or "not approved" notification leads. The form opened only
/// from the products list, which hands it the row.
final _storeProductRowProvider = FutureProvider.autoDispose
    .family<MerchantProductRow?, String>((ref, id) async {
      final shelf = ref.watch(merchantRepositoryProvider);
      for (var page = 1; ; page++) {
        final list = (await shelf.products(page: page)).unwrap();
        for (final row in list.items) {
          if (row.id == id) return row;
        }
        if (!list.hasNextPage) return null;
      }
    });

class MerchantProductByIdScreen extends ConsumerWidget {
  const MerchantProductByIdScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = ref.watch(_storeProductRowProvider(productId));
    if (row.value case final found?) {
      return MerchantProductFormScreen(existing: found);
    }
    final l10n = context.l10n;
    return Scaffold(
      appBar: SabaAppBar(title: l10n.editProduct),
      body: row.hasValue
          // Deleted since the notification was sent.
          ? NoResultsView(
              icon: SabaIcons.box,
              title: l10n.productNotFound,
              message: l10n.productNotFoundMessage,
            )
          : AsyncStateView<MerchantProductRow?>(
              value: row,
              onRetry: () =>
                  ref.invalidate(_storeProductRowProvider(productId)),
              builder: (_) => const SizedBox.shrink(),
            ),
    );
  }
}
