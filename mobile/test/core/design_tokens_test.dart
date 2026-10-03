import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/theme/app_colors.dart';
import 'package:saba_marketplace/core/theme/app_dimensions.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/core/theme/app_typography.dart';

/// The design system, pinned.
///
/// These are the values in `design/Saba Design System.dc.html`. The point of
/// this file is that a token cannot drift by accident: if someone changes a
/// colour or a size, this goes red and names the one that moved.
void main() {
  group('colour tokens match the palette', () {
    test('light', () {
      expect(AppPalette.primary, const Color(0xFF7B3FD4));
      expect(AppPalette.primaryPressed, const Color(0xFF6B2FC9));
      expect(AppPalette.lavender, const Color(0xFFCCA3FF));
      expect(AppPalette.accentSoft, const Color(0xFFF3ECFF));
      expect(AppPalette.textPrimary, const Color(0xFF1C2536));
      expect(AppPalette.surfaceDark, const Color(0xFF1C2536));
      expect(AppPalette.bgPage, const Color(0xFFFAF8F5));
      expect(AppPalette.heat, const Color(0xFFF0A22E));
      expect(AppPalette.accent, AppPalette.primary);
    });

    test('dark', () {
      expect(AppPalette.darkPrimary, const Color(0xFFA57BE8));
      expect(AppPalette.darkBgPage, const Color(0xFF0F131C));
      expect(AppPalette.darkSurface, const Color(0xFF181E2A));
      expect(AppPalette.darkSurfaceDark, const Color(0xFF222A3A));
      expect(AppPalette.darkLavender, const Color(0xFF352B4D));
      expect(AppPalette.darkAccentSoft, const Color(0xFF221C33));
      expect(AppPalette.darkHeat, const Color(0xFFF5B04A));
      expect(AppPalette.darkAccent, AppPalette.darkPrimary);
    });

    test('semantic: green and red are kept', () {
      expect(AppPalette.success, const Color(0xFF127346));
      expect(AppPalette.darkSuccess, const Color(0xFF34C77B));
      expect(AppPalette.error, const Color(0xFFB32D1C));
      expect(AppPalette.darkError, const Color(0xFFFF7A66));
    });
  });

  group('the palette rules, not just the values', () {
    test('the purple lightens in dark mode, it does not darken', () {
      expect(
        AppPalette.darkPrimary.computeLuminance(),
        greaterThan(AppPalette.primary.computeLuminance()),
      );
    });

    test('the navy is light-mode text and never dark-mode text or page', () {
      // One hex, two roles in light mode; in dark mode neither role is it.
      final dark = AppTheme.dark();
      expect(dark.colorScheme.onSurface, isNot(AppPalette.textPrimary));
      expect(dark.scaffoldBackgroundColor, isNot(AppPalette.textPrimary));
      expect(AppTheme.light().colorScheme.onSurface, AppPalette.textPrimary);
    });

    test('the tints are dark surfaces in dark mode, not light tints', () {
      for (final tint in [
        MarketplaceColors.dark.accentSoft,
        MarketplaceColors.dark.selected,
      ]) {
        expect(tint.computeLuminance(), lessThan(0.05));
      }
    });

    test('the amber lifts in dark mode', () {
      expect(
        AppPalette.darkHeat.computeLuminance(),
        greaterThan(AppPalette.heat.computeLuminance()),
      );
    });

    test('the navigation bar RISES in dark mode, it does not stay dark', () {
      int luminance(Color c) => ((c.r + c.g + c.b) * 255 ~/ 3);
      expect(
        luminance(MarketplaceColors.dark.surfaceDark),
        greaterThan(luminance(AppPalette.darkBgPage)),
      );
      expect(
        luminance(MarketplaceColors.light.surfaceDark),
        lessThan(luminance(AppPalette.bgPage)),
      );
    });

    test('out of stock is grey, not red — it is a fact, not a failure', () {
      expect(MarketplaceColors.light.outOfStock, isNot(AppPalette.error));
      expect(MarketplaceColors.dark.outOfStock, isNot(AppPalette.darkError));
    });

    test('a price is navy text, not the purple', () {
      expect(MarketplaceColors.light.price, AppPalette.textPrimary);
      expect(MarketplaceColors.light.price, isNot(AppPalette.accent));
    });

    test('the main button is the purple, not near-black', () {
      expect(AppTheme.light().colorScheme.primary, AppPalette.primary);
      expect(AppTheme.dark().colorScheme.primary, AppPalette.darkPrimary);
    });
  });

  // WCAG contrast of every pairing the app draws, in both modes: 4.5:1 for
  // words, 3:1 for a shape that has to be seen. "Readable in sunlight".
  group('contrast', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final (hi, lo) = la > lb ? (la, lb) : (lb, la);
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final (mode, theme, market) in [
      ('light', AppTheme.light(), MarketplaceColors.light),
      ('dark', AppTheme.dark(), MarketplaceColors.dark),
    ]) {
      final scheme = theme.colorScheme;
      final page = theme.scaffoldBackgroundColor;
      final text = scheme.onSurface;

      final words = <String, (Color, Color)>{
        'button text on the purple': (scheme.onPrimary, scheme.primary),
        'purple text on the page': (scheme.primary, page),
        'purple text on a card': (scheme.primary, scheme.surface),
        'ink on the amber': (market.onHeat, market.heat),
        'text on the lavender': (text, market.selected),
        'text on the soft tint': (text, market.accentSoft),
        'purple on the soft tint': (market.accent, market.accentSoft),
        'ink on the accent': (market.onAccent, market.accent),
        'ink on the green': (market.onAccent, market.success),
        'ink on the blue': (market.onAccent, market.info),
        'ink on the red': (scheme.onError, scheme.error),
        'amber words on a card': (market.lowStock, scheme.surface),
        'amber words on the amber tint': (market.lowStock, market.heatSoft),
        'text on the page': (text, page),
        'secondary text on a card': (scheme.onSurfaceVariant, scheme.surface),
        // The store under a product's name, a crossed-out price, a date.
        'muted text on a card': (market.textMuted, scheme.surface),
        'muted text on the page': (market.textMuted, page),
        'muted text on a field': (market.textMuted, market.surfaceMuted),
        'price on a card': (market.price, scheme.surface),
        'text on the navy bar': (market.onDark, market.surfaceDark),
        'navy on the bar\'s active pill': (
          market.surfaceDark,
          market.onDarkAccent,
        ),
        'a snack bar\'s action': (market.onDarkAccent, market.surfaceDark),
      };
      for (final entry in words.entries) {
        test('$mode: ${entry.key}', () {
          final (fore, back) = entry.value;
          expect(contrast(fore, back), greaterThanOrEqualTo(4.5));
        });
      }

      test('$mode: the active pill stands out from the bar', () {
        expect(
          contrast(market.onDarkAccent, market.surfaceDark),
          greaterThanOrEqualTo(3),
        );
      });
    }

    test('why amber never carries white, and lavender never purple', () {
      expect(contrast(Colors.white, AppPalette.heat), lessThan(3));
      expect(contrast(AppPalette.primary, AppPalette.lavender), lessThan(3));
      expect(contrast(Colors.white, AppPalette.darkPrimary), lessThan(4.5));
    });
  });

  group('spacing, radius and component sizes', () {
    test('the 4pt scale', () {
      expect(AppSpacing.xs, 4);
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.md, 12);
      expect(AppSpacing.lg, 16);
      expect(AppSpacing.xl, 24);
      expect(AppSpacing.sectionGap, 32);
      expect(AppSpacing.navSafe, 104);
    });

    test('radius', () {
      expect(AppRadius.xs, 8);
      expect(AppRadius.action, 14);
      expect(AppRadius.input, 18);
      expect(AppRadius.card, 24);
      expect(AppRadius.sheet, 32);
    });

    test('component sizes', () {
      expect(AppSizes.buttonHeight, 52);
      expect(AppSizes.inputHeight, 54);
      expect(AppSizes.iconCircle, 44);
      expect(AppSizes.cornerAction, 40);
      expect(AppSizes.navPillHeight, 64);
      expect(AppSizes.snackbarInsetBottom, 96);
      expect(AppSizes.minTapTarget, 48);
    });
  });

  group('typography', () {
    final light = AppTheme.light();

    test('one family, everywhere', () {
      expect(light.textTheme.bodyMedium?.fontFamily, 'IBMPlexSansArabic');
      expect(light.textTheme.displayLarge?.fontFamily, 'IBMPlexSansArabic');
    });

    test('the scale matches the design', () {
      expect(light.textTheme.displayLarge?.fontSize, 34);
      expect(light.textTheme.headlineMedium?.fontSize, 26);
      expect(light.textTheme.titleLarge?.fontSize, 18);
      expect(light.textTheme.bodyLarge?.fontSize, 16);
      expect(light.textTheme.bodyMedium?.fontSize, 14.5);
      expect(light.textTheme.bodySmall?.fontSize, 12);
      expect(light.textTheme.labelLarge?.fontSize, 13);
    });

    test('the weight gap is the hierarchy: 700 headings, 400 body', () {
      expect(light.textTheme.displayLarge?.fontWeight, FontWeight.w700);
      expect(light.textTheme.headlineMedium?.fontWeight, FontWeight.w700);
      expect(light.textTheme.titleLarge?.fontWeight, FontWeight.w700);
      expect(light.textTheme.bodyMedium?.fontWeight, FontWeight.w400);
      expect(light.textTheme.bodyLarge?.fontWeight, FontWeight.w400);
      // 600 is reserved for button and chip labels only.
      expect(light.textTheme.labelLarge?.fontWeight, FontWeight.w600);
    });

    test('Arabic adds +0.12 line height and drops the negative tracking', () {
      final latin = light.textTheme;
      final arabic = AppTypography.arabic(latin);

      expect(
        arabic.displayLarge!.height,
        closeTo(latin.displayLarge!.height! + 0.12, 1e-9),
      );
      expect(
        arabic.bodyMedium!.height,
        closeTo(latin.bodyMedium!.height! + 0.12, 1e-9),
      );
      expect(
        arabic.displayLarge!.letterSpacing,
        0,
        reason: 'tight tracking is a Latin-only fix; it damages Arabic joins',
      );
      expect(
        latin.displayLarge!.letterSpacing,
        lessThan(0),
        reason: 'precondition: Latin really does carry negative tracking',
      );
    });

    test('prices are tabular so a column of them lines up', () {
      final style = AppTypography.price(AppPalette.textPrimary);
      expect(style.fontSize, 22);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontFeatures?.map((f) => f.feature), contains('tnum'));
    });
  });

  group('theme wiring', () {
    test('both themes carry the marketplace extensions', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        expect(theme.extension<MarketplaceColors>(), isNotNull);
        expect(theme.extension<MarketplaceTextStyles>(), isNotNull);
      }
    });

    test('fields are filled at rest with no border', () {
      // The border is what makes an errored field visible from across the
      // screen, so it must not be spent on the resting state.
      final input = AppTheme.light().inputDecorationTheme;
      expect(input.filled, isTrue);
      expect(
        (input.enabledBorder as OutlineInputBorder).borderSide.color.a,
        0,
        reason: 'resting field must have no visible border',
      );
      expect(
        (input.focusedBorder as OutlineInputBorder).borderSide.color.a,
        greaterThan(0),
      );
    });

    test('snackbars clear the floating navigation bar', () {
      final snack = AppTheme.light().snackBarTheme;
      expect(snack.behavior, SnackBarBehavior.floating);
      expect(snack.insetPadding?.resolve(TextDirection.ltr).bottom, 96);
    });

    test('the page background is bg/page, not surface', () {
      expect(AppTheme.light().scaffoldBackgroundColor, AppPalette.bgPage);
      expect(AppTheme.dark().scaffoldBackgroundColor, AppPalette.darkBgPage);
    });
  });
}
