// Every demo product makes sense to someone who has bought one.
//
// A client notices these before anything else. The tester found a 65W
// charger at 519,000 IQD, a laptop sold in phone sizes under the brand
// "Atlas", a tablet showing a phone, and Nova selling Atlas's goods.
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/mock/mock_data.dart';

void main() {
  final products = MockData.products;
  String category(Map<String, dynamic> p) => '${p['categoryId']}';
  String name(Map<String, dynamic> p) => '${p['name']}';

  test('every price is one a shop in Iraq would ask', () {
    // IQD, from the cheapest to the dearest a shop would sell of each.
    const bands = <String, (int, int)>{
      'c-smartphones': (100000, 1500000),
      'c-tablets': (80000, 1500000),
      'c-ultrabooks': (300000, 3000000),
      'c-gaming-laptops': (700000, 4000000),
      'c-laptops': (300000, 3000000),
      'c-headphones': (10000, 500000),
      'c-watches': (25000, 700000),
      'c-cameras': (25000, 2500000),
      'c-home': (10000, 1500000),
      'c-accessories': (5000, 150000),
      'c-phone-cases': (3000, 50000),
      'c-chargers': (5000, 60000),
    };
    for (final p in products) {
      final (low, high) = bands[category(p)]!;
      final price = p['price'] as num;
      expect(
        price >= low && price <= high,
        isTrue,
        reason: '${name(p)} at $price IQD',
      );
      if (p['originalPrice'] case final num before) {
        expect(before, greaterThan(price), reason: '${name(p)} "was" price');
      }
      expect(price % 250, 0, reason: '${name(p)} is not payable in cash');
    }
  });

  test('a brand is the one in the name', () {
    for (final p in products) {
      if (p['brand'] case final Map<dynamic, dynamic> brand) {
        final word = '${brand['name']}'.split(' ').first;
        expect(name(p), contains(word), reason: '${name(p)} sold as $word');
      }
    }
  });

  test('a store sells nothing named after the other demo store', () {
    for (final p in products) {
      final store = (p['merchant'] as Map)['id'];
      if (store != 'm-2') {
        expect(name(p), isNot(contains('Atlas')), reason: 'at $store');
      }
      if (store != 'm-1') {
        expect(name(p), isNot(contains('Nova')), reason: 'at $store');
      }
    }
  });

  test('options fit what is sold: sizes a laptop has, not a phone\'s', () {
    for (final p in products) {
      final variants = p['variants'] as List? ?? const [];
      if (variants.isEmpty) continue;
      final sizes = {
        for (final v in variants)
          '${((v as Map)['options'] as Map)['Storage']}',
      };
      switch (category(p)) {
        case 'c-smartphones':
          expect(sizes, {'128GB', '256GB'}, reason: name(p));
        case 'c-ultrabooks' || 'c-gaming-laptops' || 'c-laptops':
          expect(sizes, {'512GB', '1TB'}, reason: name(p));
        default:
          fail('${name(p)} is sold in options nothing of its kind has');
      }
    }
  });

  // One shared photo per category, a placeholder until a store uploads its
  // own: photos rotated within a category put an air fryer on a fridge.
  test('a photo is its category\'s one photo', () {
    const fits = <String, String>{
      'c-smartphones': 'phones',
      'c-tablets': 'phones',
      'c-ultrabooks': 'laptops',
      'c-gaming-laptops': 'laptops',
      'c-laptops': 'laptops',
      'c-headphones': 'headphones',
      'c-watches': 'smartwatches',
      'c-cameras': 'cameras',
      'c-home': 'home-appliances',
      'c-accessories': 'accessories',
      'c-phone-cases': 'accessories',
      'c-chargers': 'accessories',
    };
    for (final p in products) {
      expect(
        p['imageUrl'],
        'assets/images/products/${fits[category(p)]}-1.jpg',
        reason: name(p),
      );
    }
  });
}
