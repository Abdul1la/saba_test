// The reviewer, and the user's decision (2026-09-30): the server marks only
// Saba's staff as having a verified email, so an older account with an
// email showed "Verify your email", which led to a screen that cannot work:
// v1 sends no email. The card is gone, and since the final review
// (2026-10-01) the /verify-email route and its screen too.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/localization/app_localizations.dart';
import 'package:saba_marketplace/core/providers/core_providers.dart';
import 'package:saba_marketplace/core/storage/app_preferences.dart';
import 'package:saba_marketplace/core/theme/app_theme.dart';
import 'package:saba_marketplace/features/auth/domain/entities.dart';
import 'package:saba_marketplace/features/auth/presentation/auth_providers.dart';
import 'package:saba_marketplace/features/profile/presentation/screens/account_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('an unverified email asks for nothing', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await AppPreferences.create();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferencesProvider.overrideWithValue(preferences),
          currentUserProvider.overrideWithValue(
            const User(
              id: 'u-1',
              fullName: 'Amina Saleh',
              email: 'amina@example.com',
              role: UserRole.customer,
              status: AccountStatus.active,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AccountScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Amina Saleh'), findsOneWidget, reason: 'not drawn');
    expect(find.text('Verify your email'), findsNothing);
    // The demo server answers the unread count after a delay.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
