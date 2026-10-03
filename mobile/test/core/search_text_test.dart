import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/utils/search_text.dart';

void main() {
  test('the ways Arabic is typed in Iraq fold into one', () {
    String fold(String text) => SearchText.normalize(text);

    // Hamza on or under the alef, madda, wasla.
    expect(fold('أحمد'), fold('احمد'));
    expect(fold('إسبريسو'), fold('اسبريسو'));
    expect(fold('آلة'), fold('الة'));
    // Ta marbuta and ha, alef maqsura and ya.
    expect(fold('مكتبة'), fold('مكتبه'));
    expect(fold('مصطفى'), fold('مصطفي'));
    // Hamza on waw and on ya.
    expect(fold('مؤسسة'), fold('موسسه'));
    expect(fold('هيئة'), fold('هييه'));
    // Vowel marks and the tatweel that stretches a word.
    expect(fold('مُصْطَفَى'), fold('مصطفى'));
    expect(fold('منقّي'), fold('منقي'));
    expect(fold('سـبـأ'), fold('سبا'));
    // A Persian or Kurdish keyboard's ya and kaf.
    expect(fold('کامیرا'), fold('كاميرا'));
    // Arabic and Persian digits.
    expect(fold('شاحن ٦٥ واط'), 'شاحن 65 واط');
    expect(fold('۶۵'), '65');
    // Case and spaces.
    expect(fold('  Nova   X5 '), 'nova x5');
  });

  test('every word must be found, in any order, and ال is optional', () {
    const names = ['ساعة أطلس الذكية الإصدار 4', 'Atlas Smartwatch Series 4'];

    expect(SearchText.matches('ساعه', names), isTrue);
    expect(SearchText.matches('اطلس ساعة', names), isTrue);
    expect(SearchText.matches('الساعة', names), isTrue);
    expect(SearchText.matches('smartwatch atlas', names), isTrue);
    expect(SearchText.matches('ساعة نوفا', names), isFalse);
    expect(SearchText.matches('camera', names), isFalse);
    // Nothing typed finds everything; a missing field is not an error.
    expect(SearchText.matches('  ', names), isTrue);
    expect(SearchText.matches('atlas', [null, 'Atlas']), isTrue);
  });
}
