import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/context_extensions.dart';

/// Which colours the mark is drawn in.
enum SabaMarkTone {
  /// Purple square, white bag: the app icon, and the logo on a light page.
  purple,

  /// White square, purple bag: on purple, and on a dark page, where the
  /// purple square and a purple name sink into the background.
  white,

  /// Navy square, white bag, a pale diamond: on a white document, where
  /// purple would be too loud.
  navy,
}

/// Saba's mark: a shopping bag drawn as an S, an amber diamond in its
/// keyhole, on a rounded square.
///
/// Paths, not the PNGs the design came as: those were screenshot crops,
/// 221 px at best, with the page they were cut from baked in around them.
/// A path is sharp at 16 px and at 1024. `tool/app_icons.py` reads these
/// same paths to draw the app icons, so change them here and run it.
class SabaMark extends StatelessWidget {
  const SabaMark({super.key, this.size = 40, this.tone = SabaMarkTone.purple});

  final double size;
  final SabaMarkTone tone;

  /// The bag with the S cut through it, and its keyhole, in a 100 box.
  static const String bagPath =
      'M33.6 83.02 L66.07 83.02 A12.5 12.5 0 0 0 78.57 70.52 '
      'L78.57 38.19 A8 8 0 0 0 70.57 30.19 L68.96 30.19 '
      'A19.3 19.3 0 0 0 31.04 30.19 L29.43 30.19 A8 8 0 0 0 21.43 38.19 '
      'L21.43 75.95 L53.29 57.55 A5.64 5.64 0 0 1 58.93 67.31 Z '
      'M38.4 34.34 A11.6 11.6 0 0 1 61.6 34.34 L61.6 42.97 '
      'L35.9 57.81 L35.9 39.9 L38.4 37.4 Z';

  static const String diamondPath =
      'M50 27.84 L57.3 35.14 L50 42.44 L42.7 35.14 Z';

  /// The square's corner, in the same 100 box.
  static const double cornerRadius = 18;

  /// (square, bag, diamond) for [tone].
  static (Color, Color, Color) colours(SabaMarkTone tone) => switch (tone) {
    SabaMarkTone.purple => (
      AppPalette.brand,
      AppPalette.textOnDark,
      AppPalette.heat,
    ),
    SabaMarkTone.white => (
      AppPalette.textOnDark,
      AppPalette.brand,
      AppPalette.heat,
    ),
    SabaMarkTone.navy => (
      AppPalette.surfaceDark,
      AppPalette.textOnDark,
      Color.lerp(AppPalette.heat, AppPalette.textOnDark, 0.55)!,
    ),
  };

  static String _hex(Color colour) =>
      '#${(colour.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static String svg(SabaMarkTone tone) {
    final (square, bag, diamond) = colours(tone);
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<rect width="100" height="100" rx="$cornerRadius" '
        'fill="${_hex(square)}"/>'
        '<path fill="${_hex(bag)}" fill-rule="evenodd" d="$bagPath"/>'
        '<path fill="${_hex(diamond)}" d="$diamondPath"/>'
        '</svg>';
  }

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      svg(tone),
      width: size,
      height: size,
      // The name beside it, or the thing it stands in for, says it.
      excludeFromSemantics: true,
    );
  }
}

/// The mark and the name, in the app's language: "Saba" or "سبأ".
///
/// The mark stays on the left in both, as the design draws it. Purple on a
/// light page, white on a dark one unless [tone] says otherwise.
class SabaLogo extends StatelessWidget {
  const SabaLogo({super.key, this.size = 44, this.tone});

  /// The mark's height; the name is set to match it.
  final double size;
  final SabaMarkTone? tone;

  /// The name as the logo sets it: the heading serif in Latin, Plex's bold
  /// in Arabic, which is the geometric Arabic the design uses.
  static TextStyle nameStyle(
    BuildContext context, {
    required double size,
    required Color color,
  }) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return TextStyle(
      fontFamily: isArabic ? AppTypography.family : AppTypography.headingFamily,
      fontWeight: isArabic ? FontWeight.w700 : FontWeight.w400,
      fontSize: isArabic ? size * 0.92 : size * 1.02,
      height: 1,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tone =
        this.tone ??
        (context.isDarkMode ? SabaMarkTone.white : SabaMarkTone.purple);
    final nameColour = switch (tone) {
      SabaMarkTone.purple => AppPalette.brand,
      SabaMarkTone.white => AppPalette.textOnDark,
      SabaMarkTone.navy => AppPalette.surfaceDark,
    };

    return Semantics(
      label: context.l10n.appName,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.ltr,
        children: [
          SabaMark(size: size, tone: tone),
          SizedBox(width: size * 0.26),
          Text(
            context.l10n.appName,
            textScaler: TextScaler.noScaling,
            style: nameStyle(context, size: size, color: nameColour),
          ),
        ],
      ),
    );
  }
}
