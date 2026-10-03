import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// Remote image with caching, a skeleton placeholder and a graceful fallback.
///
/// Media is served from object storage by the backend; the app only ever
/// renders the URL it was given.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.radius = AppRadius.sm,
    this.fallbackIcon,
    this.fallback,
  });

  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double radius;

  /// A [SabaIcons] path. Drawn large and muted on the sunken tile while the
  /// image loads and again if it never arrives — which is how the design
  /// draws a product without a photograph. Defaults to a picture frame.
  final String? fallbackIcon;

  /// Drawn instead of the neutral tile, for a picture that has something
  /// better to show while there is no photograph - a banner's own colour and
  /// words, a category's icon.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final source = url?.trim() ?? '';

    if (source.isEmpty) {
      return _fallback(context);
    }

    // A bundled asset, not a URL. Demo mode should not need the internet to
    // draw a product, and the real backend will hand over https URLs to the
    // very same widget — so both live here rather than at every call site.
    if (source.startsWith('assets/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          source,
          fit: fit,
          width: width,
          height: height,
          // An asset that has not been dropped in yet is the same picture as
          // one that failed to download: the neutral tile, not a red X.
          errorBuilder: (context, _, _) => _fallback(context),
        ),
      );
    }

    // A picture the app is holding itself, not one it has to fetch: a photo
    // a store uploaded in demo mode, where there is no file server to put it
    // on. CachedNetworkImage cannot read one of these, and drew the broken
    // tile a merchant saw after saving a product.
    if (source.startsWith('data:image/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(
          base64Decode(source.substring(source.indexOf(',') + 1)),
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (context, _, _) => _fallback(context),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: source,
        fit: fit,
        width: width,
        height: height,
        fadeInDuration: const Duration(milliseconds: 180),
        // In Chrome the default draws each picture from an <img> element,
        // and Flutter's engine empties the element when one copy of the
        // picture is let go while another is still on screen: it went blank
        // a moment after it appeared ("texImage2D: no image"), black in the
        // product form. Fetching the bytes decodes a picture nothing
        // empties. Phones ignore this.
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
        // The same tile for "loading" and "never arrived": the design shows
        // line art on a neutral tile in both cases, so nothing jumps when a
        // slow image finally fails.
        placeholder: (_, _) => _fallback(context),
        errorWidget: (_, _, _) => _fallback(context),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    if (fallback case final custom?) return custom;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.market.surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Sized to the tile rather than fixed, so the same widget reads
          // right on a 52 logo and on a 132 product card.
          final shortest = constraints.biggest.shortestSide;
          final size = shortest.isFinite
              ? (shortest * 0.42).clamp(AppSizes.iconMd, 64.0)
              : AppSizes.iconLg;

          return Center(
            child: SabaIcon(
              fallbackIcon ?? SabaIcons.image,
              size: size.toDouble(),
              color: context.market.starEmpty,
            ),
          );
        },
      ),
    );
  }
}

/// Circular variant used for avatars and store logos.
class AppCircleImage extends StatelessWidget {
  const AppCircleImage({
    super.key,
    required this.url,
    required this.size,
    this.fallbackIcon,
    this.fallback,
  });

  final String? url;
  final double size;
  final String? fallbackIcon;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: AppNetworkImage(
          url: url,
          width: size,
          height: size,
          radius: 0,
          fallbackIcon: fallbackIcon,
          fallback: fallback,
        ),
      ),
    );
  }
}
