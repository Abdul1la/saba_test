import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/option_sheet.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/saba_tile.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/sticky_bar.dart';
import '../support_providers.dart';

String _statusLabel(BuildContext context, TicketStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    TicketStatus.open => l10n.ticketStatusOpen,
    TicketStatus.inProgress => l10n.ticketStatusInProgress,
    TicketStatus.waitingForCustomer => l10n.ticketStatusWaiting,
    TicketStatus.resolved => l10n.ticketStatusResolved,
    TicketStatus.closed => l10n.ticketStatusClosed,
    TicketStatus.unknown => '',
  };
}

StatusTone _statusTone(TicketStatus status) => switch (status) {
  TicketStatus.resolved => StatusTone.positive,
  TicketStatus.waitingForCustomer => StatusTone.caution,
  TicketStatus.closed || TicketStatus.unknown => StatusTone.neutral,
  _ => StatusTone.progress,
};

String _categoryLabel(BuildContext context, TicketCategory category) {
  final l10n = context.l10n;
  return switch (category) {
    TicketCategory.order => l10n.ticketCategoryOrder,
    TicketCategory.payment => l10n.ticketCategoryPayment,
    TicketCategory.delivery => l10n.ticketCategoryDelivery,
    TicketCategory.returnRequest => l10n.ticketCategoryReturn,
    TicketCategory.product => l10n.ticketCategoryProduct,
    TicketCategory.account => l10n.ticketCategoryAccount,
    TicketCategory.other => l10n.ticketCategoryOther,
  };
}

/// Every ticket the customer has opened.
class SupportTicketsScreen extends ConsumerWidget {
  const SupportTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tickets = ref.watch(supportTicketsProvider);

    return Scaffold(
      appBar: SabaAppBar(title: l10n.supportTickets),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: AsyncStateView<List<SupportTicket>>(
                value: tickets,
                onRetry: () => ref.invalidate(supportTicketsProvider),
                loadingBuilder: (_) => const ListSkeleton(itemHeight: 96),
                builder: (items) {
                  if (items.isEmpty) {
                    return NoResultsView(
                      icon: SabaIcons.headset,
                      title: l10n.emptyTickets,
                      message: l10n.emptyTicketsMessage,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => ref.refresh(supportTicketsProvider.future),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenGutter,
                        AppSpacing.sm,
                        AppSpacing.screenGutter,
                        AppSpacing.xl,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md + 2),
                      itemBuilder: (context, index) =>
                          _TicketCard(ticket: items[index]),
                    ),
                  );
                },
              ),
            ),
            StickyBar(
              child: AppButton(
                label: l10n.newTicket,
                icon: SabaIcons.plus,
                onPressed: () => context.push(AppRoutes.newSupportTicket),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final radius = BorderRadius.circular(AppRadius.card);

    return Material(
      color: context.colors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: () => context.push(AppRoutes.supportTicketPath(ticket.id)),
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            border: Border.all(color: context.market.border),
            borderRadius: radius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      ticket.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleMedium?.copyWith(
                        fontSize: 14.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusBadge(
                    label: _statusLabel(context, ticket.status),
                    tone: _statusTone(ticket.status),
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '#${ticket.reference}  ·  '
                '${Formatters.date(ticket.createdAt, locale: locale)}',
                style: context.textStyles.labelSmall,
              ),
              if (ticket.lastMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  ticket.lastMessage!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodySmall?.copyWith(height: 1.45),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Open a new ticket.
class NewSupportTicketScreen extends ConsumerStatefulWidget {
  const NewSupportTicketScreen({super.key});

  @override
  ConsumerState<NewSupportTicketScreen> createState() =>
      _NewSupportTicketScreenState();
}

class _NewSupportTicketScreenState
    extends ConsumerState<NewSupportTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();

  TicketCategory _category = TicketCategory.order;
  bool _isSubmitting = false;
  Failure? _failure;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final selected = await AppDialogs.bottomSheet<TicketCategory>(
      context,
      isScrollControlled: false,
      builder: (_) => OptionSheet<TicketCategory>(
        title: context.l10n.ticketCategory,
        options: TicketCategory.values,
        current: _category,
        labelOf: (category) => _categoryLabel(context, category),
      ),
    );
    if (selected != null) setState(() => _category = selected);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _failure = null);
    if (!(_formKey.currentState?.validateAndReveal() ?? false)) return;

    setState(() => _isSubmitting = true);

    final result = await ref
        .read(supportRepositoryProvider)
        .create(
          subject: _subject.text.trim(),
          category: _category.apiValue,
          description: _description.text.trim(),
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    result.fold(
      ok: (ticket) {
        ref.invalidate(supportTicketsProvider);
        context.pushReplacement(AppRoutes.supportTicketPath(ticket.id));
      },
      err: (failure) {
        setState(() => _failure = failure);
        if (failure.fieldErrors.isEmpty) {
          AppSnackBar.failure(context, failure);
        } else {
          _formKey.currentState?.validateAndReveal();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: SabaAppBar(title: l10n.newTicket),
      body: SafeArea(
        top: false,
        child: ContentContainer(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.sm,
                      AppSpacing.screenGutter,
                      AppSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionCard(
                          padding: EdgeInsets.zero,
                          child: SabaTile(
                            icon: SabaIcons.headset,
                            label: l10n.ticketCategory,
                            // The category used to be a dropdown of raw API
                            // codes: ORDER, PAYMENT, DELIVERY.
                            subtitle: _categoryLabel(context, _category),
                            onTap: _pickCategory,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AppTextField(
                          label: l10n.ticketSubject,
                          hint: context.exampleOf(context.l10n.exTicketSubject),
                          controller: _subject,
                          isRequired: true,
                          textInputAction: TextInputAction.next,
                          serverError: _failure?.messageForField('subject'),
                          validator: (value) =>
                              Validators.minLength(value, 4, l10n),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AppTextField(
                          label: l10n.ticketDescription,
                          hint: context.exampleOf(
                            context.l10n.exTicketDescription,
                          ),
                          controller: _description,
                          isRequired: true,
                          maxLines: 6,
                          maxLength: 2000,
                          serverError: _failure?.messageForField('description'),
                          validator: (value) =>
                              Validators.minLength(value, 10, l10n),
                        ),
                      ],
                    ),
                  ),
                ),
                StickyBar(
                  child: AppButton(
                    label: l10n.submit,
                    isLoading: _isSubmitting,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One ticket and its conversation.
class SupportTicketScreen extends ConsumerStatefulWidget {
  const SupportTicketScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<SupportTicketScreen> createState() =>
      _SupportTicketScreenState();
}

class _SupportTicketScreenState extends ConsumerState<SupportTicketScreen> {
  final _reply = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;

    setState(() => _isSending = true);

    final result = await ref
        .read(supportRepositoryProvider)
        .reply(ticketId: widget.ticketId, body: body);

    if (!mounted) return;
    setState(() => _isSending = false);

    result.fold(
      ok: (_) {
        _reply.clear();
        ref.invalidate(ticketMessagesProvider(widget.ticketId));
        ref.invalidate(supportTicketProvider(widget.ticketId));
        // The reply can reopen it: the list's badge too.
        ref.invalidate(supportTicketsProvider);
      },
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ticket = ref.watch(supportTicketProvider(widget.ticketId));
    final messages = ref.watch(ticketMessagesProvider(widget.ticketId));
    final value = ticket.value;

    return Scaffold(
      appBar: SabaAppBar(title: value?.subject ?? l10n.supportTickets),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (value != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  0,
                  AppSpacing.screenGutter,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    StatusBadge(
                      label: _statusLabel(context, value.status),
                      tone: _statusTone(value.status),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '#${value.reference}',
                      style: context.textStyles.labelSmall,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: AsyncStateView<List<TicketMessage>>(
                value: messages,
                onRetry: () =>
                    ref.invalidate(ticketMessagesProvider(widget.ticketId)),
                builder: (items) => ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.sm,
                    AppSpacing.screenGutter,
                    AppSpacing.lg,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _MessageBubble(message: items[index]),
                ),
              ),
            ),
            // A closed ticket is read-only; reopening is a support action.
            if (value?.status != TicketStatus.closed)
              StickyBar(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reply,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: l10n.typeMessage,
                          filled: true,
                          fillColor: context.market.surfaceMuted,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
                    _SendButton(
                      isBusy: _isSending,
                      onPressed: _isSending ? null : _send,
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

class _SendButton extends StatelessWidget {
  const _SendButton({required this.isBusy, required this.onPressed});

  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: context.l10n.send,
          child: SizedBox(
            width: AppSizes.minTapTarget,
            height: AppSizes.minTapTarget,
            child: Center(
              child: isBusy
                  ? SizedBox(
                      width: AppSizes.iconSm,
                      height: AppSizes.iconSm,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          context.colors.onPrimary,
                        ),
                      ),
                    )
                  // The plane flies the way the language reads — SabaIcon
                  // turns it round in Arabic now, so this no longer does.
                  : SabaIcon(
                      SabaIcons.send,
                      size: AppSizes.iconMd,
                      color: context.colors.onPrimary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One message in the thread.
///
/// The customer's own messages sit on the trailing edge in the brand colour;
/// support sits on the leading edge in a neutral. Which side a bubble is on is
/// the fastest way to read a conversation.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final TicketMessage message;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final locale = context.l10n.locale.toLanguageTag();
    final isMine = message.isFromCustomer;

    return Align(
      alignment: isMine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg - 2,
          vertical: AppSpacing.md,
        ),
        constraints: BoxConstraints(maxWidth: context.screenWidth * 0.78),
        decoration: BoxDecoration(
          color: isMine ? context.colors.primary : market.surfaceMuted,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(AppRadius.action + 4),
            topEnd: const Radius.circular(AppRadius.action + 4),
            bottomStart: Radius.circular(isMine ? AppRadius.action + 4 : 4),
            bottomEnd: Radius.circular(isMine ? 4 : AppRadius.action + 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine && message.authorName != null) ...[
              Text(
                message.authorName!,
                style: context.textStyles.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs - 1),
            ],
            Text(
              message.body,
              style: context.textStyles.bodyMedium?.copyWith(
                fontSize: 13.5,
                height: 1.45,
                color: isMine ? context.colors.onPrimary : null,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              Formatters.dateTime(message.sentAt, locale: locale),
              style: context.textStyles.labelSmall?.copyWith(
                fontSize: 10.5,
                color: isMine
                    ? context.colors.onPrimary.withValues(alpha: 0.75)
                    : market.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
