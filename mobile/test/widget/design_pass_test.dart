// The design pass: one type hierarchy on every screen, and three button
// levels, so a main action reads as the main action.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/theme/app_colors.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/core/theme/app_typography.dart';
import 'package:saba_marketplace/core/widgets/app_button.dart';
import 'package:saba_marketplace/core/widgets/app_dialogs.dart';
import 'package:saba_marketplace/core/widgets/section_header.dart';

void main() {
  Widget host(Widget child, {String language = 'en'}) => MaterialApp(
    theme: AppTheme.light(),
    locale: Locale(language),
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  TextStyle styleOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!;

  group('every kind of title is set in the heading font', () {
    for (final (language, family) in [
      ('en', AppTypography.headingFamily),
      ('ar', AppTypography.headingFamilyArabic),
    ]) {
      testWidgets('in $language', (tester) async {
        await tester.pumpWidget(
          host(
            language: language,
            const Column(
              children: [
                SabaAppBar(title: 'Bar title'),
                PageTitle(title: 'Screen title'),
                SectionHeader(title: 'Section title'),
                SectionCard(title: 'Card section', child: SizedBox()),
                StepHeader(number: 1, title: 'Step title'),
              ],
            ),
          ),
        );
        for (final title in [
          'Bar title',
          'Screen title',
          'Section title',
          'Card section',
          'Step title',
        ]) {
          expect(styleOf(tester, title).fontFamily, family, reason: title);
        }
        // The hierarchy: a screen's title over a section's, over a card's.
        expect(
          styleOf(tester, 'Screen title').fontSize!,
          greaterThan(styleOf(tester, 'Section title').fontSize!),
        );
        expect(
          styleOf(tester, 'Section title').fontSize!,
          greaterThan(styleOf(tester, 'Card section').fontSize!),
        );
      });
    }

    testWidgets('a dialog\'s title too', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  AppDialogs.confirm(context, title: 'Sure?', message: 'Why'),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final title = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(title.titleTextStyle?.fontFamily, AppTypography.headingFamily);
    });
  });

  testWidgets('an Arabic heading is set larger, so it is not timid', (
    tester,
  ) async {
    await tester.pumpWidget(host(const SectionHeader(title: 'a')));
    final english = styleOf(tester, 'a').fontSize!;
    await tester.pumpWidget(
      host(const SectionHeader(title: 'a'), language: 'ar'),
    );
    final arabic = styleOf(tester, 'a').fontSize!;
    expect(arabic, english * AppTypography.headingScaleArabic);
    expect(arabic, greaterThan(english));
  });

  group('three button levels', () {
    Future<ButtonStyleButton> draw(
      WidgetTester tester,
      AppButtonVariant variant,
    ) async {
      await tester.pumpWidget(
        host(AppButton(label: 'Go', variant: variant, onPressed: () {})),
      );
      return tester.widget<ButtonStyleButton>(
        find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
    }

    Color? resolve(WidgetStateProperty<Color?>? property) =>
        property?.resolve(<WidgetState>{});

    testWidgets('primary: solid purple, white words', (tester) async {
      final button = await draw(tester, AppButtonVariant.primary);
      expect(button, isA<FilledButton>());
      final theme = AppTheme.light().filledButtonTheme.style!;
      expect(resolve(theme.backgroundColor), AppPalette.primary);
    });

    testWidgets('secondary: outlined, purple words on white', (tester) async {
      final button = await draw(tester, AppButtonVariant.secondary);
      expect(button, isA<OutlinedButton>());
      final theme = AppTheme.light().outlinedButtonTheme.style!;
      expect(resolve(theme.foregroundColor), AppPalette.primary);
      expect(resolve(theme.backgroundColor), AppPalette.surface);
      expect(theme.side?.resolve(<WidgetState>{})?.color, AppPalette.primary);
    });

    testWidgets('tertiary: words only, purple', (tester) async {
      final button = await draw(tester, AppButtonVariant.text);
      expect(button, isA<TextButton>());
      final theme = AppTheme.light().textButtonTheme.style!;
      expect(resolve(theme.foregroundColor), AppPalette.primary);
    });

    testWidgets('destructive: red', (tester) async {
      final button = await draw(tester, AppButtonVariant.danger);
      expect(resolve(button.style!.backgroundColor), AppPalette.error);
    });

    test('and no fourth look: the old tonal and outline are one level', () {
      expect(AppButtonVariant.values.map((v) => v.name), [
        'primary',
        'secondary',
        'text',
        'danger',
        'dangerText',
      ]);
    });
  });
}
