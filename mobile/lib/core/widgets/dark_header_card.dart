import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// Turns a header card white and everything printed on it dark, as every
/// header in the app now is, shopper and merchant - the product owner's
/// choice, first made for Home.
///
/// It wraps the widget that *builds* the card, not the card: the header
/// screens read their text colours in their own build, above the card, and
/// only an ancestor's theme reaches those.
class WhiteHeader extends StatelessWidget {
  const WhiteHeader({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final market = context.market;

    return Theme(
      data: theme.copyWith(
        // Keyed by type, so this replaces the colours the theme carries, or
        // adds them where it carries none.
        extensions:
            (Map.of(theme.extensions)
                  ..[MarketplaceColors] = market.copyWith(
                    surfaceDark: theme.colorScheme.surface,
                    onDark: theme.colorScheme.onSurface,
                    // Secondary text, not the muted grey: the email and the
                    // dates under a title are read, not glanced at.
                    onDarkMuted: theme.colorScheme.onSurfaceVariant,
                    onDarkFill: market.surfaceMuted,
                    onDarkRaised: theme.scaffoldBackgroundColor,
                    onDarkBorder: market.border,
                  ))
                .values,
      ),
      child: child,
    );
  }
}

/// `card/header-dark` — the dark block at the top of Home and the other
/// landing screens.
///
/// Three things make it what it is:
///
/// * **It owns the status bar.** The card runs to the very top edge of the
///   screen, so the top inset is padding inside the card, not a gap above it.
/// * **It never stays dark on a dark page.** In dark mode it becomes the
///   *lightest* surface with a hairline border. Both directions come from the
///   [MarketplaceColors.surfaceDark] token, so nothing here branches on
///   brightness.
/// * **The status bar icons follow the card**: light on the dark card, dark
///   where a screen draws the card white (all do now, through [WhiteHeader]).
class DarkHeaderCard extends StatelessWidget {
  const DarkHeaderCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final isDarkCard =
        ThemeData.estimateBrightnessForColor(market.surfaceDark) ==
        Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (isDarkCard ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          MediaQuery.paddingOf(context).top + AppSpacing.lg,
          AppSpacing.screenGutter,
          AppSpacing.xl,
        ),
        decoration: BoxDecoration(
          color: market.surfaceDark,
          // Transparent in light mode, where being darker than the page is
          // separation enough. Uniform rather than bottom-only because a
          // rounded box cannot paint a one-sided border.
          border: Border.all(color: market.onDarkBorder),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppRadius.sheet),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// The greeting line on a [DarkHeaderCard]: avatar, "Welcome back", the name,
/// then the card's own actions.
class DarkHeaderGreeting extends StatelessWidget {
  const DarkHeaderGreeting({
    super.key,
    required this.label,
    required this.name,
    this.actions = const [],
    this.nameStyle,
    this.shrinkToFit = false,
    this.leading,
  });

  final String label;
  final String name;

  /// In place of the initial's circle: Home puts the logo's mark there.
  final Widget? leading;
  final List<Widget> actions;

  /// The name's style; the card's own when not given. Home passes its
  /// heading font. The colour is always the card's: a style made outside the
  /// card does not know the card has its own theme (white on Home).
  final TextStyle? nameStyle;

  /// Shrinks the two lines to fit instead of cutting them off with "...".
  /// Home asks for it: with three icons beside it and a larger name, a small
  /// phone had room for "Ami..." and nothing more.
  final bool shrinkToFit;

  /// The initial shown when there is no avatar image.
  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    Widget fit(Widget line) => shrinkToFit
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: line,
          )
        : line;

    final lead =
        leading ??
        Container(
          width: AppSizes.iconCircle,
          height: AppSizes.iconCircle,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: market.onDarkFill,
            shape: BoxShape.circle,
          ),
          child: Text(
            _initial,
            style: context.textStyles.titleMedium?.copyWith(
              color: market.onDark,
              fontSize: 15,
            ),
          ),
        );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fit(
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.labelSmall?.copyWith(
              color: market.onDarkMuted,
            ),
          ),
        ),
        const SizedBox(height: 2),
        // The name wraps to a second line rather than shrink: at 320
        // px and the largest text it scaled down to a whisper (the
        // tester). Home cuts a name at 24 letters, so two lines hold it.
        Text(
          name,
          maxLines: shrinkToFit ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style:
              nameStyle?.copyWith(color: market.onDark) ??
              context.textStyles.titleMedium?.copyWith(
                color: market.onDark,
                fontSize: 15,
              ),
        ),
      ],
    );

    // Beside the icons when there is room for the name; under them when
    // there is not. At 320 px and the largest text three icons left the
    // name about 48 px, and it shrank to a whisper (the tester).
    return LayoutBuilder(
      builder: (context, box) {
        final room =
            box.maxWidth -
            AppSizes.iconCircle -
            AppSpacing.md -
            actions.length * (AppSizes.minTapTarget + AppSpacing.sm);
        final icons = [
          for (final action in actions) ...[
            const SizedBox(width: AppSpacing.sm),
            action,
          ],
        ];
        if (!shrinkToFit ||
            room >= MediaQuery.textScalerOf(context).scale(130)) {
          return Row(
            children: [
              lead,
              const SizedBox(width: AppSpacing.md),
              Expanded(child: texts),
              ...icons,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [lead, const Spacer(), ...icons]),
            const SizedBox(height: AppSpacing.sm),
            texts,
          ],
        );
      },
    );
  }
}

/// A round icon button that sits on a [DarkHeaderCard].
///
/// 40 visible, 48 tappable, with an optional unread dot ringed in the card
/// colour so it reads as separate from the icon rather than part of it.
class DarkIconButton extends StatelessWidget {
  const DarkIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.showDot = false,
  });

  final String icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkResponse(
          onTap: onPressed,
          radius: AppSizes.minTapTarget / 2,
          child: SizedBox(
            width: AppSizes.minTapTarget,
            height: AppSizes.minTapTarget,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: market.onDarkFill,
                      shape: BoxShape.circle,
                    ),
                    child: SabaIcon(icon, color: market.onDark),
                  ),
                  if (showDot)
                    PositionedDirectional(
                      top: 6,
                      end: 7,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: market.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: market.surfaceDark,
                            width: 2,
                          ),
                        ),
                      ),
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

/// A card raised on top of a [DarkHeaderCard] — the promo tile.
///
/// Light mode lifts it above the navy card; dark mode drops it below the
/// risen card and adds a hairline. Either way it separates itself.
class OnDarkRaisedCard extends StatelessWidget {
  const OnDarkRaisedCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Material(
      color: market.onDarkRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: market.onDarkBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: child,
        ),
      ),
    );
  }
}

/// Page dots under a carousel inside a [DarkHeaderCard]. The active dot is a
/// short bar, not a bigger circle, so the row keeps its rhythm.
class OnDarkPageDots extends StatelessWidget {
  const OnDarkPageDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var dot = 0; dot < count; dot++)
          AnimatedContainer(
            duration: AppMotion.chipExpand,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: dot == index ? 16 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: dot == index
                  ? market.onDark
                  : market.onDarkMuted.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
