// A count and its noun agree, in both languages.
//
// Every count used to pick singular or plural on its own: "1 results",
// "Delivered sales (1 orders)", "2 منتجات من 2 متاجر", "11 منتجات".
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/utils/formatters.dart';

const _en = AppLocalizations(Locale('en'));
const _ar = AppLocalizations(Locale('ar'));

void main() {
  // The date words the app itself loads: Flutter's, whose Arabic counts in
  // Arabic-Indic digits.
  setUpAll(() => GlobalMaterialLocalizations.delegate.load(const Locale('ar')));

  test('English: one and the rest', () {
    expect(_en.counted(1, CountNoun.result), '1 result');
    expect(_en.counted(2, CountNoun.result), '2 results');
    expect(_en.counted(1, CountNoun.order), '1 order');
  });

  test('Arabic: the six forms', () {
    expect(_ar.counted(1, CountNoun.product), 'منتج واحد');
    expect(_ar.counted(2, CountNoun.product), 'منتجان');
    expect(_ar.counted(2, CountNoun.store, genitive: true), 'متجرين');
    expect(_ar.counted(3, CountNoun.product), '3 منتجات');
    expect(_ar.counted(10, CountNoun.store), '10 متاجر');
    expect(_ar.counted(11, CountNoun.product), '11 منتجًا');
    expect(_ar.counted(40, CountNoun.product), '40 منتجًا');
    expect(_ar.counted(100, CountNoun.product), '100 منتج');
    expect(_ar.counted(103, CountNoun.order), '103 طلبات');
  });

  test('"2 items from 2 stores", said as Arabic says it', () {
    expect(_ar.cartSummary(2, 2), startsWith('منتجان من متجرين.'));
  });

  test('digits are Western in every language', () {
    final date = DateTime(2026, 9, 22, 14, 5);
    for (final text in [
      Formatters.date(date, locale: 'ar'),
      Formatters.dateTime(date, locale: 'ar'),
      Formatters.time(date, locale: 'ar'),
      Formatters.number(129000, locale: 'ar'),
      Formatters.percent(20, locale: 'ar'),
    ]) {
      expect(
        RegExp('[٠-٩۰-۹]').hasMatch(text),
        isFalse,
        reason: '"$text" has Arabic-Indic digits',
      );
      expect(RegExp('[0-9]').hasMatch(text), isTrue, reason: text);
    }
  });
}
