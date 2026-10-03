// Every product, category and store in the demo shows its own picture.
//
// The demo pointed at photos in assets/images/ and the folder was empty:
// every product, category and store drew a grey tile, and the browser logged
// a missing file for each one. A path here with no file behind it, or a
// product with no picture at all, is that again.
//
// The product photos come from tool/demo_photos.py: add one to
// saba_test/demo-photos/ and run it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';

void main() {
  final pictures = <String, String?>{
    for (final product in MockData.products) ...{
      '${product['id']}': product['imageUrl'] as String?,
      for (final image in product['images'] as List)
        '${product['id']} gallery': (image as Map)['url'] as String?,
      for (final variant in (product['variants'] as List?) ?? const [])
        '${(variant as Map)['id']}': variant['imageUrl'] as String?,
    },
    for (final category in MockData.categories)
      '${category['id']}': category['imageUrl'] as String?,
    for (final store in MockData.merchants) ...{
      '${store['id']} logo': store['logoUrl'] as String?,
      '${store['id']} banner': store['bannerUrl'] as String?,
    },
  };

  test('every product, category and store has a picture, and it is there', () {
    final missing = [
      for (final MapEntry(:key, :value) in pictures.entries)
        if (value == null || !File(value).existsSync()) '$key: $value',
    ];
    expect(missing, isEmpty, reason: 'no picture, or not in assets/');
  });

  test('the Home promos name no picture the app does not have', () {
    for (final banner in MockData.homeBanners) {
      final url = banner['imageUrl'] as String?;
      if (url != null) expect(File(url).existsSync(), isTrue, reason: url);
    }
  });

  test('and every picture is small enough to keep the app fast', () {
    final heavy = [
      for (final path in pictures.values.whereType<String>().toSet())
        if (File(path).existsSync() && File(path).lengthSync() > 200 * 1024)
          path,
    ];
    expect(heavy, isEmpty, reason: 'too heavy for a card');
  });
}
