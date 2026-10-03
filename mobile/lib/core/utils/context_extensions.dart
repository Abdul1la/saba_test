import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../localization/app_localizations.dart';
import 'formatters.dart';

export '../localization/app_localizations.dart' show CountNoun;
import '../router/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

/// Short, readable access to the things every widget needs.
///
/// `context.l10n.addToCart` instead of
/// `AppLocalizations.of(context).addToCart`.
extension BuildContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// "e.g. 12,500", inside an empty field: every one showed nothing, and
  /// nobody knew what to type or whether to put the zeros (the user). A
  /// number is written the way people write it, with its commas.
  String exampleOf(Object example) => l10n.example(
    example is num
        ? Formatters.number(example, locale: l10n.locale.toLanguageTag())
        : '$example',
  );

  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get textStyles => Theme.of(this).textTheme;

  /// Marketplace-specific semantic colors (price, discount, stock, skeleton).
  MarketplaceColors get market =>
      Theme.of(this).extension<MarketplaceColors>() ?? MarketplaceColors.light;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// True when the current locale lays out right to left.
  bool get isRtl => Directionality.of(this) == TextDirection.rtl;

  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);
  double get keyboardInset => MediaQuery.viewInsetsOf(this).bottom;

  bool get isMobile => screenWidth < AppBreakpoints.mobile;
  bool get isTablet =>
      screenWidth >= AppBreakpoints.mobile &&
      screenWidth < AppBreakpoints.desktop;
  bool get isDesktop => screenWidth >= AppBreakpoints.desktop;

  /// Number of columns a product grid should use at the current width.
  int get productGridColumns {
    final width = screenWidth;
    if (width >= AppBreakpoints.desktop) return 5;
    if (width >= AppBreakpoints.tablet) return 4;
    if (width >= AppBreakpoints.mobile) return 3;
    return 2;
  }

  /// Caps content width on tablets and desktop web so lines stay readable.
  double get contentMaxWidth => isDesktop ? 1200 : double.infinity;

  /// Goes back, or to [fallback] when there is nowhere to go back to.
  ///
  /// A screen arrived at with `go`, from a notification, or from a link has no
  /// history behind it, and both `maybePop` and `pop` on an empty history do
  /// nothing at all — drawing a back arrow that is not a back arrow. The path
  /// that made this matter was the one right after paying: Order confirmation
  /// sends the customer to the order with `go`, which clears the stack, and
  /// the arrow on that screen then did nothing on every tap.
  void popOrGo([String fallback = AppRoutes.home]) {
    final router = GoRouter.of(this);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(fallback);
    }
  }
}
