import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/search_pill.dart';

/// "Step 2 of 4", the step's title and what it asks for.
///
/// Sign-up used to be a stack of screens with no sense of length — you gave a
/// phone number with no idea whether two more questions were coming or ten,
/// which is the moment people abandon. The bar and "Step 2 of 4" answer that
/// before the first field.
class SignUpStepTitle extends StatelessWidget {
  const SignUpStepTitle({
    super.key,
    required this.step,
    required this.total,
    required this.title,
    this.subtitle,
  });

  final int step;
  final int total;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.stepOf(step, total),
          style: context.textStyles.labelSmall?.copyWith(
            color: market.textMuted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(title, style: AppTypography.screenTitle(context)),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle!, style: context.textStyles.bodyMedium),
        ],
      ],
    );
  }
}

/// The top row of every sign-up step: back, how far along, and the language.
///
/// The globe stays on every step because the wrong language is discovered
/// here, in the middle of the form, not on the screen that offered the choice.
class SignUpTopBar extends ConsumerWidget {
  const SignUpTopBar({
    super.key,
    required this.step,
    required this.total,
    this.onBack,
  });

  final int step;
  final int total;

  /// Defaults to popping. A step that lives inside another screen's page view
  /// passes its own, so Back goes to the previous step and not out of sign-up.
  final VoidCallback? onBack;

  Future<void> _toggleLanguage(BuildContext context, WidgetRef ref) async {
    final isArabic = context.isRtl;
    await ref
        .read(localeControllerProvider.notifier)
        .setLocale(Locale(isArabic ? 'en' : 'ar'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        CircleIconButton(
          icon: context.isRtl ? SabaIcons.chevronRight : SabaIcons.chevronLeft,
          tooltip: context.l10n.back,
          onPressed: onBack ?? () => context.popOrGo(),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _Progress(step: step, total: total),
        ),
        const SizedBox(width: AppSpacing.md),
        CircleIconButton(
          icon: SabaIcons.globe,
          tooltip: context.l10n.changeLanguage,
          onPressed: () => _toggleLanguage(context, ref),
        ),
      ],
    );
  }
}

/// One bar per step, filled up to where you are.
///
/// Segments rather than a single sliding bar: a bar at 50% says "halfway",
/// segments say "two of these four questions are behind you", which is the
/// thing someone actually wants to know.
class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Row(
      children: [
        for (var i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: AnimatedContainer(
              duration: AppMotion.chipExpand,
              curve: Curves.easeOut,
              height: 4,
              decoration: BoxDecoration(
                color: i <= step ? market.accent : market.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A sign-up step: the top bar, a scrolling body, and an action pinned to the
/// bottom so the way forward is never scrolled off the screen.
class SignUpStepScaffold extends StatelessWidget {
  const SignUpStepScaffold({
    super.key,
    required this.step,
    required this.total,
    required this.title,
    required this.children,
    required this.action,
    this.subtitle,
    this.onBack,
    this.footer,
    this.centered = false,
    this.leading,
  });

  final int step;
  final int total;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget action;
  final VoidCallback? onBack;
  final Widget? footer;

  /// For a short step - a number, a code. The title, the fields and the
  /// button sit together in the middle of the screen instead of the fields at
  /// the top and the button at the bottom with nothing between. A long form
  /// keeps the default: its button pinned, always in reach while it scrolls.
  final bool centered;

  /// Above everything, in the centered layout: the number step, now the
  /// first screen a new visitor sees, carries the logo there.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final padding = const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.md,
      AppSpacing.xl,
      AppSpacing.lg,
    );

    if (centered) {
      // A short step - a number, a code: the title, the fields and the
      // button together, from the top, the words and the logo at the start
      // of the line like every other step. Centred in the screen, it read as
      // empty and drifting.
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: padding,
            child: Column(
              children: [
                SignUpTopBar(step: step, total: total, onBack: onBack),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xl,
                      bottom: AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (leading != null) ...[
                          leading!,
                          const SizedBox(height: AppSpacing.xl),
                        ],
                        SignUpStepTitle(
                          step: step,
                          total: total,
                          title: title,
                          subtitle: subtitle,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        ...children,
                        // Room between the field and "Send code": at 24 the
                        // button sat against the field (the user).
                        const SizedBox(height: AppSpacing.xxxl + AppSpacing.sm),
                        action,
                        if (footer != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          footer!,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The top bar stays; the title scrolls away with the fields.
              // Pinned, it left the fields of a 320x568 phone a window 64 px
              // tall, and none at all with the keyboard up.
              SignUpTopBar(step: step, total: total, onBack: onBack),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xl,
                    bottom: AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SignUpStepTitle(
                        step: step,
                        total: total,
                        title: title,
                        subtitle: subtitle,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      ...children,
                    ],
                  ),
                ),
              ),
              action,
              // Hidden with the keyboard up, or it lands on top of the action.
              if (footer != null &&
                  MediaQuery.viewInsetsOf(context).bottom < 1) ...[
                const SizedBox(height: AppSpacing.sm),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
