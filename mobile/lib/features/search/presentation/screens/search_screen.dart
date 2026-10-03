import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/search_pill.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../catalog/domain/product_query.dart';
import '../../../catalog/presentation/screens/product_list_screen.dart';
import '../search_providers.dart';
import '../../../../core/utils/western_digits_formatter.dart';
import '../../../../core/widgets/saba_nav_bar.dart';

/// Search entry point: history and popular terms before typing, suggestions
/// while typing, and the full result list once submitted.
///
/// The results half is [ProductListScreen], so a search result and a category
/// listing are the same screen with the same header, the same removable
/// filter chips and the same no-results paths.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialTerm});

  final String? initialTerm;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTerm ?? '',
  );
  late final FocusNode _focusNode = FocusNode();

  /// Null until a search is actually submitted, which is what switches the
  /// screen from "suggestions" to "results".
  String? _submittedTerm;

  @override
  void initState() {
    super.initState();
    _submittedTerm = widget.initialTerm?.trim().isEmpty ?? true
        ? null
        : widget.initialTerm!.trim();
    if (_submittedTerm == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;

    _controller.text = trimmed;
    _focusNode.unfocus();

    // Remembered locally so guests also get a history list.
    await ref
        .read(appPreferencesProvider)
        .addRecentSearch(trimmed, account: ref.read(accountIdProvider));
    if (!mounted) return;

    setState(() => _submittedTerm = trimmed);
    ref.invalidate(searchHistoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (_submittedTerm != null) {
      return ProductListScreen(
        title: _submittedTerm,
        initialQuery: ProductQuery(search: _submittedTerm),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          _SearchField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: (value) =>
                ref.read(searchTermProvider.notifier).setTerm(value),
            onSubmitted: _submit,
            onClear: () {
              _controller.clear();
              ref.read(searchTermProvider.notifier).setTerm('');
              _focusNode.requestFocus();
            },
          ),
          Expanded(child: _SuggestionsBody(onSelect: _submit)),
        ],
      ),
    );
  }
}

/// The live field, in the same white block the results header uses, so
/// typing and reading results feel like one screen rather than two.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (context.isDarkMode
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(bottom: BorderSide(color: market.surfaceMuted)),
        ),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          MediaQuery.paddingOf(context).top + AppSpacing.sm,
          AppSpacing.screenGutter,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            CircleIconButton(
              icon: context.isRtl
                  ? SabaIcons.chevronRight
                  : SabaIcons.chevronLeft,
              tooltip: l10n.back,
              onPressed: () => context.popOrGo(),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Container(
                height: AppSizes.iconCircle,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: context.theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  children: [
                    SabaIcon(
                      SabaIcons.search,
                      size: AppSizes.iconSm,
                      color: context.colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm + 1),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        inputFormatters: const [WesternDigitsFormatter()],
                        focusNode: focusNode,
                        textInputAction: TextInputAction.search,
                        autocorrect: false,
                        style: context.textStyles.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: context.colors.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: l10n.searchPlaceholder,
                          filled: false,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: onChanged,
                        onSubmitted: onSubmitted,
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(
                                left: AppSpacing.sm,
                              ),
                              child: Semantics(
                                button: true,
                                label: l10n.clear,
                                child: InkResponse(
                                  onTap: onClear,
                                  radius: AppSizes.minTapTarget / 2,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: market.borderStrong,
                                      shape: BoxShape.circle,
                                    ),
                                    child: SabaIcon(
                                      SabaIcons.close,
                                      size: 11,
                                      color: context.colors.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            CircleIconButton(
              icon: SabaIcons.search,
              tooltip: l10n.search,
              filled: true,
              onPressed: () => onSubmitted(controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionsBody extends ConsumerWidget {
  const _SuggestionsBody({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final term = ref.watch(searchTermProvider);

    if (term.trim().length >= 2) {
      final suggestions = ref.watch(searchSuggestionsProvider(term));
      return suggestions.maybeWhen(
        data: (items) => ListView(
          padding: EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: SabaNavBar.clearance(context),
          ),
          children: [
            for (final suggestion in items)
              _SuggestionRow(
                text: suggestion.text,
                icon: switch (suggestion.type.toUpperCase()) {
                  'CATEGORY' => SabaIcons.grid,
                  'BRAND' => SabaIcons.ticket,
                  'PRODUCT' => SabaIcons.box,
                  _ => SabaIcons.search,
                },
                onTap: () {
                  if (suggestion.productId != null) {
                    context.push(
                      AppRoutes.productDetailPath(suggestion.productId!),
                    );
                    return;
                  }
                  if (suggestion.categoryId != null) {
                    context.push(
                      AppRoutes.categoryProductsPath(suggestion.categoryId!),
                    );
                    return;
                  }
                  onSelect(suggestion.text);
                },
                onFill: () => onSelect(suggestion.text),
              ),
          ],
        ),
        orElse: () => const Center(child: CircularProgressIndicator()),
      );
    }

    final localHistory = ref
        .watch(appPreferencesProvider)
        .recentSearchesOf(ref.watch(accountIdProvider));
    final serverHistory = ref.watch(isAuthenticatedProvider)
        ? ref.watch(searchHistoryProvider).value ?? const <String>[]
        : const <String>[];
    final history = <String>{...serverHistory, ...localHistory}.toList();
    final popular =
        ref.watch(popularSearchesProvider).value ?? const <String>[];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.xl,
        AppSpacing.screenGutter,
        SabaNavBar.clearance(context),
      ),
      children: [
        if (history.isNotEmpty) ...[
          _TermSection(
            title: l10n.recentSearches,
            actionLabel: l10n.clearAll,
            // This deletes the device list *and* the account's history in
            // one tap. It used to do both with no confirmation, while the
            // harmless "Clear all" that only relaxes filters is drawn in red
            // - and it threw the Result away, so a failed delete made the
            // terms quietly reappear with nothing said.
            onAction: () async {
              final confirmed = await AppDialogs.confirm(
                context,
                title: l10n.clearHistoryTitle,
                message: l10n.clearHistoryMessage,
                confirmLabel: l10n.clearAll,
                isDestructive: true,
              );
              if (!confirmed || !context.mounted) return;

              await ref
                  .read(appPreferencesProvider)
                  .clearRecentSearches(account: ref.read(accountIdProvider));
              final result = await ref
                  .read(searchRepositoryProvider)
                  .clearHistory();
              if (!context.mounted) return;
              ref.invalidate(searchHistoryProvider);
              result.fold(
                ok: (_) {},
                err: (failure) => AppSnackBar.failure(context, failure),
              );
            },
            terms: history,
            icon: SabaIcons.clock,
            onSelect: onSelect,
          ),
          const SizedBox(height: AppSpacing.sectionGap),
        ],
        if (popular.isNotEmpty)
          _TermSection(
            title: l10n.popularSearches,
            terms: popular,
            icon: SabaIcons.flame,
            onSelect: onSelect,
          ),
      ],
    );
  }
}

/// Past or popular terms as a wrap of pills.
///
/// Pills rather than list rows: a search term is two or three words, and a
/// full-width row per word wastes the screen the customer is about to fill
/// with results.
class _TermSection extends StatelessWidget {
  const _TermSection({
    required this.title,
    required this.terms,
    required this.icon,
    required this.onSelect,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final List<String> terms;
  final String icon;
  final ValueChanged<String> onSelect;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: AppTypography.subsectionTitle(context)),
            ),
            if (onAction != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: context.colors.onSurfaceVariant,
                ),
                child: Text(actionLabel ?? ''),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm + 1,
          runSpacing: AppSpacing.sm + 1,
          children: [
            for (final term in terms)
              _TermPill(term: term, icon: icon, onTap: () => onSelect(term)),
          ],
        ),
      ],
    );
  }
}

class _TermPill extends StatelessWidget {
  const _TermPill({
    required this.term,
    required this.icon,
    required this.onTap,
  });

  final String term;
  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: term,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          height: AppSizes.filterChipHeight - 4,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: context.market.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SabaIcon(icon, size: 13, color: context.colors.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm - 1),
              Text(
                term,
                style: context.textStyles.labelLarge?.copyWith(
                  fontSize: 12.5,
                  color: context.colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A suggestion while typing: tap the row to go, tap the arrow to put the
/// term in the field and keep editing it.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.text,
    required this.icon,
    required this.onTap,
    required this.onFill,
  });

  final String text;
  final String icon;
  final VoidCallback onTap;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            SabaIcon(
              icon,
              size: AppSizes.iconMd,
              color: context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.bodyMedium,
              ),
            ),
            Semantics(
              button: true,
              label: text,
              child: InkResponse(
                onTap: onFill,
                radius: AppSizes.minTapTarget / 2,
                child: SizedBox(
                  width: AppSizes.minTapTarget,
                  height: AppSizes.minTapTarget,
                  child: Center(
                    child: Transform.flip(
                      flipX: context.isRtl,
                      child: SabaIcon(
                        SabaIcons.arrowUp,
                        size: AppSizes.iconSm,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
