// Regenerates `lib/core/localization/app_localizations.dart` from the string
// tables, and fails if a translation is missing a key.
//
// Run from the `mobile/` directory:
//
//   dart run tool/generate_localizations.dart
//
// Adding a user-facing string is therefore a three-step job: add it to
// `strings_en.dart`, add it to `strings_ar.dart`, run this. The build breaks if
// you skip the translation, which is the point.

import 'dart:io';

const String _localizationDir = 'lib/core/localization';
const String _englishFile = '$_localizationDir/strings_en.dart';
const String _arabicFile = '$_localizationDir/strings_ar.dart';
const String _outputFile = '$_localizationDir/app_localizations.dart';

final RegExp _keyPattern = RegExp("^  '([A-Za-z0-9_]+)':", multiLine: true);

void main(List<String> args) {
  final englishKeys = _readKeys(_englishFile);
  final arabicKeys = _readKeys(_arabicFile).toSet();

  if (englishKeys.isEmpty) {
    stderr.writeln('No keys found in $_englishFile. Is the format correct?');
    exit(1);
  }

  final missing = englishKeys
      .where((key) => !arabicKeys.contains(key))
      .toList();
  final extra = arabicKeys.where((key) => !englishKeys.contains(key)).toList();

  if (missing.isNotEmpty) {
    stderr.writeln('Missing Arabic translations for ${missing.length} key(s):');
    for (final key in missing) {
      stderr.writeln('  - $key');
    }
    exit(1);
  }

  if (extra.isNotEmpty) {
    stderr.writeln('Arabic has ${extra.length} key(s) English does not:');
    for (final key in extra) {
      stderr.writeln('  - $key');
    }
    exit(1);
  }

  final duplicates = <String>{};
  final seen = <String>{};
  for (final key in englishKeys) {
    if (!seen.add(key)) duplicates.add(key);
  }
  if (duplicates.isNotEmpty) {
    stderr.writeln('Duplicate keys: ${duplicates.join(', ')}');
    exit(1);
  }

  final getters = englishKeys
      .map((key) => "  String get $key => _v('$key');")
      .join('\n');

  File(_outputFile).writeAsStringSync('$_header$getters\n$_footer');

  stdout.writeln(
    'Generated $_outputFile with ${englishKeys.length} keys '
    '(en + ar in sync).',
  );
}

List<String> _readKeys(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Missing $path');
    exit(1);
  }
  return _keyPattern
      .allMatches(file.readAsStringSync())
      .map((match) => match.group(1)!)
      .toList();
}

const String _header = r'''
// GENERATED FILE - DO NOT EDIT BY HAND.
//
// Regenerate with: dart run tool/generate_localizations.dart
// Source of truth: strings_en.dart (keys) and strings_ar.dart (translations).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'strings_ar.dart';
import 'strings_en.dart';

/// Localized strings for the app.
///
/// No user-facing text is written inline in a widget; everything resolves
/// through here (specification section 60). A key missing from a translation
/// falls back to English rather than rendering a raw key.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('en'));

  /// Name of a locale, shown in the language picker in that language itself.
  static String displayName(Locale locale) => switch (locale.languageCode) {
        'ar' => 'العربية',
        _ => 'English',
      };

  Map<String, String> get _table => switch (locale.languageCode) {
        'ar' => stringsAr,
        _ => stringsEn,
      };

  bool get isRtl => locale.languageCode == 'ar';

  String _v(String key) => _table[key] ?? stringsEn[key] ?? key;

''';

const String _footer = r'''
  // -------------------------------------------------- parameterized strings --

  /// A count and its noun, said the way the language says it: "1 item",
  /// "3 items"; "منتج واحد", "منتجان", "3 منتجات", "11 منتجًا", "100 منتج".
  ///
  /// Every count on screen goes through here. They each chose singular or
  /// plural on their own, which is two forms where Arabic has six, and read
  /// "2 منتجات من 2 متاجر" and "11 منتجات".
  ///
  /// The forms come from the translation file, `|` between them: English
  /// one|other; Arabic one|two|two after a preposition|3-10|11-99|other,
  /// the plural classes of CLDR. One and two are said without the number,
  /// as Arabic does. [genitive] picks the dual after a preposition: "من
  /// متجرين", not "من متجران".
  String counted(int count, CountNoun noun, {bool genitive = false}) {
    final forms = _v(noun.key).split('|');
    if (forms.length < 6) {
      return '$count ${count == 1 || forms.length == 1 ? forms[0] : forms[1]}';
    }
    final rest = count % 100;
    return switch (count) {
      1 => forms[0],
      2 => genitive ? forms[2] : forms[1],
      _ when rest >= 3 && rest <= 10 => '$count ${forms[3]}',
      _ when rest >= 11 => '$count ${forms[4]}',
      _ => '$count ${forms[5]}',
    };
  }

  /// "Tokyo, Japan" / "طوكيو، اليابان": the list comma of the language.
  String get comma => _v('listSeparator');

  /// "3 items from 2 stores. Each store ships on its own."
  String cartSummary(int items, int stores) =>
      '${counted(items, CountNoun.item)} ${_v('fromWord')} '
      '${counted(stores, CountNoun.store, genitive: true)}. '
      '${_v('eachStoreShips')}';

  /// The API's business-type token, in the reader's language. Built by
  /// title-casing the token before this, which left Arabic showing
  /// "Sole Proprietorship".
  String businessTypeLabel(String token) => switch (token) {
    'INDIVIDUAL' => _v('businessTypeIndividual'),
    'SOLE_PROPRIETORSHIP' => _v('businessTypeSoleProprietorship'),
    'COMPANY' => _v('businessTypeCompany'),
    'DISTRIBUTOR' => _v('businessTypeDistributor'),
    _ => token,
  };

  /// "Step 2 of 4"
  String stepOf(int step, int total) =>
      '${_v('stepWord')} $step ${_v('ofWord')} $total';

  /// "Out of stock - not charged"
  String outOfStockNotCharged() =>
      '${_v('outOfStock')} — ${_v('notCharged')}';

  /// "Delivery, 2 stores"
  String deliveryFromStores(int stores) =>
      '${_v('deliveryWord')}$comma${counted(stores, CountNoun.store)}';

  /// "Place order - 2,605,200 IQD"
  String placeOrderFor(String amount) =>
      '${_v('placeOrder')} · $amount';

  /// "10% off", "خصم 10%" - one template per language, because the amount
  /// sits on a different side of the words in each.
  String amountOff(String amount) =>
      _v('amountOffTemplate').replaceFirst('{amount}', amount);

  /// The first words of a chat started from a product or an order, so the
  /// store knows what the question is about.
  String aboutTopic(String topic) =>
      _v('aboutTopicTemplate').replaceFirst('{topic}', topic);

  /// "Doesn't deliver to Erbil", beside a store the shopper cannot buy from.
  String noDeliveryTo(String city) =>
      _v('noDeliveryToTemplate').replaceFirst('{city}', city);

  /// "Delivers to Erbil", beside a store that does.
  String deliversTo(String city) =>
      _v('deliversToTemplate').replaceFirst('{city}', city);

  /// Said at checkout when the address is not in the Home city.
  String addressCityNote({required String home, required String city}) =>
      _v('addressCityNoteTemplate')
          .replaceFirst('{home}', home)
          .replaceFirst('{city}', city);

  /// "Not in your total: Doesn't deliver to Erbil", on a store's part of
  /// the cart that cannot come.
  String notInTotal(String reason) => _v('notInTotalTemplate')
      .replaceFirst('{reason}', reason)
      .trim();

  /// "31 products", beside Home's Filters button.
  String productsFound(int count) => counted(count, CountNoun.product);

  /// "Deliver to Erbil", on the Home city button.
  String deliverToCity(String city) =>
      _v('deliverToTemplate').replaceFirst('{city}', city);

  String aboutOrder(String number) =>
      _v('aboutOrderTemplate').replaceFirst('{number}', number);

  /// "12 of 50 used", or "Used 12 times" when there is no limit.
  String couponUsage(int used, int? limit) => limit == null
      ? _v('couponUsedTemplate')
            .replaceFirst('{times}', counted(used, CountNoun.time))
      : _v('couponUsedOfTemplate')
            .replaceFirst('{used}', '$used')
            .replaceFirst('{limit}', '$limit');

  String untilDate(String date) =>
      _v('untilDateTemplate').replaceFirst('{date}', date);

  /// "e.g. 12,500": see BuildContextX.exampleOf.
  String example(String example) =>
      _v('exampleTemplate').replaceFirst('{example}', example);

  /// "Expected: 1–2 days", in a store's box on an order.
  String expectedArrival(String time) =>
      _v('expectedArrivalTemplate').replaceFirst('{time}', time);

  /// Under the order's badge, when more than one store is sending it.
  String orderFollowsSlowest(String status) =>
      _v('orderFollowsSlowestTemplate').replaceFirst('{status}', status);

  /// What a store's account deletion still waits for.
  String storeDeletionAsked(String date) =>
      _v('storeDeletionAskedTemplate').replaceFirst('{date}', date);

  String stillOpenOrders(int count) =>
      _v('stillOpenOrdersTemplate').replaceFirst('{count}', '$count');

  String openReturns(int count) =>
      _v('openReturnsTemplate').replaceFirst('{count}', '$count');

  String stillOwed(String amount) =>
      _v('stillOwedTemplate').replaceFirst('{amount}', amount);

  String returnsOpenUntil(String date) =>
      _v('returnsOpenUntilTemplate').replaceFirst('{date}', date);

  /// "Flash sale until 9:00 PM", on a product its store put on one.
  String flashSaleUntil(String time) =>
      _v('flashSaleUntilTemplate').replaceFirst('{time}', time);

  /// "Paid 2 Sep": a past month's bill, and the day Saba marked it paid.
  String billPaidOn(String date) =>
      _v('billPaidOnTemplate').replaceFirst('{date}', date);

  /// "The normal price is 61,250 IQD.", under the sale price being typed:
  /// the price without the sale, during one too.
  String normalPrice(String price) =>
      _v('normalPriceTemplate').replaceFirst('{price}', price);

  String startsDate(String date) =>
      _v('startsDateTemplate').replaceFirst('{date}', date);

  /// "At Nova Electronics": where a store's coupon can be used.
  String atStore(String store) =>
      _v('atStoreTemplate').replaceFirst('{store}', store);

  String couponsFrom(String store) =>
      _v('couponsFromTemplate').replaceFirst('{store}', store);

  /// The design writes a discount as '− 25%' — a true minus sign and
  /// nothing else. 'off' is still translated and still used by screen
  /// readers through [discountBadgeLabel].
  // Isolated left-to-right: in Arabic a bare leading minus is a neutral
  // character, and the badge rendered as "20%-".
  String discountBadge(String percent) => '\u2066−$percent%\u2069';

  String discountBadgeLabel(String percent) =>
      '$percent% ${_v('off')}';

  /// "Too short. Use at least 2 characters." It said "Too short (2)".
  String minimumLength(int length) => _v('validationMinLengthTemplate')
      .replaceAll('{count}', counted(length, CountNoun.character, genitive: true));

  /// "Resend in 58 seconds"
  String resendAfter(int seconds) => _v('resendInTemplate')
      .replaceFirst('{time}', counted(seconds, CountNoun.second, genitive: true));

  /// "Waiting 3 hours": how long an order has waited for its store.
  String waitingFor(Duration elapsed) => _v('waitingForTemplate').replaceFirst(
    '{time}',
    elapsed.inDays >= 1
        ? counted(elapsed.inDays, CountNoun.day)
        : elapsed.inHours >= 1
        ? counted(elapsed.inHours, CountNoun.hour)
        : counted(elapsed.inMinutes, CountNoun.minute),
  );
}

/// What a count counts, for [AppLocalizations.counted]. Each names the key
/// in the translation files that holds its forms.
enum CountNoun {
  item('nounItem'),
  product('nounProduct'),
  store('nounStore'),
  order('nounOrder'),
  result('nounResult'),
  customer('nounCustomer'),
  returnRequest('nounReturnRequest'),
  day('nounDay'),
  hour('nounHour'),
  minute('nounMinute'),
  second('nounSecond'),
  time('nounTime'),
  character('nounCharacter');

  const CountNoun(this.key);

  final String key;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
''';
