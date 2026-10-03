import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/utils/iraqi_phone.dart';

void main() {
  // The same order showed its driver as +9647705550311 and its customer as
  // +964 780 555 0117: each number as it arrived.
  test('a number is shown one way, however it arrived', () {
    for (final arrived in [
      '+9647705550311',
      '+964 770 555 0311',
      '07705550311',
      '9647705550311',
      '٠٧٧٠٥٥٥٠٣١١',
    ]) {
      expect(IraqiPhone.display(arrived), '+964 770 555 0311', reason: arrived);
    }
    // Not an Iraqi mobile: shown as it came, never mangled.
    expect(IraqiPhone.display('+44 20 7946 0958'), '+44 20 7946 0958');
    expect(IraqiPhone.display(''), '');
  });
}
