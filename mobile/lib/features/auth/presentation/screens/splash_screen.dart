import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/widgets/saba_logo.dart';
import '../../../../core/widgets/state_views.dart';
import '../auth_providers.dart';

/// Shown while the stored session is being validated against the backend.
///
/// The logo in white on the logo's purple, in the app's language - the same
/// purple the phone's own launch screen shows, so one follows the other
/// without a cut.
///
/// If that check fails for a transport reason the user is not thrown back to
/// the sign-in form — they get an explanation and a retry, because their
/// credentials are probably fine and the network is not.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    // The explanation is written for the page, not for purple.
    if (auth case AsyncError(:final error)) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SabaLogo(),
                  const SizedBox(height: AppSpacing.xl),
                  AppErrorView(
                    failure: ErrorMapper.fromObject(error),
                    onRetry: () =>
                        ref.read(authControllerProvider.notifier).retry(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Loading, or resolved: the router moves on as soon as it has resolved,
    // so that is only ever visible for a frame.
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppPalette.brand,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SabaLogo(size: 56, tone: SabaMarkTone.white),
              SizedBox(height: AppSpacing.xxxl),
              CircularProgressIndicator(color: AppPalette.textOnDark),
            ],
          ),
        ),
      ),
    );
  }
}
