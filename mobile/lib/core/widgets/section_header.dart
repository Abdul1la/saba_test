import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../router/app_routes.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_typography.dart';
import '../theme/saba_icons.dart';
import 'search_pill.dart';
import '../utils/context_extensions.dart';

/// Title row above a section, on every screen: one style for "Categories",
/// "Flash sale", "Featured stores", "All products" and the rest.
///
/// The design separates sections with space, not lines: 32 above the title,
/// 12 below it, and no divider anywhere. The title is set in the heading
/// font; "See all" is a quiet second action at the end of the row and never
/// competes with it.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.badge,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter + AppSpacing.xs,
      AppSpacing.sectionGap,
      AppSpacing.screenGutter + AppSpacing.xs,
      AppSpacing.md,
    ),
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Sits beside the title — the flash-sale countdown is the one user of it.
  final Widget? badge;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Expanded, not Flexible + Spacer: those two split the free space
          // between them and the title lost half its width to empty space.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  // Two lines: the heading was cut off on a small phone at a
                  // large text size.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sectionTitle(context),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle!, style: context.textStyles.bodySmall),
                ],
              ],
            ),
          ),
          if (badge != null) ...[const SizedBox(width: AppSpacing.sm), badge!],
          if (onAction != null)
            SeeAllAction(label: actionLabel, onTap: onAction!),
        ],
      ),
    );
  }
}

/// The header of a *pushed* screen: a back circle, a centred title, and
/// whatever the screen needs on the other side.
///
/// The back chevron flips direction with the writing direction — it points at
/// the edge the customer came from, which in Arabic is the right.
class SabaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SabaAppBar({
    super.key,
    required this.title,
    this.trailing,
    this.backFallback = AppRoutes.home,
    this.leadingIcon,
    this.onLeading,
  });

  final String title;
  final Widget? trailing;

  /// Overrides the back chevron. A flow the reader is *inside* rather than
  /// one they navigated into — paying, or filling a product form — closes
  /// with an X, because "back" in the middle of a payment is a question, not
  /// a direction.
  final String? leadingIcon;

  /// What the leading control does. Defaults to popping, or falling back to
  /// [backFallback]; a flow that must ask before it is abandoned passes its
  /// own confirmation here.
  final VoidCallback? onLeading;

  /// Where back goes when there is no history to pop — a notification tap, a
  /// deep link, a restored session. The default lands on the customer home,
  /// which is wrong for a merchant screen: it drops a seller out of their own
  /// store, so those screens name their own list instead.
  final String backFallback;

  @override
  Size get preferredSize =>
      const Size.fromHeight(AppSizes.minTapTarget + AppSpacing.sm * 2);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (context.isDarkMode
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          MediaQuery.paddingOf(context).top + AppSpacing.sm,
          AppSpacing.screenGutter,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            CircleIconButton(
              icon:
                  leadingIcon ??
                  (context.isRtl
                      ? SabaIcons.chevronRight
                      : SabaIcons.chevronLeft),
              tooltip: context.l10n.back,
              onPressed: onLeading ?? () => context.popOrGo(backFallback),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.barTitle(context),
              ),
            ),
            // Balances the back circle so the title stays centred on the
            // screen rather than on the space left over — but only as a
            // minimum. It used to be a hard 48 wide, which is fine for an
            // icon and ruinous for a word: "Mark all as read" and "Clear all"
            // were handed 32px of usable space and wrapped into an app bar
            // that is a fixed 48 high. A named action gets the room to say
            // its name; the title gives up dead-centre to let it.
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSizes.minTapTarget,
              ),
              child: trailing == null
                  ? const SizedBox(width: AppSizes.minTapTarget)
                  : Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: trailing,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A numbered step header inside a checkout card.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.number,
    required this.title,
    this.action,
  });

  final int number;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: AppSizes.iconLg,
          height: AppSizes.iconLg,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colors.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: context.textStyles.labelLarge?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.colors.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.subsectionTitle(context),
          ),
        ),
        ?action,
      ],
    );
  }
}

/// The big title at the top of a tab screen.
///
/// The design gives these screens a page title rather than an app bar: there
/// is nothing to go back to from a tab, so a bar with a back chevron would be
/// a lie, and a 32px heading tells the customer where they are far faster
/// than a 16px one in a strip. It owns the status bar area itself.
class PageTitle extends StatelessWidget {
  const PageTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;

  /// An action that belongs with the title rather than in a bar.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // A page title screen has no app bar, so nothing else claims the status
    // bar. Without this, arriving from a screen with a dark header card
    // leaves white status icons on a light page, and the clock disappears.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (context.isDarkMode
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          MediaQuery.paddingOf(context).top + AppSpacing.md + 2,
          AppSpacing.screenGutter,
          0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.screenTitle(context)),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle!,
                      style: context.textStyles.bodyLarge?.copyWith(
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.md),
              // Capped, not flexed. A bare child is laid out with unbounded
              // width, and an AppButton - which expands by default - asked
              // for infinite width and threw the screen away. Flexible fixed
              // that but split the free space in half with the title, so the
              // action sat in the middle of the bar instead of at its end.
              // A cap keeps it at the end and never more than half the row.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width / 2,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: trailing!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "See all ›" — the chevron points forward in either writing direction.
class SeeAllAction extends StatelessWidget {
  const SeeAllAction({super.key, this.label, required this.onTap});

  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = label ?? context.l10n.seeAll;

    return Semantics(
      button: true,
      label: text,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Purple like every link; small and without a fill, so it
              // still never competes with the title.
              Text(
                text,
                style: context.textStyles.labelLarge?.copyWith(
                  color: context.colors.primary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              SabaIcon(
                context.isRtl ? SabaIcons.chevronLeft : SabaIcons.chevronRight,
                size: AppSizes.iconSm,
                color: context.colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Constrains page content on tablet and desktop widths so text lines and
/// forms do not stretch across an entire monitor.
class ContentContainer extends StatelessWidget {
  const ContentContainer({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// A titled white card: the unit every detail screen is built from.
///
/// The order, the return and the invoice each had their own private copy of
/// this. One card means a heading is the same size and a border the same
/// colour on all three, and a change lands everywhere at once.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  /// Omitted when the card's content speaks for itself, as the totals do.
  final String? title;

  /// A quiet second action on the title's line.
  final Widget? trailing;

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.market.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  // Two lines: a heading font at the largest text size
                  // needs the room on a small phone.
                  child: Text(
                    title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.subsectionTitle(context),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.md + 2),
          ],
          child,
        ],
      ),
    );
  }
}

/// A label-and-value line inside a [SectionCard].
///
/// Totals, refund figures and invoice sums are all this row. [emphasise] is
/// the grand-total variant: the one number the eye should land on.
class CardLine extends StatelessWidget {
  const CardLine({
    super.key,
    required this.label,
    required this.value,
    this.emphasise = false,
    this.valueColor,
    this.struck = false,
  });

  final String label;
  final String value;
  final bool emphasise;
  final Color? valueColor;

  /// Crossed out: a sum nobody will pay, like a cancelled invoice's total.
  final bool struck;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasise
                  ? context.textStyles.titleMedium?.copyWith(fontSize: 15)
                  : context.textStyles.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      color: context.market.textMuted,
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            value,
            textAlign: TextAlign.end,
            style:
                (emphasise
                        ? context.textStyles.titleLarge?.copyWith(fontSize: 18)
                        : context.textStyles.bodyMedium?.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: valueColor,
                          ))
                    ?.copyWith(
                      decoration: struck ? TextDecoration.lineThrough : null,
                    ),
          ),
        ],
      ),
    );
  }
}

/// A small note under a [SectionCard]'s lines: an info icon and a sentence.
class CardNote extends StatelessWidget {
  const CardNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: SabaIcon(
            SabaIcons.info,
            size: 14,
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.xs + 1),
        Expanded(child: Text(text, style: context.textStyles.bodySmall)),
      ],
    );
  }
}
