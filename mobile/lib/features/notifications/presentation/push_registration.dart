import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/push_service.dart';
import '../../auth/presentation/auth_providers.dart';

/// Sends this phone's push address for whoever is signed in: at sign-in, in
/// the app's language and again when it changes, and whenever the push
/// service hands the phone a new address. Taken back at sign-out by
/// `AuthController.signOut`. Kept alive by the app itself ([SabaApp]).
final pushRegistrationProvider = Provider<void>((ref) {
  final account = ref.watch(accountIdProvider);
  if (account == null) return;

  final device = ref.watch(pushDeviceProvider);
  final push = ref.watch(pushServiceProvider);
  unawaited(push.askPermission().then((_) => device.register()));
  final changes = push.tokenChanges.listen((_) => device.register());
  ref.onDispose(changes.cancel);
});

/// Pushes the person tapped.
final pushTapsProvider = StreamProvider<PushTap>(
  (ref) => ref.watch(pushServiceProvider).taps,
);
