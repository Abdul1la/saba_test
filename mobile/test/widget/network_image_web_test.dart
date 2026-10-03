// The user, in Chrome: a product's photos showed, then went blank a moment
// later ("texImage2D: no image" in the console), and black in the product
// form. The package drew each picture from an <img> element that Flutter's
// engine empties when one copy is let go while another is on screen. The
// bytes are fetched instead. The fault needs a browser, so this checks the
// setting.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/core/widgets/app_network_image.dart';

void main() {
  testWidgets('pictures are fetched as bytes in Chrome', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const AppNetworkImage(url: 'https://example.com/photo.jpg'),
      ),
    );
    final providers = [
      for (final image in tester.widgetList<Image>(find.byType(Image)))
        if (image.image case final CachedNetworkImageProvider provider)
          provider,
    ];
    expect(providers, isNotEmpty);
    expect(
      providers.map((p) => p.imageRenderMethodForWeb),
      everyElement(ImageRenderMethodForWeb.HttpGet),
    );
  });
}
