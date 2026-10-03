import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/location/governorate.dart';

void main() {
  test("Iraq's 19 governorates, each with its own code", () {
    expect(Governorate.values, hasLength(19), reason: 'Halabja is the 19th');
    expect(
      Governorate.values.map((each) => each.apiValue).toSet(),
      hasLength(19),
    );
    expect(Governorate.values.first, Governorate.baghdad);
  });

  test('a place is found by its code, or its name in either language', () {
    expect(Governorate.fromApi('ERBIL'), Governorate.erbil);
    // Stores saved before the list existed kept their city as words.
    expect(Governorate.fromApi('Baghdad'), Governorate.baghdad);
    expect(Governorate.fromApi(' basra '), Governorate.basra);
    // Looked for by the city, found by the governorate.
    expect(Governorate.fromApi('Mosul'), Governorate.nineveh);
    expect(Governorate.fromApi('الموصل'), Governorate.nineveh);
    expect(Governorate.fromApi('نينوى'), Governorate.nineveh);
    expect(Governorate.fromApi('حلبجة'), Governorate.halabja);
    expect(Governorate.fromApi('Paris'), isNull);
    expect(Governorate.fromApi(''), isNull);
    expect(Governorate.fromApi(null), isNull);
  });

  test('names in the app language', () {
    expect(Governorate.dhiQar.nameIn('en'), 'Dhi Qar (Nasiriyah)');
    expect(Governorate.dhiQar.nameIn('ar'), 'ذي قار (الناصرية)');
  });
}
