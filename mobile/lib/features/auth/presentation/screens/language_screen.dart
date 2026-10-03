import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/saba_logo.dart';
import '../auth_providers.dart';

/// First launch, straight after the splash, and the only thing it asks.
///
/// Each option is written in **both** scripts — العربية / Arabic — so neither
/// speaker has to recognise a foreign word to find their own. Everything
/// after this point compiles for the tap.
///
/// There is no skip. A wrong guess here costs a reader the whole app, and
/// picking is one tap; the choice is not permanent either, which is what the
/// line at the bottom says.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    Locale locale,
  ) async {
    await ref.read(localeControllerProvider.notifier).setLocale(locale);
    // Once this is set the redirect stops sending anyone here.
    await ref.read(appPreferencesProvider).setOnboardingSeen(true);
    if (!context.mounted) return;

    // Someone already signed in - a reinstall with a live session, or this
    // screen reached from Account - goes back to the app instead of being
    // asked to sign in.
    final isAuthenticated =
        ref.read(authControllerProvider).value?.isAuthenticated ?? false;
    // A first launch goes on to sign in, with "Create an account" under it:
    // it went straight into sign-up, and someone who already had an account
    // had to find their way out of it (the user).
    context.go(isAuthenticated ? AppRoutes.home : AppRoutes.login);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.colors;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (context.isDarkMode
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: colors.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 3),
                _Wordmark(tagline: l10n.sabaTagline),
                const Spacer(flex: 2),
                Text(
                  // Both scripts in the heading too: at this moment the app
                  // does not yet know which one the reader is looking for.
                  '${l10n.chooseYourLanguage} · اختر لغتك',
                  // Centred, all of this screen: the "start edge" rule was
                  // for the sign-in screens, not this one (the user).
                  textAlign: TextAlign.center,
                  style: context.textStyles.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: AppSpacing.md + 2),
                Row(
                  children: [
                    Expanded(
                      child: _LanguageButton(
                        name: l10n.arabicName,
                        other: l10n.arabicOther,
                        onTap: () => _choose(context, ref, const Locale('ar')),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _LanguageButton(
                        name: l10n.englishName,
                        other: l10n.englishOther,
                        onTap: () => _choose(context, ref, const Locale('en')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md + 2),
                Text(
                  l10n.changeLanguageLater,
                  textAlign: TextAlign.center,
                  style: context.textStyles.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.tagline});

  final String tagline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Before a language is chosen, so the mark with both names rather
        // than one language's lockup.
        Center(
          child: SabaMark(
            size: 76,
            tone: context.isDarkMode ? SabaMarkTone.white : SabaMarkTone.purple,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Saba',
                style: TextStyle(
                  fontFamily: AppTypography.headingFamily,
                  fontSize: 26,
                ),
              ),
              const TextSpan(text: '  ·  '),
              const TextSpan(
                text: 'سبأ',
                style: TextStyle(
                  fontFamily: AppTypography.family,
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                ),
              ),
            ],
          ),
          style: TextStyle(
            height: 1.2,
            color: context.isDarkMode ? colors.onSurface : AppPalette.brand,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        // Centred with the name above it: part of the logo, not a paragraph.
        Text(
          tagline,
          textAlign: TextAlign.center,
          style: context.textStyles.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.name,
    required this.other,
    required this.onTap,
  });

  final String name;
  final String other;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadius.action);

    // Two equal answers, so neither is the screen's one filled button:
    // both are the second level, purple words and outline on white.
    return Semantics(
      button: true,
      label: '$name $other',
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.primary, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: 58,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: context.textStyles.titleSmall?.copyWith(
                    color: colors.primary,
                    fontSize: 15,
                  ),
                ),
                Text(
                  other,
                  style: context.textStyles.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
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
