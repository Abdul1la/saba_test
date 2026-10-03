import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_typography.dart';

/// Builds the light and dark themes from the Saba design system.
///
/// Every visual decision lives here, so screens contain layout and behaviour
/// only — no inline colours, no hard-coded text styles. Changing a token in
/// `app_colors.dart` or `app_dimensions.dart` changes all 47 screens at once.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final market = isLight ? MarketplaceColors.light : MarketplaceColors.dark;

    // Built from the tokens rather than seeded from a hue: a generated tonal
    // palette would spread the purple into a dozen tints nobody asked for.
    // Every slot a Material widget might read is filled, so none of them
    // falls back to a colour of Material's own.
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: isLight ? AppPalette.primary : AppPalette.darkPrimary,
      onPrimary: isLight ? AppPalette.onPrimary : AppPalette.darkOnPrimary,
      primaryContainer: market.accentSoft,
      onPrimaryContainer: isLight
          ? AppPalette.textPrimary
          : AppPalette.darkTextPrimary,
      secondary: market.accent,
      onSecondary: market.onAccent,
      secondaryContainer: market.selected,
      onSecondaryContainer: isLight
          ? AppPalette.textPrimary
          : AppPalette.darkTextPrimary,
      tertiary: market.heat,
      onTertiary: market.onHeat,
      tertiaryContainer: market.heatSoft,
      onTertiaryContainer: isLight
          ? AppPalette.textPrimary
          : AppPalette.darkTextPrimary,
      error: isLight ? AppPalette.error : AppPalette.darkError,
      onError: isLight ? AppPalette.onPrimary : AppPalette.darkOnPrimary,
      surface: isLight ? AppPalette.surface : AppPalette.darkSurface,
      onSurface: isLight ? AppPalette.textPrimary : AppPalette.darkTextPrimary,
      surfaceContainerLowest: isLight
          ? AppPalette.surface
          : AppPalette.darkSurface,
      surfaceContainerHighest: market.surfaceMuted,
      onSurfaceVariant: isLight
          ? AppPalette.textSecondary
          : AppPalette.darkTextSecondary,
      outline: market.border,
      outlineVariant: market.borderStrong,
      scrim: market.scrim,
      inverseSurface: market.surfaceDark,
      onInverseSurface: market.onDark,
    );

    final textTheme = AppTypography.textTheme(
      colorScheme.onSurface,
      colorScheme.onSurfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: AppTypography.family,
      scaffoldBackgroundColor: isLight
          ? AppPalette.bgPage
          : AppPalette.darkBgPage,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[
        market,
        MarketplaceTextStyles(price: AppTypography.price(market.price)),
      ],
      visualDensity: VisualDensity.adaptivePlatformDensity,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? AppPalette.bgPage : AppPalette.darkBgPage,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),

      // Separation is space first, then a soft fill, then a 1px border. A card
      // carries a border only because it must hold its edge against a
      // same-colour page.
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: market.border),
        ),
      ),

      // Off is a solid grey track with a white thumb, and on is the brand
      // colour. Material's outlined off track read as switched off and
      // greyed out at once, a control nobody could use (BUGS.md 22).
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : market.borderStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      dividerTheme: DividerThemeData(
        color: market.border,
        thickness: 1,
        space: 1,
      ),

      // Filled, not outlined, at rest. The border appears only on focus and on
      // error, so an errored field is visible from across the screen.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: market.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: _inputBorder(Colors.transparent),
        enabledBorder: _inputBorder(Colors.transparent),
        focusedBorder: _inputBorder(colorScheme.primary, width: 1.5),
        errorBorder: _inputBorder(colorScheme.error, width: 1.5),
        focusedErrorBorder: _inputBorder(colorScheme.error, width: 1.5),
        disabledBorder: _inputBorder(Colors.transparent),
        hintStyle: textTheme.bodyMedium?.copyWith(color: market.textMuted),
        // Errors sit below the field in words, never colour alone.
        errorStyle: textTheme.bodySmall?.copyWith(color: colorScheme.error),
        labelStyle: textTheme.labelMedium,
      ),

      // The one action that moves the user forward. Never two on a screen.
      // Pressed, it darkens to its own token rather than taking Material's
      // white wash, which lightened the purple instead.
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
              elevation: 0,
              shape: const StadiumBorder(),
              textStyle: textTheme.labelLarge,
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? null
                    : states.contains(WidgetState.pressed)
                    ? (isLight
                          ? AppPalette.primaryPressed
                          : AppPalette.darkPrimaryPressed)
                    : colorScheme.primary,
              ),
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.pressed)
                    ? Colors.transparent
                    : null,
              ),
            ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // The second level: purple words and outline on the surface, so it
      // is plainly an action and plainly not the main one. Text buttons,
      // the third, are purple words alone.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
          foregroundColor: colorScheme.primary,
          backgroundColor: colorScheme.surface,
          side: BorderSide(color: colorScheme.primary, width: 1.5),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),

      // A chosen chip is purple with white words, like every selected
      // control; Material's default would have made it lavender. One that
      // cannot be changed is grey with readable grey words, chosen or not:
      // Material kept it purple and faded the words to 2:1.
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) &&
                  !states.contains(WidgetState.disabled)
              ? colorScheme.primary
              : market.surfaceMuted,
        ),
        checkmarkColor: colorScheme.onPrimary,
        side: BorderSide.none,
        labelStyle: textTheme.labelMedium?.copyWith(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colorScheme.onSurfaceVariant
                : states.contains(WidgetState.selected)
                ? colorScheme.onPrimary
                : colorScheme.onSurface,
          ),
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: AppSizes.navPillHeight,
        backgroundColor: market.surfaceDark,
        surfaceTintColor: Colors.transparent,
        indicatorColor: market.onDarkAccent,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? market.surfaceDark
                : market.onDark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        showDragHandle: true,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      // Snackbars clear the floating navigation bar rather than hide behind it.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: market.surfaceDark,
        insetPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSizes.snackbarInsetBottom,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: market.onDark),
        actionTextColor: market.onDarkAccent,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        subtitleTextStyle: textTheme.bodySmall,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        labelColor: colorScheme.onSurface,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorColor: colorScheme.primary,
        dividerColor: market.border,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: color, width: width),
      );
}
