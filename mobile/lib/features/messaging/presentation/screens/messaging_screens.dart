import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../media/domain/entities.dart';
import '../../../media/presentation/media_providers.dart';
import '../../../reviews/presentation/widgets/report_dialog.dart';
import '../messaging_providers.dart';
import 'photo_viewer_screen.dart';
import '../../../../core/widgets/section_header.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: SabaAppBar(title: l10n.messages),
      body: AsyncStateView<List<Conversation>>(
        value: conversations,
        onRetry: () => ref.invalidate(conversationsProvider),
        loadingBuilder: (_) => const ListSkeleton(itemHeight: 64),
        builder: (items) {
          if (items.isEmpty) {
            // Says where a chat starts, which a blank list never did.
            return EmptyStateView(
              title: l10n.emptyConversations,
              message: ref.watch(currentRoleProvider).isMerchant
                  ? l10n.emptyConversationsStoreHint
                  : l10n.emptyConversationsHint,
              icon: SabaIcons.message,
            );
          }

          // A customer writes to stores, a store to customers.
          final withStores = !ref.watch(currentRoleProvider).isMerchant;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(conversationsProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.sm,
                AppSpacing.screenGutter,
                AppSpacing.xl,
              ),
              children: [
                // One card of rows, the way Account groups its own.
                Material(
                  color: context.colors.surface,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    side: BorderSide(color: context.market.border),
                  ),
                  child: Column(
                    children: [
                      for (var index = 0; index < items.length; index++) ...[
                        if (index > 0)
                          Divider(
                            height: 1,
                            indent: 78,
                            color: context.market.border,
                          ),
                        _ConversationRow(
                          conversation: items[index],
                          withStore: withStores,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One chat in the list: who, what they said last, when, and how many of
/// their words are still unread - the name, the time and the count all
/// louder while there are.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation, required this.withStore});

  final Conversation conversation;
  final bool withStore;

  /// The time today, "Yesterday", or the date.
  String _when(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final at = conversation.updatedAt.toLocal();
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    return switch (days) {
      0 => Formatters.time(at, locale: locale),
      1 => l10n.yesterday,
      _ => Formatters.monthDay(at, locale: locale),
    };
  }

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final unread = conversation.unreadCount > 0;
    // A photo has no words: the row says "Photo" in their place.
    final preview = conversation.lastMessageIsPhoto
        ? context.l10n.photo
        : conversation.lastMessage ?? conversation.subtitle ?? '';

    return InkWell(
      onTap: () => context.push(AppRoutes.conversationPath(conversation.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md + 2,
        ),
        child: Row(
          children: [
            _ChatAvatar(
              title: conversation.title,
              url: conversation.avatarUrl,
              square: withStore,
            ),
            const SizedBox(width: AppSpacing.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleSmall?.copyWith(
                            fontSize: 15,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _when(context),
                        style: context.textStyles.labelSmall?.copyWith(
                          color: unread ? market.accent : market.textMuted,
                          fontWeight: unread ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodySmall?.copyWith(
                            fontSize: 13,
                            color: unread
                                ? context.colors.onSurface
                                : context.colors.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.w500 : null,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          height: 20,
                          constraints: const BoxConstraints(minWidth: 20),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: market.accent,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '${conversation.unreadCount}',
                            style: context.textStyles.labelSmall?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: market.onAccent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The other side's logo, or their initials on a colour of their own - the
/// same colour every time, so a chat is found by it. A store is square, a
/// person round, as the store's own header draws them.
class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.title,
    required this.url,
    required this.square,
  });

  final String title;
  final String? url;
  final bool square;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final tints = <(Color, Color)>[
      (market.info, market.infoSoft),
      (market.accent, market.accentSoft),
      (market.success, market.successSoft),
      (market.warning, market.warningSoft),
    ];
    final (ink, fill) =
        tints[title.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
            tints.length];
    final initials = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    final radius = square ? AppRadius.action : _size / 2;

    return AppNetworkImage(
      url: url,
      width: _size,
      height: _size,
      radius: radius,
      fallback: Container(
        width: _size,
        height: _size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: context.textStyles.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ),
    );
  }
}

/// A single chat thread.
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    this.initialDraft,
  });

  final String conversationId;

  /// Words already in the box when the chat opens - "About Nova X5: " -
  /// for the customer to finish. Nothing is sent until they press send.
  final String? initialDraft;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  // "About order SB-100015:" sits above the box, not in it: in the box a
  // tap could land inside it, and a message went out as "About order
  // SB-1000Hello…15:" (the tester). It leads the first message sent.
  late String? _about = widget.initialDraft?.trim();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final typed = _controller.text.trim();
    if (typed.isEmpty || _isSending) return;
    final body = _about == null ? typed : '$_about $typed';

    setState(() => _isSending = true);

    final result = await ref
        .read(conversationProvider(widget.conversationId).notifier)
        .send(body);

    if (!mounted) return;
    setState(() => _isSending = false);

    result.fold(
      ok: (_) {
        _controller.clear();
        setState(() => _about = null);
        _scrollToBottom();
      },
      err: (failure) {
        AppSnackBar.failure(context, failure);
        // Blocked from the other side meanwhile: the box gives way to the
        // line that says so.
        if (failure is ConflictFailure) {
          ref.invalidate(conversationInfoProvider(widget.conversationId));
        }
      },
    );
  }

  /// A photo, from the gallery or the camera, sent to the chat. The picker
  /// shrinks it to 1600px at quality 82, as product photos (§43); the server
  /// strips any location and signs a link back.
  Future<void> _pickPhoto() async {
    if (_isSending) return;
    final fromCamera = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SabaIcon(SabaIcons.image, size: AppSizes.iconMd),
              title: Text(context.l10n.chooseFromGallery),
              onTap: () => Navigator.of(context).pop(false),
            ),
            ListTile(
              leading: SabaIcon(SabaIcons.camera, size: AppSizes.iconMd),
              title: Text(context.l10n.takePhoto),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (fromCamera == null || !mounted) return;

    final picker = ref.read(mediaPickerProvider);
    const constraints = MediaConstraints.chatPhoto;
    final PickedMedia? photo;
    if (fromCamera) {
      photo = await picker.captureImage(constraints: constraints);
    } else {
      final picked = await picker.pickImages(
        constraints: constraints,
        multiple: false,
      );
      photo = picked.isEmpty ? null : picked.first;
    }
    if (photo == null || !mounted) return;

    setState(() => _isSending = true);
    final result = await ref
        .read(conversationProvider(widget.conversationId).notifier)
        .sendPhoto(photo);
    if (!mounted) return;
    setState(() => _isSending = false);

    result.fold(
      ok: (_) => _scrollToBottom(),
      err: (failure) {
        AppSnackBar.failure(context, failure);
        if (failure is ConflictFailure) {
          ref.invalidate(conversationInfoProvider(widget.conversationId));
        }
      },
    );
  }

  /// Blocks the other side, once asked; or lifts this side's own block.
  Future<void> _setBlocked(bool blocked) async {
    final l10n = context.l10n;
    if (blocked) {
      final confirmed = await AppDialogs.confirm(
        context,
        title: l10n.blockTitle,
        message: l10n.blockMessage,
        confirmLabel: l10n.block,
        isDestructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    final result = await ref
        .read(messagingRepositoryProvider)
        .setBlocked(widget.conversationId, blocked: blocked);
    if (!mounted) return;
    result.fold(
      ok: (_) =>
          ref.invalidate(conversationInfoProvider(widget.conversationId)),
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final messages = ref.watch(conversationProvider(widget.conversationId));
    // Who this is with: the store, or for a store the customer. It said
    // "Messages" on every chat.
    final info = ref
        .watch(conversationInfoProvider(widget.conversationId))
        .value;
    final withWhom = info?.title;

    return Scaffold(
      appBar: SabaAppBar(
        title: withWhom == null || withWhom.isEmpty ? l10n.messages : withWhom,
        // Report the chat to Saba, or block the other side (Apple 1.2).
        trailing: info == null
            ? null
            : _ChatMenu(
                blockedByMe: info.blockedByMe,
                onReport: () => reportToSaba(
                  context,
                  ref,
                  target: ReportTarget.conversation,
                  id: widget.conversationId,
                ),
                onBlock: () => _setBlocked(!info.blockedByMe),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AsyncStateView<List<Message>>(
              value: messages,
              onRetry: () =>
                  ref.invalidate(conversationProvider(widget.conversationId)),
              builder: (items) {
                if (items.isEmpty) {
                  // Inside an open thread, "No conversations yet" told the
                  // customer they had none while they were looking at one.
                  return EmptyStateView(
                    title: l10n.noMessagesYet,
                    message: l10n.noMessagesYetMessage,
                    icon: SabaIcons.message,
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.screenGutter),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _MessageBubble(message: items[index]),
                );
              },
            ),
          ),
          // Blocked by either side: nobody writes, and the chat stays
          // readable. Only the side that blocked can lift its block.
          if (info?.blocked ?? false)
            _BlockedBar(
              byMe: info!.blockedByMe,
              onUnblock: () => _setBlocked(false),
            )
          else ...[
            if (_about case final about?)
              _AboutLabel(
                text: about,
                onRemove: () => setState(() => _about = null),
              ),
            _Composer(
              controller: _controller,
              isSending: _isSending,
              onSend: _send,
              onPhoto: _pickPhoto,
              // Started with a draft, the keyboard is where the customer is
              // going next.
              autofocus: widget.initialDraft != null,
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final locale = context.l10n.locale.toLanguageTag();
    final isMine = message.isMine;

    return Align(
      alignment: isMine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(maxWidth: context.screenWidth * 0.75),
        decoration: BoxDecoration(
          color: isMine ? context.colors.primary : context.market.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMine && message.senderName != null)
              Text(message.senderName!, style: context.textStyles.labelSmall),
            if (message.isPhoto)
              _PhotoBubble(message: message, isMine: isMine)
            else
              Text(
                message.body,
                style: context.textStyles.bodyMedium?.copyWith(
                  color: isMine ? context.colors.onPrimary : null,
                ),
              ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              Formatters.time(message.sentAt, locale: locale),
              style: context.textStyles.labelSmall?.copyWith(
                color: isMine
                    ? context.colors.onPrimary.withValues(alpha: 0.75)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A photo in a message: the picture, which opens full size on a tap, or a
/// line where a removed one was.
class _PhotoBubble extends StatelessWidget {
  const _PhotoBubble({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final onColor = isMine ? context.colors.onPrimary : null;

    if (message.photoRemoved case final removed?) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SabaIcon(SabaIcons.imageOff, size: AppSizes.iconSm, color: onColor),
          const SizedBox(width: AppSpacing.xs),
          Text(
            removed == PhotoRemoval.saba
                ? l10n.photoRemovedBySaba
                : l10n.photoDeleted,
            style: context.textStyles.bodySmall?.copyWith(
              color: onColor,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PhotoViewerScreen(
            url: message.photoUrl!,
            conversationId: _conversationIdOf(context),
          ),
          fullscreenDialog: true,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: context.screenWidth * 0.6,
          maxHeight: 260,
        ),
        child: AppNetworkImage(
          url: message.photoUrl,
          fit: BoxFit.cover,
          radius: AppRadius.sm,
        ),
      ),
    );
  }

  /// The chat this bubble sits in, so the viewer can reload it when a link
  /// has expired.
  static String? _conversationIdOf(BuildContext context) => context
      .findAncestorWidgetOfExactType<ConversationScreen>()
      ?.conversationId;
}

/// What the first message is about, above the box and out of the way of
/// typing; the cross leaves it off.
class _AboutLabel extends StatelessWidget {
  const _AboutLabel({required this.text, required this.onRemove});

  final String text;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.surface,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.remove,
            onPressed: onRemove,
            icon: SabaIcon(SabaIcons.close, size: AppSizes.iconSm),
          ),
        ],
      ),
    );
  }
}

/// Report the chat, and block or unblock the other side.
class _ChatMenu extends StatelessWidget {
  const _ChatMenu({
    required this.blockedByMe,
    required this.onReport,
    required this.onBlock,
  });

  final bool blockedByMe;
  final VoidCallback onReport;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<VoidCallback>(
      tooltip: l10n.moreOptions,
      icon: SabaIcon(SabaIcons.moreVertical, size: AppSizes.iconMd),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(value: onReport, child: Text(l10n.report)),
        PopupMenuItem(
          value: onBlock,
          child: Text(blockedByMe ? l10n.unblock : l10n.block),
        ),
      ],
    );
  }
}

/// In place of the box while the chat is blocked: why nobody can write, and
/// for the side that blocked, the way back.
class _BlockedBar extends StatelessWidget {
  const _BlockedBar({required this.byMe, required this.onUnblock});

  final bool byMe;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.market.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                byMe ? l10n.chatBlockedByMe : l10n.chatBlocked,
                style: context.textStyles.bodyMedium,
              ),
            ),
            if (byMe)
              TextButton(onPressed: onUnblock, child: Text(l10n.unblock)),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onPhoto,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onPhoto;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.market.border)),
        ),
        child: Row(
          children: [
            // A photo, from the gallery or the camera (§43).
            IconButton(
              onPressed: isSending ? null : onPhoto,
              icon: SabaIcon(SabaIcons.image, size: AppSizes.iconMd),
              tooltip: context.l10n.sendPhoto,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(hintText: context.l10n.typeMessage),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: isSending ? null : onSend,
              icon: isSending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  // The design's own plane, which SabaIcon turns round in
                  // Arabic. Material's send_rounded never mirrored, so the
                  // arrow pointed away from the way the message travels.
                  : SabaIcon(SabaIcons.send, size: AppSizes.iconMd),
              tooltip: context.l10n.send,
            ),
          ],
        ),
      ),
    );
  }
}
