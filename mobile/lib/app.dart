import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/app_localizations.dart';
import 'core/providers/core_providers.dart';
import 'core/router/app_router.dart';
import 'core/router/app_shells.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_typography.dart';
import 'features/notifications/presentation/live_channel_provider.dart';
import 'features/notifications/presentation/notification_destination.dart';
import 'features/notifications/presentation/notifications_providers.dart';
import 'features/notifications/presentation/push_registration.dart';

/// The application root.
///
/// Locale and theme are read from providers, so switching either in Settings
/// rebuilds the whole tree, flips text direction for Arabic and re-renders in
/// the chosen brightness (specification sections 15, 17 and 60).
class SabaApp extends ConsumerWidget {
  const SabaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeControllerProvider);
    final themeMode = ref.watch(themeControllerProvider);
    // Kept listening, so it clears the moment someone signs out: unheard,
    // it was paused and kept the last visit's marks.
    ref.listen(deliveryAskedProvider, (_, _) {});
    // The server's live changes, for as long as someone is signed in.
    ref.listen(liveChannelProvider, (_, _) {});
    // This phone's push address, for whoever is signed in.
    ref.listen(pushRegistrationProvider, (_, _) {});
    // A tapped push opens what its notification opens in the list, and
    // counts as reading it.
    ref.listen(pushTapsProvider, (_, next) {
      final tap = next.value;
      if (tap == null) return;
      if (tap.notificationId case final id?) {
        ref.read(notificationsRepositoryProvider).markRead(id);
      }
      final to = notificationDestination(tap.targetType, tap.targetId);
      if (to != null) router.push(to);
    });

    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,

      // `null` follows the device; `localeResolutionCallback` then falls back
      // to English for any language we do not ship.
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (deviceLocale, supported) {
        if (deviceLocale == null) return supported.first;
        for (final candidate in supported) {
          if (candidate.languageCode == deviceLocale.languageCode) {
            return candidate;
          }
        }
        return supported.first;
      },
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,

      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,

      builder: (context, child) {
        // Cap text scaling so an extreme accessibility setting cannot break
        // prices and buttons out of their containers.
        final scale = MediaQuery.textScalerOf(
          context,
        ).clamp(minScaleFactor: 0.85, maxScaleFactor: 1.4);

        // Arabic gets +0.12 line height at every level and drops the negative
        // tracking, which is a Latin-only optical fix. Applied here because
        // this builder sits below `Localizations`, so it sees the *resolved*
        // locale - still correct when the user left the language on "follow
        // device". Doing it here means no screen has to think about it.
        final theme = Theme.of(context);
        final isArabic = Localizations.localeOf(context).languageCode == 'ar';

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: isArabic
              ? Theme(
                  data: theme.copyWith(
                    textTheme: AppTypography.arabic(theme.textTheme),
                  ),
                  child: child ?? const SizedBox.shrink(),
                )
              : child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
