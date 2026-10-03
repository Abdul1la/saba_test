import 'package:flutter/material.dart';

/// Raw colour tokens: the purple palette of the design pass (2026-09-24,
/// DESIGN_CHANGES.md "Colours"), on the structure of the Saba design system
/// (`design/Saba Design System.dc.html`, sections 01 and 10).
///
/// Screens never read these directly; they go through `context.colors`
/// (Material's scheme) or `context.market` ([MarketplaceColors]).
///
/// Three colours carry meaning:
/// * **Purple** is what a person taps: buttons, links, selected chips,
///   active states.
/// * **Amber** is heat: flash sales, discounts, countdowns, limited
///   quantity. It is too light for white text or for text on white (2:1), so
///   it always carries navy ink and is never itself text on a light page.
/// * **Green and red** stay success and error.
///
/// Dark mode is not the light values darkened. The purple *lightens* there
/// (the light-mode purple is too dim on a dark page) and so carries dark ink,
/// the tints become dark desaturated purples, the navy stops being text and
/// becomes the page, and the amber lifts a little to stay warm. The contrast
/// of every pairing is pinned in `test/core/design_tokens_test.dart`.
class AppPalette {
  const AppPalette._();

  // ------------------------------------------------------------ light ------
  /// Warm off-white.
  static const Color bgPage = Color(0xFFFAF8F5);
  static const Color surface = Color(0xFFFFFFFF);

  /// Input fills and neutral tiles, warmed to sit on [bgPage]: the old cool
  /// grey read blue against it.
  static const Color surfaceSunken = Color(0xFFF1EEE9);

  /// Navy: the floating navigation bar and the snack bar.
  static const Color surfaceDark = Color(0xFF1C2536);
  static const Color border = Color(0xFFE8E3DC);

  /// Deep purple, for anything a person taps. White on it is 6.0:1.
  static const Color primary = Color(0xFF7B3FD4);

  /// [primary] while pressed.
  static const Color primaryPressed = Color(0xFF6B2FC9);
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Navy text. The same hex as [surfaceDark] by design, but its own token:
  /// in dark mode text turns light and the navy becomes the page.
  static const Color textPrimary = Color(0xFF1C2536);
  static const Color textSecondary = Color(0xFF55677D);

  /// The quietest text: a store's name on a card, a crossed-out price, a
  /// date, "Step 2 of 4". People read these, so it meets 4.5:1 - 5.3:1 on
  /// white, 4.6:1 on an input's fill. It was #8A99AB, 2.9:1; the admin web
  /// darkened its own to this same value.
  static const Color textMuted = Color(0xFF626D79);

  /// The brand colour where it is a highlight rather than a button: the
  /// chosen city chip, an unread dot, a step bar, a heart. It is [primary].
  static const Color accent = primary;

  /// Very soft tint: card and section backgrounds that want a hint of
  /// purple, and the tile behind a purple icon. Purple on it is 5.2:1.
  static const Color accentSoft = Color(0xFFF3ECFF);

  /// Soft lavender: selected backgrounds, soft badges, highlights. Navy on
  /// it is 7.5:1; white on it is 2:1 and purple on it 2.9:1, so neither is
  /// ever put on it.
  static const Color lavender = Color(0xFFCCA3FF);

  /// Warm amber: heat. Navy on it is 7.3:1.
  static const Color heat = Color(0xFFF0A22E);

  /// The logo's purple. Not [primary]: the mark keeps the colour it was
  /// drawn in, and the buttons keep theirs. White on it is 7.4:1.
  static const Color brand = Color(0xFF6B3FA0);

  // ------------------------------------------------------------- dark ------
  /// A deep navy page: the navy that is text in light mode, pushed down.
  static const Color darkBgPage = Color(0xFF0F131C);
  static const Color darkSurface = Color(0xFF181E2A);
  static const Color darkSurfaceSunken = Color(0xFF131823);

  /// Rises rather than darkens: in dark mode the navigation bar is the
  /// *lightest* surface on the page, which is how it keeps its separating
  /// role.
  static const Color darkSurfaceDark = Color(0xFF222A3A);
  static const Color darkBorder = Color(0xFF2A3242);

  /// Lighter, not darker: [primary] is too dim on a dark page. White on this
  /// is only 3.2:1, so it carries [darkOnPrimary] (5.8:1).
  static const Color darkPrimary = Color(0xFFA57BE8);
  static const Color darkPrimaryPressed = Color(0xFF9467DD);
  static const Color darkOnPrimary = Color(0xFF0F131C);
  static const Color darkTextPrimary = Color(0xFFF2F5F8);
  static const Color darkTextSecondary = Color(0xFFA2B0C0);

  /// 5.5:1 on a card and 4.8:1 on the risen bar; it was #6E7C8C, 3.9:1.
  static const Color darkTextMuted = Color(0xFF8795A6);
  static const Color darkAccent = darkPrimary;

  /// The soft tint on a dark page: a dark desaturated purple, not a light
  /// tint. [darkPrimary] on it is 5.2:1.
  static const Color darkAccentSoft = Color(0xFF221C33);

  /// The lavender on a dark page: a deeper purple surface that light text
  /// sits on (12:1).
  static const Color darkLavender = Color(0xFF352B4D);

  /// Lifted a little so it stays warm on a dark page. Dark ink on it is
  /// 9.9:1, and it can be text there (8.9:1 on [darkSurface]).
  static const Color darkHeat = Color(0xFFF5B04A);

  // --------------------------------------------------------- semantic ------
  static const Color success = Color(0xFF127346);
  static const Color darkSuccess = Color(0xFF34C77B);

  /// Dark amber: amber's meaning as text on a light page, where [heat]
  /// itself is unreadable. 5.1:1 on white.
  static const Color warning = Color(0xFF9A6208);
  static const Color darkWarning = Color(0xFFE8A33D);
  static const Color error = Color(0xFFB32D1C);
  static const Color darkError = Color(0xFFFF7A66);
  static const Color info = Color(0xFF1B5FA8);
  static const Color darkInfo = Color(0xFF6BA9E8);

  /// Empty stars are a neutral so a 4-of-5 row still reads as a rating and
  /// not as damage. Filled stars are [heat].
  static const Color starEmpty = Color(0xFFD6DBE1);
  static const Color darkStarEmpty = Color(0xFF3A444F);

  // --------------------------------------------------- on the dark bar -----
  // The navigation bar and the snack bar are navy in light mode and *risen*
  // in dark mode, so everything printed on them needs its own pair.

  /// `color/text/on-dark`.
  static const Color textOnDark = Color(0xFFFFFFFF);
  static const Color onDarkMuted = Color(0xFF9AA7B5);
  static const Color darkOnDarkMuted = darkTextSecondary;

  /// Icon circles sitting on a dark surface.
  static const Color onDarkFill = Color(0xFF2E3954);
  static const Color darkOnDarkFill = Color(0xFF313B4E);

  /// A card raised on top of a dark surface.
  static const Color onDarkRaised = Color(0xFF253047);
  static const Color darkOnDarkRaised = darkSurface;

  /// Hairline the dark surfaces need once they can no longer separate
  /// themselves from the page by being darker than it.
  static const Color onDarkBorder = Color(0x00000000);
  static const Color darkOnDarkBorder = Color(0xFF333C4F);

  /// Ink on a strong fill: the accent, or a status colour used as a fill.
  /// White on the light-mode fills; dark on the dark-mode ones, which are
  /// all light enough that white on them fails (white on dark-mode green is
  /// 2:1).
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color darkOnAccent = darkOnPrimary;

  // ---------------------------------------------------- soft semantic ------
  // The status badges are drawn with these; their dark counterparts are the
  // same hue at the opposite end of lightness.
  static const Color successSoft = Color(0xFFE7F3ED);
  static const Color darkSuccessSoft = Color(0xFF0D1F18);

  /// Also amber's soft background: an "only a few left" chip.
  static const Color warningSoft = Color(0xFFFDF3E3);
  static const Color darkWarningSoft = Color(0xFF2B200D);
  static const Color errorSoft = Color(0xFFFBEDEA);
  static const Color darkErrorSoft = Color(0xFF2A1310);
  static const Color infoSoft = Color(0xFFE8F0F9);
  static const Color darkInfoSoft = Color(0xFF0E1B29);

  // ---------------------------------------------------------- derived ------
  static const Color borderStrong = Color(0xFFD3CCC2);
  static const Color darkBorderStrong = Color(0xFF3A4356);
  static const Color scrim = Color(0x801C2536);
  static const Color darkScrim = Color(0x990A0D14);
}

/// Everything a marketplace needs that Material's [ColorScheme] has no slot
/// for: prices, sale badges, stock state, the dark header card, skeletons.
///
/// Registered as a [ThemeExtension] so light and dark each supply their own
/// values and no widget ever branches on brightness itself.
@immutable
class MarketplaceColors extends ThemeExtension<MarketplaceColors> {
  const MarketplaceColors({
    required this.price,
    required this.originalPrice,
    required this.heat,
    required this.heatSoft,
    required this.onHeat,
    required this.selected,
    required this.success,
    required this.warning,
    required this.info,
    required this.star,
    required this.inStock,
    required this.outOfStock,
    required this.border,
    required this.surfaceMuted,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.surfaceDark,
    required this.onDark,
    required this.accent,
    required this.accentSoft,
    required this.borderStrong,
    required this.textMuted,
    required this.scrim,
    required this.lowStock,
    required this.starEmpty,
    required this.successSoft,
    required this.warningSoft,
    required this.errorSoft,
    required this.infoSoft,
    required this.onDarkMuted,
    required this.onDarkFill,
    required this.onDarkRaised,
    required this.onDarkBorder,
    required this.onAccent,
    required this.onDarkAccent,
  });

  /// Prices are navy text, not a colour: the purple is for what is tapped,
  /// so a price needs size, not colour, to be noticed.
  final Color price;
  final Color originalPrice;

  /// Amber: flash sales, discount badges, countdowns, limited quantity.
  /// A fill with [onHeat] on it, never text on a light page.
  final Color heat;

  /// Amber's soft background, for a chip whose text is [warning] or navy.
  final Color heatSoft;

  /// Ink on [heat]: navy, or dark in dark mode.
  final Color onHeat;

  /// Selected backgrounds and soft badges: lavender, or a deep purple in
  /// dark mode. Text on it is the ordinary text colour, never white.
  final Color selected;

  final Color success;
  final Color warning;
  final Color info;
  final Color star;
  final Color inStock;

  /// Grey, not red. Out of stock is a fact, not a failure.
  final Color outOfStock;

  final Color border;
  final Color surfaceMuted;
  final Color skeletonBase;
  final Color skeletonHighlight;

  /// The floating navigation bar and the snack bar: navy. In dark mode this
  /// is the *lightest* surface, not the darkest.
  final Color surfaceDark;

  /// Text and icons sitting on [surfaceDark].
  final Color onDark;

  final Color accent;
  final Color accentSoft;
  final Color borderStrong;

  /// The quietest text, below secondary: a store's name on a card, a
  /// crossed-out price, a date, a step count. Still 4.5:1 or more, because
  /// people read it.
  final Color textMuted;

  final Color scrim;
  final Color lowStock;
  final Color starEmpty;
  final Color successSoft;
  final Color warningSoft;
  final Color errorSoft;
  final Color infoSoft;

  /// Secondary text on [surfaceDark] — "Welcome back" above the name.
  final Color onDarkMuted;

  /// Avatar and icon circles on [surfaceDark].
  final Color onDarkFill;

  /// A card raised on top of [surfaceDark] — the promo tile in the header.
  final Color onDarkRaised;

  /// Hairline on [surfaceDark] and [onDarkRaised]. Transparent in light mode,
  /// where being darker than the page is separation enough.
  final Color onDarkBorder;

  /// Ink on an [accent] fill, and on a status colour used as a fill.
  final Color onAccent;

  /// The brand colour where it sits on [surfaceDark] - the navigation bar's
  /// active pill, a snack bar's action. Lavender in light mode, where the
  /// purple on navy is 2.6:1; the purple itself in dark mode, where the bar
  /// has risen. [surfaceDark] is the ink on it in both.
  final Color onDarkAccent;

  static const MarketplaceColors light = MarketplaceColors(
    price: AppPalette.textPrimary,
    originalPrice: AppPalette.textSecondary,
    heat: AppPalette.heat,
    heatSoft: AppPalette.warningSoft,
    onHeat: AppPalette.textPrimary,
    selected: AppPalette.lavender,
    success: AppPalette.success,
    warning: AppPalette.warning,
    info: AppPalette.info,
    star: AppPalette.heat,
    inStock: AppPalette.success,
    outOfStock: AppPalette.textSecondary,
    border: AppPalette.border,
    surfaceMuted: AppPalette.surfaceSunken,
    skeletonBase: AppPalette.surfaceSunken,
    skeletonHighlight: AppPalette.surface,
    surfaceDark: AppPalette.surfaceDark,
    onDark: AppPalette.textOnDark,
    accent: AppPalette.accent,
    accentSoft: AppPalette.accentSoft,
    borderStrong: AppPalette.borderStrong,
    textMuted: AppPalette.textMuted,
    scrim: AppPalette.scrim,
    lowStock: AppPalette.warning,
    starEmpty: AppPalette.starEmpty,
    successSoft: AppPalette.successSoft,
    warningSoft: AppPalette.warningSoft,
    errorSoft: AppPalette.errorSoft,
    infoSoft: AppPalette.infoSoft,
    onDarkMuted: AppPalette.onDarkMuted,
    onDarkFill: AppPalette.onDarkFill,
    onDarkRaised: AppPalette.onDarkRaised,
    onDarkBorder: AppPalette.onDarkBorder,
    onAccent: AppPalette.onAccent,
    onDarkAccent: AppPalette.lavender,
  );

  static const MarketplaceColors dark = MarketplaceColors(
    price: AppPalette.darkTextPrimary,
    originalPrice: AppPalette.darkTextSecondary,
    heat: AppPalette.darkHeat,
    heatSoft: AppPalette.darkWarningSoft,
    onHeat: AppPalette.darkOnPrimary,
    selected: AppPalette.darkLavender,
    success: AppPalette.darkSuccess,
    warning: AppPalette.darkWarning,
    info: AppPalette.darkInfo,
    star: AppPalette.darkHeat,
    inStock: AppPalette.darkSuccess,
    outOfStock: AppPalette.darkTextSecondary,
    border: AppPalette.darkBorder,
    surfaceMuted: AppPalette.darkSurfaceSunken,
    skeletonBase: AppPalette.darkSurfaceSunken,
    skeletonHighlight: AppPalette.darkSurfaceDark,
    surfaceDark: AppPalette.darkSurfaceDark,
    onDark: AppPalette.darkTextPrimary,
    accent: AppPalette.darkAccent,
    accentSoft: AppPalette.darkAccentSoft,
    borderStrong: AppPalette.darkBorderStrong,
    textMuted: AppPalette.darkTextMuted,
    scrim: AppPalette.darkScrim,
    lowStock: AppPalette.darkWarning,
    starEmpty: AppPalette.darkStarEmpty,
    successSoft: AppPalette.darkSuccessSoft,
    warningSoft: AppPalette.darkWarningSoft,
    errorSoft: AppPalette.darkErrorSoft,
    infoSoft: AppPalette.darkInfoSoft,
    onDarkMuted: AppPalette.darkOnDarkMuted,
    onDarkFill: AppPalette.darkOnDarkFill,
    onDarkRaised: AppPalette.darkOnDarkRaised,
    onDarkBorder: AppPalette.darkOnDarkBorder,
    onAccent: AppPalette.darkOnAccent,
    onDarkAccent: AppPalette.darkPrimary,
  );

  @override
  MarketplaceColors copyWith({
    Color? price,
    Color? originalPrice,
    Color? heat,
    Color? heatSoft,
    Color? onHeat,
    Color? selected,
    Color? success,
    Color? warning,
    Color? info,
    Color? star,
    Color? inStock,
    Color? outOfStock,
    Color? border,
    Color? surfaceMuted,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? surfaceDark,
    Color? onDark,
    Color? accent,
    Color? accentSoft,
    Color? borderStrong,
    Color? textMuted,
    Color? scrim,
    Color? lowStock,
    Color? starEmpty,
    Color? successSoft,
    Color? warningSoft,
    Color? errorSoft,
    Color? infoSoft,
    Color? onDarkMuted,
    Color? onDarkFill,
    Color? onDarkRaised,
    Color? onDarkBorder,
    Color? onAccent,
    Color? onDarkAccent,
  }) {
    return MarketplaceColors(
      price: price ?? this.price,
      originalPrice: originalPrice ?? this.originalPrice,
      heat: heat ?? this.heat,
      heatSoft: heatSoft ?? this.heatSoft,
      onHeat: onHeat ?? this.onHeat,
      selected: selected ?? this.selected,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      star: star ?? this.star,
      inStock: inStock ?? this.inStock,
      outOfStock: outOfStock ?? this.outOfStock,
      border: border ?? this.border,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
      surfaceDark: surfaceDark ?? this.surfaceDark,
      onDark: onDark ?? this.onDark,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      borderStrong: borderStrong ?? this.borderStrong,
      textMuted: textMuted ?? this.textMuted,
      scrim: scrim ?? this.scrim,
      lowStock: lowStock ?? this.lowStock,
      starEmpty: starEmpty ?? this.starEmpty,
      successSoft: successSoft ?? this.successSoft,
      warningSoft: warningSoft ?? this.warningSoft,
      errorSoft: errorSoft ?? this.errorSoft,
      infoSoft: infoSoft ?? this.infoSoft,
      onDarkMuted: onDarkMuted ?? this.onDarkMuted,
      onDarkFill: onDarkFill ?? this.onDarkFill,
      onDarkRaised: onDarkRaised ?? this.onDarkRaised,
      onDarkBorder: onDarkBorder ?? this.onDarkBorder,
      onAccent: onAccent ?? this.onAccent,
      onDarkAccent: onDarkAccent ?? this.onDarkAccent,
    );
  }

  @override
  MarketplaceColors lerp(ThemeExtension<MarketplaceColors>? other, double t) {
    if (other is! MarketplaceColors) return this;
    return MarketplaceColors(
      price: Color.lerp(price, other.price, t)!,
      originalPrice: Color.lerp(originalPrice, other.originalPrice, t)!,
      heat: Color.lerp(heat, other.heat, t)!,
      heatSoft: Color.lerp(heatSoft, other.heatSoft, t)!,
      onHeat: Color.lerp(onHeat, other.onHeat, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      star: Color.lerp(star, other.star, t)!,
      inStock: Color.lerp(inStock, other.inStock, t)!,
      outOfStock: Color.lerp(outOfStock, other.outOfStock, t)!,
      border: Color.lerp(border, other.border, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight: Color.lerp(
        skeletonHighlight,
        other.skeletonHighlight,
        t,
      )!,
      surfaceDark: Color.lerp(surfaceDark, other.surfaceDark, t)!,
      onDark: Color.lerp(onDark, other.onDark, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      lowStock: Color.lerp(lowStock, other.lowStock, t)!,
      starEmpty: Color.lerp(starEmpty, other.starEmpty, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      onDarkMuted: Color.lerp(onDarkMuted, other.onDarkMuted, t)!,
      onDarkFill: Color.lerp(onDarkFill, other.onDarkFill, t)!,
      onDarkRaised: Color.lerp(onDarkRaised, other.onDarkRaised, t)!,
      onDarkBorder: Color.lerp(onDarkBorder, other.onDarkBorder, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      onDarkAccent: Color.lerp(onDarkAccent, other.onDarkAccent, t)!,
    );
  }
}
