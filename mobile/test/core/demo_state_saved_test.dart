// Everything the demo server holds is kept on the phone.
//
// The demo server writes itself to the phone after each change and reads it
// back when the app opens (`mock_state_saving.dart`). A new piece of state
// that nobody adds to that document would be lost when the app is closed -
// an account's orders, or its store's work, quietly gone. These tests read
// the source and fail the moment that happens.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final server = File(
    'lib/core/mock/mock_api_interceptor.dart',
  ).readAsStringSync();
  final saving = File(
    'lib/core/mock/mock_state_saving.dart',
  ).readAsStringSync();

  /// What a class keeps: its own fields, declared at one indent. Anything
  /// deeper is a local inside a method, not state.
  List<String> fieldsOf(String source, String className, {String? until}) {
    final from = source.indexOf('class $className');
    final body = until == null
        ? source.substring(from)
        : source.substring(from, source.indexOf(until));
    final matches = RegExp(
      r'^  (?! )(?:final |late )?[\w<>,? ()]+ (_?[a-zA-Z]\w*)\s*(?:=[^=]|;)',
      multiLine: true,
    ).allMatches(body);
    return [for (final match in matches) match.group(1)!];
  }

  test('every piece of the demo server is in the document it saves', () {
    // Nothing here belongs in the document, and each says why.
    const notKept = <String, String>{
      'latency': 'how slowly the demo answers, a setting of the app',
      'hiddenCategories': 'set only by tests: the demo has no admin to hide one',
      'phoneChecks': 'set only by tests: no demo admin to switch SMS checks off',
      '_unverifiedPhones':
          'empty unless a test turns checks off; nothing to keep in a '
          'normal demo',
      '_language': 'the language of the request being answered',
      '_arabic': 'read from _language',
      '_save': 'where to write, handed in at startup',
      '_saved': 'what was written last, to write only on a change',
      '_otpCode': 'a code sent this minute; a real one expires too',
      '_otpPhone': 'the number waiting for that code',
      '_shelfStore': 'worked out from the signed-in account',
      '_isNewAccount': 'worked out from the account',
      '_isNewStore': 'worked out from the account',
      '_merchantOrderStore': "worked out: the store's own orders",
      '_addedProducts':
          "worked out: this store's own share of "
          '_storeProducts, which is kept',
      '_bannerWordsAr': 'fixed words, the same in every build',
      '_savedStores': 'worked out from the accounts\' own stores, kept',
      '_storeFaceKeys': 'fixed field names',
      '_returnedItems': 'worked out from the returns, which are kept',
      '_stepsEn': 'fixed words',
      '_stepsAr': 'fixed words',
      '_deliveryTimes': 'fixed choices',
      '_firstOrderLimit': 'a rule, not data',
      '_returnWindow': 'a rule, not data',
      '_isStore': 'worked out from the signed-in account',
      '_ratingAsks': 'a rule, not data: how often an order is asked about',
      '_pushAddresses': 'sent again by the app at every start',
      'pushAddresses': 'the tests\' view of _pushAddresses',
      '_optionWordsAr': 'a dictionary, not data: option words in Arabic',
      '_seedCustomers': 'seed, not data: who the demo stores sold to',
      '_historyCustomers': 'seed, not data: who they sold to before today',
      '_returnReasons': 'a list of codes, not data',
      '_phoneTakenMessage': 'words, not data',
      '_storeDrivers': "seed, not data: each demo store's driver",
      '_noAccountMessage': 'words, not data',
      '_commissionPercent': 'a rule, not data',
    };

    // An account's own things are written through its snapshot, which
    // `_restore` reads back, so naming them there is enough.
    final restore = server.substring(
      server.indexOf('void _restore('),
      server.indexOf('void _openStore('),
    );

    final missing = <String>[
      for (final field in fieldsOf(server, 'MockApiInterceptor'))
        if (!notKept.containsKey(field) &&
            !saving.contains(field) &&
            !restore.contains(field))
          field,
    ];

    expect(
      missing,
      isEmpty,
      reason:
          'These are held by the demo server but never written to the '
          'phone, so closing the app would lose them: ${missing.join(', ')}. '
          'Add them to mock_state_saving.dart, or say in `notKept` why they '
          'do not belong there.',
    );
  });

  test("every account's own things are written and read back", () {
    final fields = fieldsOf(
      server,
      '_AccountSnapshot',
      until: 'class MockApiInterceptor',
    );
    expect(fields, isNotEmpty, reason: 'the snapshot fields were not found');

    final written = saving.substring(
      saving.indexOf('_accountJson('),
      saving.indexOf('bool _decodeState('),
    );
    final read = saving.substring(saving.indexOf('_accountFrom('));

    for (final field in fields) {
      expect(
        written.contains('account.$field'),
        isTrue,
        reason: "an account's $field is never written to the phone",
      );
      expect(
        read.contains("json['$field']"),
        isTrue,
        reason: "an account's $field is never read back",
      );
    }
  });
}
