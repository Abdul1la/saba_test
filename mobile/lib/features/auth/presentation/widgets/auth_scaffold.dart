import 'package:flutter/material.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/saba_icons.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/search_pill.dart';

/// Shared chrome for every authentication screen: a back button, a title block
/// and a scrollable, keyboard-safe, width-capped body.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.showBackButton = true,
    this.bottom,
    this.logo,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBackButton;

  /// Pinned below the scroll area, for "already have an account?" style rows.
  final Widget? bottom;

  /// Above the title, at the start edge like the title and the fields: the
  /// one thing centred over words at the start looked unfinished (the user).
  final Widget? logo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ContentContainer(
          child: Column(
            children: [
              // This was a Material AppBar carrying nothing but a back
              // arrow: a full bar's worth of height, Material's own arrow,
              // and a title slot that every auth screen left empty while
              // printing its title in the body underneath. The design's
              // round control says the same thing in a row.
              if (showBackButton)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.sm,
                    AppSpacing.screenGutter,
                    0,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: CircleIconButton(
                      icon: context.isRtl
                          ? SabaIcons.chevronRight
                          : SabaIcons.chevronLeft,
                      tooltip: context.l10n.back,
                      onPressed: () => context.popOrGo(),
                    ),
                  ),
                )
              else
                const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.sm,
                    AppSpacing.screenGutter,
                    AppSpacing.xxxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (logo != null) ...[
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: logo,
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                      Text(title, style: AppTypography.screenTitle(context)),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(subtitle!, style: context.textStyles.bodyMedium),
                      ],
                      const SizedBox(height: AppSpacing.xxl),
                      ...children,
                    ],
                  ),
                ),
              ),
              // Hidden while the keyboard is up. Pinned to the bottom of a
              // shrinking body, "Create account" came to rest on top of
              // "Forgot password?" the moment anyone typed - two tappable
              // things in the same place, one of them unreadable.
              if (bottom != null && MediaQuery.viewInsetsOf(context).bottom < 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    0,
                    AppSpacing.screenGutter,
                    AppSpacing.lg,
                  ),
                  child: bottom,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Already have an account? Sign in", "Open a store on Saba" and their
/// kind, at the foot of a sign-in or sign-up screen: centred, with room
/// above to set it apart from the form, and the link large enough to read
/// and to tap. It was small grey text at the start edge, an afterthought
/// (the user).
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.prompt,
  });

  /// The question before the link, when there is one.
  final String? prompt;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      // The full width, so it centres whatever the form around it aligns to.
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prompt case final prompt?)
              Text(
                prompt,
                textAlign: TextAlign.center,
                style: context.textStyles.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                foregroundColor: context.market.accent,
                minimumSize: const Size(
                  AppSizes.minTapTarget * 2,
                  AppSizes.minTapTarget,
                ),
                textStyle: context.textStyles.titleSmall?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
