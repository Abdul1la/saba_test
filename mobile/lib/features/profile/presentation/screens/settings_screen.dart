import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/saba_tile.dart';
import '../../../../core/widgets/section_header.dart';

/// Language and appearance.
///
/// Changing the language flips the whole app between LTR and RTL immediately,
/// and the choice also travels to the backend as `Accept-Language` so server
/// messages match (specification sections 15, 17 and 60).
///
/// Both choices are tick-marked rows rather than radio dials, which is how a
/// choice is made everywhere else in the app.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final currentLocale = ref.watch(localeControllerProvider);
    final themeMode = ref.watch(themeControllerProvider);

    void setLocale(Locale? locale) =>
        ref.read(localeControllerProvider.notifier).setLocale(locale);
    void setTheme(ThemeMode mode) =>
        ref.read(themeControllerProvider.notifier).setThemeMode(mode);

    return Scaffold(
      appBar: SabaAppBar(title: l10n.settings),
      body: SafeArea(
        top: false,
        child: ContentContainer(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.xxl,
            ),
            children: [
              TileGroup(
                title: l10n.language,
                tiles: [
                  // Was labelled with the *theme's* "System" string and
                  // subtitled "Language", which read as nonsense in both
                  // languages. It now says what it actually does.
                  ChoiceRow(
                    label: l10n.languageSystem,
                    subtitle: l10n.languageSystemHint,
                    isSelected: currentLocale == null,
                    onTap: () => setLocale(null),
                    padding: _rowPadding,
                  ),
                  for (final locale in AppLocalizations.supportedLocales)
                    ChoiceRow(
                      label: AppLocalizations.displayName(locale),
                      isSelected:
                          currentLocale?.languageCode == locale.languageCode,
                      onTap: () => setLocale(locale),
                      padding: _rowPadding,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md + 2),
              TileGroup(
                title: l10n.theme,
                tiles: [
                  ChoiceRow(
                    label: l10n.themeSystem,
                    isSelected: themeMode == ThemeMode.system,
                    onTap: () => setTheme(ThemeMode.system),
                    padding: _rowPadding,
                  ),
                  ChoiceRow(
                    label: l10n.themeLight,
                    isSelected: themeMode == ThemeMode.light,
                    onTap: () => setTheme(ThemeMode.light),
                    padding: _rowPadding,
                  ),
                  ChoiceRow(
                    label: l10n.themeDark,
                    isSelected: themeMode == ThemeMode.dark,
                    onTap: () => setTheme(ThemeMode.dark),
                    padding: _rowPadding,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Matches [SabaTile]'s own padding so a tick row and a chevron row line up
  /// when they share a card.
  static const EdgeInsets _rowPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.md + 1,
  );
}
