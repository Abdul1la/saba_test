import 'package:intl/intl.dart';

import '../config/app_config.dart';

/// Locale-aware money, number and date formatting.
///
/// Amounts arrive from the API as minor-unit-safe decimal strings and are
/// formatted here. The app never performs pricing arithmetic of its own — the
/// server is the only authority on totals (specification sections 13 and 20).
class Formatters {
  const Formatters._();

  /// Digits stay Western in every language.
  ///
  /// The design is explicit about this: an Iraqi customer reads `250,000` far
  /// faster than `٢٥٠٬٠٠٠` in a price, so only the currency mark localises.
  /// Formatting the number against `en` is what keeps the digits Western.
  static const String _digitLocale = 'en';

  /// Formats an amount with Western digits and a localised currency mark.
  static String money(
    num amount, {
    required String locale,
    String? currencyCode,
    bool compact = false,
  }) {
    final (number, mark) = moneyParts(
      amount,
      locale: locale,
      currencyCode: currencyCode,
      compact: compact,
    );
    final code = (currencyCode ?? AppConfig.fallbackCurrencyCode).toUpperCase();
    return _markLeads(code) ? '$mark$number' : '$number $mark';
  }

  /// An amount taken off — a discount, a refund, a commission — as a minus
  /// and the figure, with the minus welded to the digits.
  ///
  /// In Arabic the line runs right to left, and a leading minus is a neutral
  /// character, so the bidi algorithm carried it to the far end of the
  /// number: a discount read "250,000- د.ع" and a product badge "20%-". An
  /// LTR isolate around the sign and the number keeps them in one piece, and
  /// the currency mark stays on the side every other price puts it. Always a
  /// true minus sign, which is what the design draws; the call sites had
  /// drifted between that and a hyphen.
  static String deduction(
    num amount, {
    required String locale,
    String? currencyCode,
  }) {
    final code = (currencyCode ?? AppConfig.fallbackCurrencyCode).toUpperCase();
    final (number, mark) = moneyParts(
      amount.abs(),
      locale: locale,
      currencyCode: code,
    );
    return _markLeads(code)
        ? ltrIsolate('−$mark$number')
        : '${ltrIsolate('−$number')} $mark';
  }

  /// Keeps a signed figure in one piece inside right-to-left text.
  static String ltrIsolate(String text) => '\u2066$text\u2069';

  /// The same figure split into `(amount, mark)`.
  ///
  /// Product cards and the detail screen set the currency mark several points
  /// smaller than the number, which needs the two pieces separately.
  static (String, String) moneyParts(
    num amount, {
    required String locale,
    String? currencyCode,
    bool compact = false,
  }) {
    final code = (currencyCode ?? AppConfig.fallbackCurrencyCode).toUpperCase();
    final number = compact
        ? NumberFormat.compact(locale: _digitLocale).format(amount)
        : NumberFormat.decimalPatternDigits(
            locale: _digitLocale,
            decimalDigits: _decimalDigitsFor(code),
          ).format(amount);
    return (number, currencyMark(code, locale: locale));
  }

  /// `IQD` in English, `د.ع` in Arabic; glyph currencies keep their glyph.
  static String currencyMark(String code, {required String locale}) {
    final upper = code.toUpperCase();
    if (locale.startsWith('ar')) {
      final arabic = _arabicMarks[upper];
      if (arabic != null) return arabic;
    }
    return _symbolFor(upper).trim();
  }

  /// Glyph currencies lead the number; three-letter marks follow it, which is
  /// how the design writes `250,000 IQD` and `250,000 د.ع`.
  static bool _markLeads(String code) =>
      const {'USD', 'EUR', 'GBP', 'JPY', 'TRY'}.contains(code);

  static const Map<String, String> _arabicMarks = {
    'IQD': 'د.ع',
    'SAR': 'ر.س',
    'AED': 'د.إ',
    'QAR': 'ر.ق',
    'KWD': 'د.ك',
    'BHD': 'د.ب',
    'OMR': 'ر.ع',
    'EGP': 'ج.م',
    'YER': 'ر.ي',
    'JOD': 'د.أ',
    'USD': r'$',
  };

  /// Parses a decimal string from the API. Returns 0 for malformed input
  /// rather than throwing in the middle of a build.
  static num parseAmount(Object? value) => switch (value) {
    final num v => v,
    final String v => num.tryParse(v) ?? 0,
    _ => 0,
  };

  /// Western digits, whatever the locale formatted them in.
  ///
  /// Money always was; dates, times and counts were not. Flutter's Arabic
  /// date words count in Arabic-Indic digits, so an order read
  /// "٢٢ سبتمبر ٢٠٢٦" beside "129,000 د.ع". One rule for every number on
  /// screen: 0-9. The month names and ص/م stay in the reader's language.
  static String western(String text) =>
      text.replaceAllMapped(RegExp('[٠-٩۰-۹٫٬٪]'), (match) {
        final unit = match[0]!.codeUnitAt(0);
        return switch (unit) {
          0x066B => '.',
          0x066C => ',',
          0x066A => '%',
          >= 0x06F0 => '${unit - 0x06F0}',
          _ => '${unit - 0x0660}',
        };
      });

  /// A number as someone typed it: "12,250", "12 250" or Arabic digits
  /// are 12250. The commas the examples show were refused as "not a
  /// number", on the price the product form's own hint wrote with one.
  static num? typedNumber(String text) =>
      num.tryParse(western(text).replaceAll(RegExp(r'[,\s]'), ''));

  /// [typedNumber], whole: "2.5" units of stock is no count at all.
  static int? typedWholeNumber(String text) => switch (typedNumber(text)) {
    final value? when value == value.truncate() => value.toInt(),
    _ => null,
  };

  static String number(num value, {required String locale}) =>
      western(NumberFormat.decimalPattern(locale).format(value));

  static String compactNumber(num value, {required String locale}) =>
      western(NumberFormat.compact(locale: locale).format(value));

  static String percent(num value, {required String locale}) => western(
    NumberFormat.decimalPercentPattern(
      locale: locale,
      decimalDigits: 0,
    ).format(value / 100),
  );

  static String date(DateTime value, {required String locale}) =>
      western(DateFormat.yMMMd(locale).format(value.toLocal()));

  static String dateTime(DateTime value, {required String locale}) =>
      western(DateFormat.yMMMd(locale).add_jm().format(value.toLocal()));

  static String time(DateTime value, {required String locale}) =>
      western(DateFormat.jm(locale).format(value.toLocal()));

  static String monthYear(DateTime value, {required String locale}) =>
      western(DateFormat.yMMMM(locale).format(value.toLocal()));

  /// "Sep", "سبتمبر".
  static String month(DateTime value, {required String locale}) =>
      western(DateFormat.MMM(locale).format(value.toLocal()));

  static String monthDay(DateTime value, {required String locale}) =>
      western(DateFormat.MMMd(locale).format(value.toLocal()));

  static String monthDayTime(DateTime value, {required String locale}) =>
      western(DateFormat.MMMd(locale).add_jm().format(value.toLocal()));

  /// A countdown rendered as `HH:MM:SS`, used by flash sales.
  static String countdown(Duration remaining) {
    if (remaining.isNegative) return '00:00:00';
    final hours = remaining.inHours.toString().padLeft(2, '0');
    final minutes = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  /// Masks all but the last four digits, for saved payment instruments.
  /// The app never receives or stores a full card number.
  static String maskedCard(String last4) => '•••• •••• •••• $last4';

  /// IQD is never written with decimals, and neither are the others here.
  static int _decimalDigitsFor(String code) => switch (code.toUpperCase()) {
    'IQD' || 'JPY' || 'KRW' || 'VND' || 'CLP' || 'ISK' => 0,
    'KWD' || 'BHD' || 'OMR' || 'JOD' || 'TND' => 3,
    _ => 2,
  };

  static String _symbolFor(String code) => switch (code.toUpperCase()) {
    'USD' => r'$',
    'EUR' => '€',
    'GBP' => '£',
    'JPY' => '¥',
    'SAR' => 'SAR ',
    'AED' => 'AED ',
    'QAR' => 'QAR ',
    'KWD' => 'KWD ',
    'BHD' => 'BHD ',
    'OMR' => 'OMR ',
    'EGP' => 'EGP ',
    'YER' => 'YER ',
    'IQD' => 'IQD ',
    'JOD' => 'JOD ',
    'TRY' => '₺',
    _ => '$code ',
  };
}
