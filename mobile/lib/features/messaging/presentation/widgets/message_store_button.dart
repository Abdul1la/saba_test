import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../messaging_providers.dart';

/// "Message": opens the customer's chat with a store, starting one if there
/// is none, from wherever the customer meets the store - the product, the
/// store's page, an order. Signed out, it opens sign-in, as every account
/// action does. A store owner does not message stores, so it is not shown.
class MessageStoreButton extends ConsumerStatefulWidget {
  const MessageStoreButton({
    super.key,
    required this.merchantId,
    this.about,
    this.variant = AppButtonVariant.secondary,
  });

  final String merchantId;

  /// The first words of the message, naming the product or order it is
  /// about, so the store is not left asking "which one?".
  final String? about;

  /// Outline on a card; filled where it sits on a photograph.
  final AppButtonVariant variant;

  @override
  ConsumerState<MessageStoreButton> createState() => _MessageStoreButtonState();
}

class _MessageStoreButtonState extends ConsumerState<MessageStoreButton> {
  bool _isOpening = false;

  Future<void> _open() async {
    if (!ref.read(isAuthenticatedProvider)) {
      context.push(AppRoutes.login);
      return;
    }

    setState(() => _isOpening = true);
    final result = await ref
        .read(messagingRepositoryProvider)
        .startWithStore(widget.merchantId);

    if (!mounted) return;
    setState(() => _isOpening = false);

    result.fold(
      ok: (chat) => context.push(
        AppRoutes.conversationPath(chat.id),
        extra: widget.about,
      ),
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentRoleProvider).isMerchant) {
      return const SizedBox.shrink();
    }

    return AppButton(
      label: context.l10n.message,
      icon: SabaIcons.message,
      variant: widget.variant,
      size: AppButtonSize.small,
      expand: false,
      isLoading: _isOpening,
      onPressed: _open,
    );
  }
}
