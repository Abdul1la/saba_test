// M9: "report a review" had no test. The sheet asks for a reason before it
// sends, in the reader's language, and hands back the code with the words
// (the server now keeps the words).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/features/reviews/presentation/widgets/report_dialog.dart';

void main() {
  for (final code in ['en', 'ar']) {
    testWidgets('a report needs a reason and keeps the words ($code)', (
      tester,
    ) async {
      final l10n = AppLocalizations(Locale(code));
      ReportChoice? chosen;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(code),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => chosen = await ReportDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.reportReview), findsOneWidget);
      for (final reason in [
        l10n.reportCounterfeit,
        l10n.reportProhibited,
        l10n.reportMisleading,
        l10n.reportOffensive,
        l10n.reportSpam,
        l10n.reportOther,
      ]) {
        expect(find.text(reason), findsOneWidget);
      }

      // No reason: it says so and sends nothing.
      await tester.tap(find.text(l10n.submit));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reportReasonRequired), findsOneWidget);
      expect(chosen, isNull);

      await tester.tap(find.text(l10n.reportOffensive));
      await tester.enterText(find.byType(TextField), 'Rude words.');
      await tester.tap(find.text(l10n.submit));
      await tester.pumpAndSettle();
      expect(chosen?.apiValue, 'OFFENSIVE');
      expect(chosen?.description, 'Rude words.');
    });
  }
}
