import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/localization/strings_ar.dart';
import 'package:saba_marketplace/core/localization/strings_en.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/core/theme/saba_icons.dart';
import 'package:saba_marketplace/core/widgets/saba_tile.dart';
import 'package:saba_marketplace/core/widgets/section_header.dart';
import 'package:saba_marketplace/features/support/presentation/support_providers.dart';

/// The rules Batch 3 introduced for the account, settings and support screens.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  group('a support category is words, never the code behind it', () {
    // The same bug as the return reasons (WORK-LOG F27), found again in a
    // different screen: the dropdown listed ORDER, PAYMENT, DELIVERY, so an
    // Arabic customer picked from English constants.
    String keyFor(TicketCategory category) {
      const overrides = <TicketCategory, String>{
        TicketCategory.returnRequest: 'ticketCategoryReturn',
      };
      if (overrides.containsKey(category)) return overrides[category]!;
      final name = category.name;
      return 'ticketCategory'
          '${name[0].toUpperCase()}${name.substring(1)}';
    }

    test('every category has an English and an Arabic sentence', () {
      for (final category in TicketCategory.values) {
        final key = keyFor(category);
        expect(stringsEn[key], isNotNull, reason: '$key missing from English');
        expect(stringsAr[key], isNotNull, reason: '$key missing from Arabic');
        expect(stringsAr[key], isNot(stringsEn[key]));
      }
    });

    test('no category is shown as its API constant', () {
      for (final category in TicketCategory.values) {
        for (final label in [
          stringsEn[keyFor(category)]!,
          stringsAr[keyFor(category)]!,
        ]) {
          expect(label, isNot(contains('_')));
          expect(label.toUpperCase(), isNot(equals(category.apiValue)));
        }
      }
    });

    test('the API value the server stores is untouched', () {
      expect(TicketCategory.order.apiValue, 'ORDER');
      expect(TicketCategory.returnRequest.apiValue, 'RETURN');
      expect(TicketCategory.other.apiValue, 'OTHER');
      expect(
        TicketCategory.values.map((c) => c.apiValue).toSet(),
        hasLength(TicketCategory.values.length),
        reason: 'two categories sharing a code would be stored as one',
      );
    });
  });

  group('no product grid guesses its own height', () {
    // This bug has now appeared three times: the catalogue card overflowed
    // because heightFor added the wrong number (F23), and the wishlist (F38)
    // and storefront (F44) grids each guessed with a childAspectRatio. A
    // ratio cannot know the text scale the reader has chosen, so the card
    // overflows for anyone who has made the type bigger.
    test('no screen pairs childAspectRatio with a product card', () {
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // Only real usage counts; a comment recalling the old value is a
        // record of the fix, not a repeat of it.
        final source = entity
            .readAsLinesSync()
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');
        if (!source.contains('childAspectRatio:')) continue;
        if (source.contains('ProductCard') ||
            source.contains('ConnectedProductCard')) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these grids must ask ProductCard.heightFor instead of guessing a '
            'ratio: ${offenders.join(", ")}',
      );
    });
  });

  group('a settings row promises only what it does', () {
    testWidgets('a row that navigates shows a chevron', (tester) async {
      await tester.pumpWidget(host(SabaTile(label: 'Addresses', onTap: () {})));

      final icon = tester.widget<SabaIcon>(find.byType(SabaIcon));
      expect(icon.icon, SabaIcons.chevronRight);
    });

    testWidgets('a row that toggles shows its control, not an arrow', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SabaTile(
            label: 'Push',
            onTap: () {},
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
        ),
      );

      // An arrow beside a switch promises a screen that does not exist.
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(SabaIcon), findsNothing);
    });

    testWidgets('a row with nothing to do is not tappable', (tester) async {
      await tester.pumpWidget(host(const SabaTile(label: 'Version 1.0')));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('a group title sits above its card, not in its corner', (
      tester,
    ) async {
      // Inside the card the title shared the zero padding the rows need, and
      // was jammed against the card's edge on Account and Settings.
      await tester.pumpWidget(
        host(
          TileGroup(
            title: 'Your account',
            tiles: [SabaTile(label: 'Addresses', onTap: () {})],
          ),
        ),
      );

      expect(
        find.ancestor(
          of: find.text('Your account'),
          matching: find.byType(SectionCard),
        ),
        findsNothing,
      );
      expect(
        tester.getBottomLeft(find.text('Your account')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(SectionCard)).dy),
      );
    });
  });

  test('every navigation icon has the solid twin its selected tab draws', () {
    // The selected tab draws `<icon>-fill.svg`. A tab added with an icon
    // that has no twin would show a broken image the moment it is chosen.
    final shells = File('lib/core/router/app_shells.dart').readAsStringSync();
    final icons = File('lib/core/theme/saba_icons.dart').readAsStringSync();
    final used = RegExp(
      r'icon: SabaIcons\.(\w+)',
    ).allMatches(shells).map((m) => m[1]!).toSet();
    expect(used, isNotEmpty);

    final missing = <String>[];
    for (final name in used) {
      final file = RegExp(
        'static final String $name = _i\\(\'([^\']+)\'\\)',
      ).firstMatch(icons)![1]!;
      if (!File('assets/icons/$file-fill.svg').existsSync()) missing.add(file);
    }
    expect(missing, isEmpty, reason: 'no -fill.svg for: $missing');
  });

  test('every phone number on screen is kept in one piece', () {
    // In Arabic a leading plus is a neutral character, so a bare number was
    // drawn "9647701234567+". Every place that shows one wraps it in
    // Formatters.ltrIsolate; a new one that does not fails here.
    final bare = [
      RegExp(r'Text\(\s*[\w.]*[pP]hone!?\s*,'),
      RegExp(r'\$\{[\w.]*[pP]hone!?\}'),
    ];
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final pattern in bare) {
        for (final match in pattern.allMatches(source)) {
          offenders.add('${entity.path}: ${match[0]}');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
