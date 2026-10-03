import 'formatters.dart';

/// Iraqi mobile numbers, typed any way people type them - 0770 123 4567,
/// 770 123 4567, +964 770 123 4567, 00964 770... - and kept one way:
/// +9647701234567. A number that changes shape with where it was typed
/// cannot be matched against itself later, and it is how people sign in.
class IraqiPhone {
  const IraqiPhone._();

  /// The number in full international form, or null when it is not an
  /// Iraqi mobile: a 7 and nine more digits, after the country code or 0.
  static String? normalize(String? input) {
    // Arabic and Persian digits are digits: they were thrown away with the
    // spaces, so a number typed on an Arabic keyboard was never a number.
    var digits = Formatters.western(input ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00964')) {
      digits = digits.substring(5);
    } else if (digits.startsWith('964')) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) digits = digits.substring(1);
    return RegExp(r'^7\d{9}$').hasMatch(digits) ? '+964$digits' : null;
  }

  /// The number without its country code, 7701234567, for a field that has
  /// +964 in front of it already: "+964 0770..." is not a number. Anything
  /// not Iraqi comes back as it was.
  static String local(String number) {
    final full = normalize(number);
    return full == null ? number : full.substring(4);
  }

  /// How a number is shown, one way everywhere: +964 770 555 0311. The same
  /// order showed its driver as +9647705550311 and its customer as
  /// +964 780 555 0117, as each arrived. Anything not Iraqi is shown as it
  /// came.
  static String display(String number) {
    final full = normalize(number);
    if (full == null) return number;
    return '${full.substring(0, 4)} ${full.substring(4, 7)} '
        '${full.substring(7, 10)} ${full.substring(10)}';
  }
}
