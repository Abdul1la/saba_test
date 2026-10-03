// The new logo: its name follows the app's language, it turns white where
// purple would sink into a dark page, a store without a logo shows it, and
// the phone's icon is drawn from the same paths as the one in the app.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/core/widgets/saba_logo.dart';
import 'package:saba_marketplace/core/widgets/store_card.dart';

void main() {
  Widget host(Widget child, {String language = 'en', bool dark = false}) =>
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        locale: Locale(language),
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('the name is in the app\'s language', (tester) async {
    await tester.pumpWidget(host(const SabaLogo()));
    expect(find.text('Saba'), findsOneWidget);

    await tester.pumpWidget(host(const SabaLogo(), language: 'ar'));
    expect(find.text('سبأ'), findsOneWidget);
    expect(find.text('Saba'), findsNothing);
  });

  testWidgets('purple on a light page, white on a dark one', (tester) async {
    SabaMarkTone tone() => tester.widget<SabaMark>(find.byType(SabaMark)).tone;

    await tester.pumpWidget(host(const SabaLogo()));
    expect(tone(), SabaMarkTone.purple);

    await tester.pumpWidget(host(const SabaLogo(), dark: true));
    await tester.pumpAndSettle();
    expect(tone(), SabaMarkTone.white);
  });

  testWidgets('a store with no logo shows the mark', (tester) async {
    await tester.pumpWidget(host(StoreCard(name: 'New store', onTap: () {})));
    expect(find.byType(SabaMark), findsOneWidget);
  });

  test('the phone\'s icon is drawn from the mark\'s paths', () {
    for (final file in [
      'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
      'android/app/src/main/res/drawable/saba_splash_mark.xml',
    ]) {
      final vector = File(file).readAsStringSync();
      expect(vector, contains(SabaMark.bagPath), reason: file);
      expect(vector, contains(SabaMark.diamondPath), reason: file);
    }
  });
}
