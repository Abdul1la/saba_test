import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/theme/saba_icons.dart';
import 'package:saba_marketplace/core/widgets/filter_chip_row.dart';

void main() {
  test('an Arabic name gets the icon its English name gets', () {
    // Home's categories, in both languages: same icon either way.
    const pairs = <(String, String)>[
      ('Headphones', 'سماعات'),
      ('Phones', 'هواتف'),
      ('Laptops', 'حواسيب محمولة'),
      ('Smartwatches', 'ساعات ذكية'),
      ('Cameras', 'كاميرات'),
      ('Home appliances', 'أجهزة منزلية'),
    ];
    for (final (english, arabic) in pairs) {
      expect(iconForName(arabic, 99), iconForName(english, 99), reason: arabic);
    }
    expect(iconForName('سماعات', 0), SabaIcons.video);
    expect(iconForName('ساعات ذكية', 0), SabaIcons.clock);
    expect(iconForName('شاحن نوفا السريع', 0), SabaIcons.card);
  });
}
