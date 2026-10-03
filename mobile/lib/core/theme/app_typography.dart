import 'package:flutter/material.dart';

/// The type scale from the design system (section 03 and section 10).
///
/// Two rules carry the whole hierarchy:
///
/// * **The weight gap is the hierarchy.** Headings are 700, body is 400.
///   Nothing sits at 500 except numerals in dense merchant tiles, and 600 is
///   reserved for button and chip labels. Two weights, far apart, is what
///   stops the app reading flat.
/// * **Arabic gets `+0.12` line height and no negative tracking.** Arabic runs
///   longer and taller, and the tight letter-spacing is a Latin-only optical
///   fix that damages Arabic joins. [arabic] applies both.
class AppTypography {
  const AppTypography._();

  static const String family = 'IBMPlexSansArabic';

  /// Extra line height Arabic needs at every level.
  static const double arabicLineHeightDelta = 0.12;

  // ------------------------------------------------------- headings ---
  // The one place the heading fonts are chosen; nothing else names them.
  // To set Arabic headings in Cairo Bold instead of Amiri: add Cairo-Bold.ttf
  // to pubspec.yaml as family 'Cairo', weight 700, then change the Arabic
  // values below (Cairo sits well at a line height of about 1.35, and needs
  // no size lift).

  /// English headings: a display serif with one weight, drawn heavy.
  static const String headingFamily = 'DMSerifDisplay';
  static const FontWeight headingWeight = FontWeight.w400;
  static const double headingHeight = 1.15;

  /// Arabic headings. Amiri's letters reach higher and lower than Plex's,
  /// so it is given more line height than the body's +0.12.
  static const String headingFamilyArabic = 'Amiri';
  static const FontWeight headingWeightArabic = FontWeight.w700;
  static const double headingHeightArabic = 1.45;

  /// Amiri draws small for its size: at the English size an Arabic heading
  /// looked timid beside DM Serif, so Arabic headings are set this much
  /// larger. Bold is Amiri's heaviest weight; size is what is left.
  static const double headingScaleArabic = 1.18;

  // One hierarchy, on every screen. Card titles, labels, body and prices
  // stay in the body font.

  /// A tab screen's big title: "My cart", "Orders", "Account".
  static const double screenTitleSize = 30;

  /// A pushed screen's title, centred in its bar beside the back button.
  static const double barTitleSize = 20;

  /// A product's or a store's name as the title of its own page: a name,
  /// not a word, so it runs long and sits below a screen title.
  static const double nameTitleSize = 24;

  /// A section on a page: "Shop by category", "Related products".
  static const double sectionTitleSize = 21;

  /// A section inside a card or a sheet: "Deliver to", "Description", a
  /// sheet's title.
  static const double subsectionTitleSize = 18;

  /// A heading at [size], in the font for the reader's language, in
  /// [color] or the text colour.
  ///
  /// The other language's heading font stands behind it, then the body
  /// family, so a name typed in the other alphabet still draws in a heading
  /// face and never in a system font.
  static TextStyle heading(
    BuildContext context, {
    required double size,
    Color? color,
  }) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return TextStyle(
      fontFamily: isArabic ? headingFamilyArabic : headingFamily,
      fontFamilyFallback: [
        isArabic ? headingFamily : headingFamilyArabic,
        family,
      ],
      fontSize: isArabic ? size * headingScaleArabic : size,
      fontWeight: isArabic ? headingWeightArabic : headingWeight,
      height: isArabic ? headingHeightArabic : headingHeight,
      letterSpacing: 0,
      color: color ?? Theme.of(context).colorScheme.onSurface,
    );
  }

  static TextStyle screenTitle(BuildContext context, {Color? color}) =>
      heading(context, size: screenTitleSize, color: color);

  static TextStyle barTitle(BuildContext context) =>
      heading(context, size: barTitleSize);

  static TextStyle nameTitle(BuildContext context) =>
      heading(context, size: nameTitleSize);

  static TextStyle sectionTitle(BuildContext context, {Color? color}) =>
      heading(context, size: sectionTitleSize, color: color);

  static TextStyle subsectionTitle(BuildContext context) =>
      heading(context, size: subsectionTitleSize);

  static TextTheme textTheme(Color primary, Color secondary) {
    TextStyle style(
      double size,
      FontWeight weight,
      double height, {
      double tracking = 0,
      Color? color,
    }) => TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: tracking,
      color: color ?? primary,
    );

    return TextTheme(
      // type/display · 34 / 700 / 1.08
      displayLarge: style(34, FontWeight.w700, 1.08, tracking: -1.19),
      displayMedium: style(30, FontWeight.w700, 1.10, tracking: -0.90),
      displaySmall: style(28, FontWeight.w700, 1.12, tracking: -0.78),

      // type/heading · 26 / 700 / 1.15
      headlineLarge: style(26, FontWeight.w700, 1.15, tracking: -0.65),
      headlineMedium: style(26, FontWeight.w700, 1.15, tracking: -0.65),
      headlineSmall: style(22, FontWeight.w700, 1.18, tracking: -0.44),

      // type/card-title · 18 / 700 / 1.25
      titleLarge: style(18, FontWeight.w700, 1.25, tracking: -0.27),
      titleMedium: style(16, FontWeight.w700, 1.28, tracking: -0.16),
      // type/label · 13 / 600 / 1.30
      titleSmall: style(13, FontWeight.w600, 1.30),

      // type/subtitle · 16 / 400 / 1.50
      bodyLarge: style(16, FontWeight.w400, 1.50, color: secondary),
      // type/body · 14.5 / 400 / 1.55
      bodyMedium: style(14.5, FontWeight.w400, 1.55),
      // type/caption · 12 / 400 / 1.40
      bodySmall: style(12, FontWeight.w400, 1.40, color: secondary),

      // type/label · buttons and chips are the only place 600 is allowed
      labelLarge: style(13, FontWeight.w600, 1.30),
      labelMedium: style(12, FontWeight.w600, 1.35),
      // type/caption-sm · 11.5 / 400 / 1.35
      labelSmall: style(11.5, FontWeight.w400, 1.35, color: secondary),
    );
  }

  /// type/price · 22 / 700 / 1.10.
  ///
  /// Always tabular so a column of prices lines up, and never decimals: IQD
  /// is not written with them. Digits stay Western in both languages — an
  /// Iraqi customer reads `250,000` far faster than `٢٥٠٬٠٠٠` in a price, and
  /// only the currency mark localises.
  static TextStyle price(Color color) => TextStyle(
    fontFamily: family,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.10,
    letterSpacing: -0.22,
    color: color,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// The same theme with Arabic's taller lines and no negative tracking.
  ///
  /// Applied once, in `app.dart`'s builder, which sits below `Localizations`
  /// and therefore sees the *resolved* locale — so it is still correct when
  /// the user has left the language on "follow device".
  static TextTheme arabic(TextTheme latin) {
    TextStyle? fix(TextStyle? s) => s?.copyWith(
      height: (s.height ?? 1.0) + arabicLineHeightDelta,
      letterSpacing: 0,
    );

    return TextTheme(
      displayLarge: fix(latin.displayLarge),
      displayMedium: fix(latin.displayMedium),
      displaySmall: fix(latin.displaySmall),
      headlineLarge: fix(latin.headlineLarge),
      headlineMedium: fix(latin.headlineMedium),
      headlineSmall: fix(latin.headlineSmall),
      titleLarge: fix(latin.titleLarge),
      titleMedium: fix(latin.titleMedium),
      titleSmall: fix(latin.titleSmall),
      bodyLarge: fix(latin.bodyLarge),
      bodyMedium: fix(latin.bodyMedium),
      bodySmall: fix(latin.bodySmall),
      labelLarge: fix(latin.labelLarge),
      labelMedium: fix(latin.labelMedium),
      labelSmall: fix(latin.labelSmall),
    );
  }
}

/// Text styles Material's [TextTheme] has no slot for.
///
/// Only [price] so far, because it needs tabular figures and appears on most
/// screens in the app. Everything else maps onto a Material slot.
@immutable
class MarketplaceTextStyles extends ThemeExtension<MarketplaceTextStyles> {
  const MarketplaceTextStyles({required this.price});

  final TextStyle price;

  @override
  MarketplaceTextStyles copyWith({TextStyle? price}) =>
      MarketplaceTextStyles(price: price ?? this.price);

  @override
  MarketplaceTextStyles lerp(
    ThemeExtension<MarketplaceTextStyles>? other,
    double t,
  ) {
    if (other is! MarketplaceTextStyles) return this;
    return MarketplaceTextStyles(price: TextStyle.lerp(price, other.price, t)!);
  }
}
