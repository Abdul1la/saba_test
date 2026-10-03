import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_typography.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import 'search_pill.dart';

/// The white block at the top of a results screen: back, the query, filters,
/// and the active filters as chips.
///
/// The design's rule, and the reason this is not a number on a button: *a
/// count tells the customer that something is filtering their results but not
/// what*, and makes them open a sheet to find out. Every active filter is
/// visible and removable where it is visible.
class ResultsHeader extends StatelessWidget {
  const ResultsHeader({
    super.key,
    required this.query,
    required this.onQueryTap,
    required this.onFilters,
    required this.filterCount,
    this.onClear,
    this.hint,
    this.chips = const <Widget>[],
  });

  /// What the customer searched for. Null shows the hint instead.
  final String? query;
  final String? hint;

  final VoidCallback onQueryTap;
  final VoidCallback onFilters;

  /// Clears the query text. Null hides the clear circle.
  final VoidCallback? onClear;

  final int filterCount;

  /// One [ActiveFilterChip] per live filter, plus a "Clear all" at the end.
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final hasQuery = query != null && query!.isNotEmpty;

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
        child: Column(
          children: [
            Row(
              children: [
                CircleIconButton(
                  icon: context.isRtl
                      ? SabaIcons.chevronRight
                      : SabaIcons.chevronLeft,
                  tooltip: context.l10n.back,
                  onPressed: () => context.popOrGo(),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: _QueryPill(
                    query: query,
                    hint: hint ?? context.l10n.searchPlaceholder,
                    onTap: onQueryTap,
                    onClear: hasQuery ? onClear : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                _FilterCircle(count: filterCount, onPressed: onFilters),
              ],
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: chips.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.xs + 3),
                  itemBuilder: (context, index) => chips[index],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QueryPill extends StatelessWidget {
  const _QueryPill({
    required this.query,
    required this.hint,
    required this.onTap,
    required this.onClear,
  });

  final String? query;
  final String hint;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final hasQuery = query != null && query!.isNotEmpty;

    return Semantics(
      button: true,
      label: hasQuery ? query : hint,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
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
                child: Text(
                  hasQuery ? query! : hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    fontWeight: hasQuery ? FontWeight.w500 : null,
                    color: hasQuery
                        ? context.colors.onSurface
                        : context.colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Semantics(
                  button: true,
                  label: context.l10n.clear,
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterCircle extends StatelessWidget {
  const _FilterCircle({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleIconButton(
          icon: SabaIcons.sort,
          tooltip: context.l10n.filters,
          filled: true,
          onPressed: onPressed,
        ),
        if (count > 0)
          PositionedDirectional(
            top: 1,
            end: 1,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: AppSizes.navBadge),
                height: AppSizes.navBadge,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: market.accent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: context.colors.surface, width: 2),
                ),
                child: Text(
                  '$count',
                  style: context.textStyles.labelSmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: market.onAccent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One live filter, with the x that removes it.
class ActiveFilterChip extends StatelessWidget {
  const ActiveFilterChip({
    super.key,
    required this.label,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Semantics(
      label: label,
      child: Container(
        height: 32,
        padding: const EdgeInsetsDirectional.fromSTEB(11, 0, 6, 0),
        decoration: BoxDecoration(
          color: context.colors.primary,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.textStyles.labelMedium?.copyWith(
                fontSize: 11.5,
                color: context.colors.onPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs + 2),
            Semantics(
              button: true,
              label: context.l10n.remove,
              child: InkResponse(
                onTap: onRemove,
                radius: AppSizes.minTapTarget / 2,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: market.onDarkFill,
                    shape: BoxShape.circle,
                  ),
                  child: SabaIcon(
                    SabaIcons.close,
                    size: 10,
                    color: context.colors.onPrimary,
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

/// "Clear all", at the end of the chip row.
class ClearAllChip extends StatelessWidget {
  const ClearAllChip({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.clearAll,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          height: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: context.market.borderStrong),
          ),
          child: Text(
            context.l10n.clearAll,
            style: context.textStyles.labelMedium?.copyWith(
              fontSize: 11.5,
              color: context.colors.error,
            ),
          ),
        ),
      ),
    );
  }
}

/// "68 results" on one side, the current sort on the other.
class ResultsBar extends StatelessWidget {
  const ResultsBar({
    super.key,
    required this.count,
    required this.sortLabel,
    required this.onSort,
  });

  final int? count;
  final String sortLabel;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md + 2,
        AppSpacing.screenGutter,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: count == null
                ? const SizedBox.shrink()
                : Text(
                    // "1 result", "نتيجتان", "11 نتيجةً": the count and its
                    // noun agree. It read "1 results".
                    l10n.counted(count!, CountNoun.result),
                    style: context.textStyles.bodyMedium?.copyWith(
                      fontSize: 13,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Semantics(
            button: true,
            label: sortLabel,
            child: InkWell(
              onTap: onSort,
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xs,
                  horizontal: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SabaIcon(
                      SabaIcons.sortVertical,
                      size: 14,
                      color: context.colors.onSurface,
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      sortLabel,
                      style: context.textStyles.labelLarge?.copyWith(
                        fontSize: 12.5,
                        color: context.colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The floating "Filters · 2" pill.
///
/// It only opens the sheet; it is never the only evidence that filters exist
/// — that is what the chips at the top are for.
class FloatingFilterButton extends StatelessWidget {
  const FloatingFilterButton({
    super.key,
    required this.count,
    required this.onPressed,
  });

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final page = context.theme.scaffoldBackgroundColor;

    return IgnorePointer(
      ignoring: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.md + 2,
          AppSpacing.screenGutter,
          AppSpacing.xl - 4 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [page, page, page.withValues(alpha: 0)],
            stops: const [0, 0.62, 1],
          ),
        ),
        child: Center(
          child: Semantics(
            button: true,
            label: l10n.filters,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                height: AppSizes.navPillActiveHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl - 4,
                ),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (context.isDarkMode
                                  ? Colors.black
                                  : AppPalette.textPrimary)
                              .withValues(alpha: 0.24),
                      blurRadius: AppElevation.floatBlur,
                      offset: const Offset(0, AppElevation.floatOffsetY),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SabaIcon(
                      SabaIcons.sort,
                      size: AppSizes.iconSm,
                      color: context.colors.onPrimary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      count > 0 ? '${l10n.filters} · $count' : l10n.filters,
                      style: context.textStyles.labelLarge?.copyWith(
                        fontSize: 12.5,
                        color: context.colors.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dead end turned into live paths.
///
/// The design's rule: *"The no-results screen names the cause and counts the
/// fix."* When filters are what emptied the list, say so and offer to relax
/// them — a customer who is told "no results" learns nothing and leaves.
class NoResultsView extends StatelessWidget {
  const NoResultsView({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.actions = const <Widget>[],
  });

  final String title;
  final String message;
  final String? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl + 4,
        AppSpacing.xxl2,
        AppSpacing.xl + 4,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: market.surfaceMuted,
                borderRadius: BorderRadius.circular(30),
              ),
              child: SabaIcon(
                icon ?? SabaIcons.zoomOut,
                size: 36,
                color: market.textMuted,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md + 1),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.sectionTitle(context),
          ),
          const SizedBox(height: AppSpacing.md + 1),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.textStyles.bodyMedium?.copyWith(
              fontSize: 14,
              height: 1.55,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl - 5),
            for (var index = 0; index < actions.length; index++) ...[
              if (index > 0) const SizedBox(height: AppSpacing.sm + 1),
              actions[index],
            ],
          ],
        ],
      ),
    );
  }
}
