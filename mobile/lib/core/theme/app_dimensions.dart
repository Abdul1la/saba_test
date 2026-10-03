/// Spacing, radius, component sizing, elevation and motion tokens from the
/// Saba design system (`design/Saba Design System.dc.html`, sections 04 and 10).
///
/// Names mirror the design's tokens: `space/section-gap` is [sectionGap],
/// `radius/card` is [AppRadius.card]. Using tokens instead of magic numbers is
/// what keeps 47 screens consistent and makes a density change one edit.
library;

import 'package:flutter/painting.dart';

/// 4pt base scale.
class AppSpacing {
  const AppSpacing._();

  /// icon to its label
  static const double xs = 4;

  /// title to description
  static const double sm = 8;

  /// between chips, grid gutter
  static const double md = 12;

  /// card padding, screen gutter
  static const double lg = 16;

  /// heading to content
  static const double xl = 24;

  /// between home sections — the design uses space, not divider lines
  static const double sectionGap = 32;

  /// empty-state breathing room
  static const double xxl2 = 48;

  /// Default horizontal padding for page content.
  static const double screenGutter = 16;

  /// Bottom padding on **every** scroll view, so the floating navigation bar
  /// never covers the last row of content.
  static const double navSafe = 104;

  // Kept so the 47 existing screens keep compiling while they are migrated
  // screen by screen. Each maps onto the nearest design token.
  static const double xxs = 4;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

class AppRadius {
  const AppRadius._();

  /// badges, small chips
  static const double xs = 8;

  /// corner action button, size box
  static const double action = 14;

  /// fields, list rows
  static const double input = 18;

  /// product and merchant cards
  static const double card = 24;

  /// header card, bottom sheet
  static const double sheet = 32;

  /// buttons, navigation, chips
  static const double pill = 999;

  // Legacy names, remapped onto the design scale rather than deleted, so the
  // 73 existing call sites move to the new look immediately and get renamed
  // as each screen is rebuilt.
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
}

class AppSizes {
  const AppSizes._();

  /// Every interactive element is at least this, including invisible tap
  /// padding, even when it looks smaller.
  static const double minTapTarget = 48;

  static const double buttonHeight = 52;
  static const double buttonHeightLarge = 58;
  static const double iconCircle = 44;

  /// The coloured square behind a list row's icon.
  static const double tileIcon = 36;
  static const double cornerAction = 40;
  static const double inputHeight = 54;
  static const double filterChipHeight = 44;

  static const double navPillHeight = 64;
  static const double navPillInsetX = 20;
  static const double navPillInsetBottom = 16;
  static const double navPillActiveHeight = 48;
  static const double navBadge = 18;

  /// The card is drawn 172 wide with 10 padding, so its image box is 152×132.
  ///
  /// The handoff token list says `card/product/image-ratio · 4:3`, but no card
  /// in the design is actually drawn at 4:3 — the grid card is 152×132 and the
  /// home rail card is 140×118, both ≈7:6. The drawing wins, because that is
  /// the thing that was reviewed. See WORK-LOG.md, finding F12.
  /// Square. A shop photographs whatever it has to hand, and one tall
  /// picture in a grid of wide ones used to push a whole row out of
  /// line; cropped to a square by the frame, none of them can.
  static const double productCardImageRatio = 1;

  /// Padding inside a product card, and the gap between image and text.
  static const double productCardPadding = 10;
  static const double productCardGap = 10;

  /// Width of a product card inside a horizontal rail.
  static const double productCardRailWidth = 172;

  /// The flash-sale card: wide enough to set the name and the price side by
  /// side, over a full "Add to cart" button. Its image is a 2:1 banner.
  static const double flashSaleCardWidth = 248;
  static const double flashSaleImageRatio = 2;

  /// Badges on a product image: "−25%", "Only 3 left", "Out of stock".
  static const double cardBadgeHeight = 24;
  static const double cardBadgeInset = 10;

  /// The favourite circle in the image's top trailing corner.
  static const double cardFavourite = 30;

  static const double headerCardRadiusBottom = 32;
  static const double sheetHandleWidth = 36;
  static const double sheetHandleHeight = 4;

  /// Snackbars clear the floating navigation bar instead of hiding behind it.
  static const double snackbarInsetBottom = 96;

  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double appBarHeight = 56;

  // Legacy.
  static const double buttonHeightSmall = 38;
  static const double bottomNavHeight = navPillHeight;
  static const double bannerRatio = 16 / 9;
}

/// Shadow is used on exactly three things: the floating nav, the sticky buy
/// bar and the bottom sheet. Everywhere else, separation is space, then a soft
/// neutral fill, then a 1px border — in that order of preference.
class AppElevation {
  const AppElevation._();

  static const double floatBlur = 24;
  static const double floatOffsetY = 8;
  static const double floatOpacity = 0.10;

  static const double dialogBlur = 32;
  static const double dialogOffsetY = 12;
  static const double dialogOpacity = 0.16;

  /// A card's soft shadow, in place of a border: the product, store and
  /// order cards all use it.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
}

class AppMotion {
  const AppMotion._();

  /// Pressed is a 2% scale-down plus a fill shift, never a hue change.
  static const Duration press = Duration(milliseconds: 120);
  static const double pressScale = 0.98;

  static const Duration chipExpand = Duration(milliseconds: 180);
  static const Duration sheet = Duration(milliseconds: 240);
  static const Duration skeleton = Duration(milliseconds: 1200);

  /// A skeleton that has run this long has failed; it becomes the error state
  /// rather than spinning forever.
  static const Duration skeletonTimeout = Duration(seconds: 8);

  /// The corner action button confirms in place for this long instead of
  /// firing a snackbar for every add to cart.
  static const Duration confirmInPlace = Duration(milliseconds: 1200);
}

/// Layout breakpoints. The same widget tree serves phone, tablet and desktop
/// web; these decide how many columns it uses.
class AppBreakpoints {
  const AppBreakpoints._();

  static const double mobile = 600;
  static const double tablet = 905;
  static const double desktop = 1240;
}
