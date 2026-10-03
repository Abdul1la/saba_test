import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/localization/strings_ar.dart';
import 'package:saba_marketplace/core/localization/strings_en.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/core/widgets/filter_chip_row.dart';
import 'package:saba_marketplace/core/widgets/status_timeline.dart';
import 'package:saba_marketplace/features/returns/domain/entities.dart';

/// The design rules Batch 2 introduced for the screens that come after the
/// sale. The parsing and repository rules for the same screens live in
/// after_sale_test.dart.
void main() {
  Widget host(Widget child, {Locale locale = const Locale('en')}) {
    return MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  group('a return reason is words, never the code behind it', () {
    // The bug this pins (WORK-LOG F27): the reason list was six bare strings
    // printed by replacing underscores with spaces, so an Arabic customer
    // chose between "DAMAGED" and "WRONG ITEM". The code the backend stores
    // and the words the customer reads are two different things.
    String keyFor(ReturnReason reason) {
      final name = reason.name;
      return 'returnReason${name[0].toUpperCase()}${name.substring(1)}';
    }

    test('every reason has an English and an Arabic sentence', () {
      for (final reason in ReturnReason.values) {
        final key = keyFor(reason);
        expect(
          stringsEn[key],
          isNotNull,
          reason: '$key is missing from the English strings',
        );
        expect(
          stringsAr[key],
          isNotNull,
          reason: '$key is missing from the Arabic strings',
        );
        expect(stringsAr[key], isNot(stringsEn[key]));
      }
    });

    test('no reason is shown as its API constant', () {
      for (final reason in ReturnReason.values) {
        for (final label in [
          stringsEn[keyFor(reason)]!,
          stringsAr[keyFor(reason)]!,
        ]) {
          expect(label, isNot(contains('_')));
          expect(label.toUpperCase(), isNot(equals(reason.apiValue)));
          expect(
            label,
            isNot(equals(reason.apiValue.replaceAll('_', ' '))),
            reason: 'that is the old underscore-stripping output',
          );
        }
      }
    });

    test('the API value the server stores is untouched', () {
      // The words may be translated freely; these codes may not change.
      expect(ReturnReason.damaged.apiValue, 'DAMAGED');
      expect(ReturnReason.wrongItem.apiValue, 'WRONG_ITEM');
      expect(ReturnReason.notAsDescribed.apiValue, 'NOT_AS_DESCRIBED');
      expect(ReturnReason.missingParts.apiValue, 'MISSING_PARTS');
      expect(ReturnReason.changedMind.apiValue, 'CHANGED_MIND');
      expect(ReturnReason.other.apiValue, 'OTHER');
    });
  });

  group('the progress trail says where the customer actually is', () {
    List<TimelineEntry> ladder(int reachedIndex) => <TimelineEntry>[
      for (var i = 0; i < 4; i++)
        TimelineEntry(label: 'Step $i', isDone: i <= reachedIndex),
    ];

    testWidgets('a half-finished trail fills only what is reached', (
      tester,
    ) async {
      await tester.pumpWidget(host(StatusTimeline(entries: ladder(1))));

      // A reached stop is bold, a stop still to come is not. If they all
      // looked alike the trail would answer nothing, which is the whole
      // reason it exists.
      final reached = tester.widget<Text>(find.text('Step 1'));
      final pending = tester.widget<Text>(find.text('Step 2'));
      expect(reached.style?.fontWeight, FontWeight.w600);
      expect(pending.style?.fontWeight, FontWeight.w400);
    });

    testWidgets('nothing reached yet leaves every stop quiet', (tester) async {
      await tester.pumpWidget(host(StatusTimeline(entries: ladder(-1))));

      for (var i = 0; i < 4; i++) {
        expect(
          tester.widget<Text>(find.text('Step $i')).style?.fontWeight,
          FontWeight.w400,
        );
      }
    });

    testWidgets('an empty trail draws nothing rather than an empty box', (
      tester,
    ) async {
      await tester.pumpWidget(host(const StatusTimeline(entries: [])));
      expect(find.byType(IntrinsicHeight), findsNothing);
    });
  });

  group('status filter chips', () {
    // These replaced the nine-tab TabBar on Orders and the six-tab one on
    // Returns (WORK-LOG F29). A tab bar built one live list per tab; this
    // filters one list. The label must always be visible — unlike the
    // category chips, a status cannot be drawn as an icon.
    testWidgets('every chip shows its word, chosen or not', (tester) async {
      await tester.pumpWidget(
        host(
          TextFilterChips(
            labels: const ['All', 'Shipped', 'Delivered'],
            selectedIndex: 1,
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Shipped'), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
    });

    testWidgets('tapping a chip reports its index', (tester) async {
      int? tapped;
      await tester.pumpWidget(
        host(
          TextFilterChips(
            labels: const ['All', 'Shipped', 'Delivered'],
            selectedIndex: 0,
            onSelected: (index) => tapped = index,
          ),
        ),
      );

      await tester.tap(find.text('Delivered'));
      expect(tapped, 2);
    });
  });
}
