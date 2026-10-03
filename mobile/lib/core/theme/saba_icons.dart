import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_dimensions.dart';

/// The design system's own icon set.
///
/// 97 icons lifted from the design files, normalised to a 24x24 box with a
/// stroke of 2 and rounded caps. Material's icons are a different family with
/// a different weight and a different corner language, so using them is what
/// made the first pass still read as the old app.
///
/// Every name here is an asset path. Draw one with [SabaIcon], which colours
/// it from the theme and gives it the right optical size.
class SabaIcons {
  const SabaIcons._();

  static const String _dir = 'assets/icons';
  static String _i(String name) => '$_dir/$name.svg';

  /// The solid twin of a navigation icon, for the selected tab. Only the
  /// icons a navigation bar uses have one (`home-fill.svg` beside
  /// `home.svg`).
  static String filled(String icon) => icon.replaceFirst('.svg', '-fill.svg');

  // ------------------------------------------------------- navigation ------
  static final String home = _i('home');
  static final String grid = _i('grid');
  static final String bag = _i('bag');
  static final String receipt = _i('receipt');
  static final String user = _i('user');
  static final String store = _i('store');
  static final String barChart = _i('bar-chart');
  static final String box = _i('box');

  // ------------------------------------------------------- directional -----
  static final String chevronRight = _i('chevron-right');
  static final String chevronLeft = _i('chevron-left');
  static final String chevronDown = _i('chevron-down');
  static final String chevronUp = _i('chevron-up');
  static final String arrowUp = _i('arrow-up');
  static final String close = _i('close');
  static final String check = _i('check');
  static final String plus = _i('plus');
  static final String minus = _i('minus');
  static final String menu = _i('menu');
  static final String moreVertical = _i('more-vertical');
  static final String swap = _i('swap');
  static final String signOut = _i('sign-out');

  // ------------------------------------------------------------ actions ----
  static final String search = _i('search');
  static final String sort = _i('sort');
  static final String sortVertical = _i('sort-vertical');
  static final String heart = _i('heart');
  static final String heartFilled = _i('heart-filled');
  static final String send = _i('send');
  static final String share = _i('share');
  static final String pencil = _i('pencil');
  static final String trash = _i('trash');
  static final String refresh = _i('refresh');
  static final String download = _i('download');
  static final String bookmark = _i('bookmark');
  static final String camera = _i('camera');
  static final String image = _i('image');
  static final String imageOff = _i('image-off');
  static final String lock = _i('lock');
  static final String mail = _i('mail');
  static final String eye = _i('eye');
  static final String eyeOff = _i('eye-off');
  static final String play = _i('play');
  static final String video = _i('video');
  static final String zoomOut = _i('zoom-out');

  // ------------------------------------------------------------- status ----
  static final String bell = _i('bell');
  static final String info = _i('info');
  static final String alert = _i('alert');
  static final String alertCircle = _i('alert-circle');
  static final String exclamation = _i('exclamation');
  static final String clock = _i('clock');
  static final String shield = _i('shield');
  static final String spinner = _i('spinner');
  static final String wifiOff = _i('wifi-off');
  static final String trendingUp = _i('trending-up');
  static final String trendingDown = _i('trending-down');
  static final String sliders = _i('sliders');
  static final String message = _i('message');
  static final String headset = _i('headset');

  // -------------------------------------------------------- ratings -------
  // Drawn to the set's own spec (24x24, stroke 2, rounded caps) because the
  // design shipped no thumbs-up, flag or star and reviews need all three.
  // See WORK-LOG F28: replace them if the design later ships its own.
  static final String star = _i('star');
  static final String starFilled = _i('star-filled');
  static final String starHalf = _i('star-half');
  static final String thumbUp = _i('thumb-up');
  static final String thumbUpFilled = _i('thumb-up-filled');
  static final String flag = _i('flag');

  // ---------------------------------------------------------- commerce -----
  static final String flame = _i('flame');
  static final String truck = _i('truck');
  static final String creditCard = _i('credit-card');
  static final String card = _i('card');
  static final String coin = _i('coin');
  static final String ticket = _i('ticket');
  static final String ticketDashed = _i('ticket-dashed');
  static final String mapPin = _i('map-pin');
  static final String clipboard = _i('clipboard');
  static final String archive = _i('archive');
  static final String briefcase = _i('briefcase');
  static final String handbag = _i('handbag');
  static final String shoppingBag = _i('shopping-bag');
  static final String gem = _i('gem');
  static final String sofa = _i('sofa');
  static final String phone = _i('phone');
  static final String tablet = _i('tablet');
  static final String globe = _i('globe');
  static final String moon = _i('moon');
  static final String sun = _i('sun');

  /// Icons used for category chips when a category has no image of its own,
  /// picked so a row of them still reads as a set.
  static final List<String> categoryFallbacks = <String>[
    phone,
    tablet,
    sofa,
    handbag,
    gem,
    briefcase,
    box,
    store,
  ];
}

/// Draws one [SabaIcons] entry in the current text colour.
///
/// Defaults to [AppSizes.iconMd], the size the design uses inside buttons and
/// rows; pass [size] for the 16 and 24 variants.
class SabaIcon extends StatelessWidget {
  const SabaIcon(
    this.icon, {
    super.key,
    this.size = AppSizes.iconMd,
    this.color,
  });

  /// Glyphs that point along the reading direction and have no mirrored twin
  /// in the set, so in Arabic they have to be flipped rather than swapped.
  ///
  /// An SVG does not mirror itself the way a Material icon declared
  /// `matchTextDirection` does, so before this every call site had to remember
  /// — and the chat composer did not, leaving a send arrow pointing away from
  /// the direction the message travels. Doing it here means no call site can
  /// forget it again.
  ///
  /// Deliberately absent: chevrons and arrows, which come as left/right pairs
  /// that every call site already picks by name — flipping those as well would
  /// turn a correct swap back round. Absent too are `trending-up` and
  /// `trending-down`, where the direction *is* the meaning (a price fell), not
  /// the layout, and mirroring would invert what they say.
  static final Set<String> _mirroredInRtl = <String>{
    SabaIcons.send,
    SabaIcons.signOut,
  };

  final String icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? Colors.black;

    final picture = SvgPicture.asset(
      icon,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
    );

    if (_mirroredInRtl.contains(icon) &&
        Directionality.of(context) == TextDirection.rtl) {
      return Transform.flip(flipX: true, child: picture);
    }

    return picture;
  }
}
