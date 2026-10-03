import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../rate_order_providers.dart';

/// One sheet for one delivered order: did it arrive, and what were its
/// stores like.
///
/// One sheet, not several popups. An order from two stores used to mean two
/// review screens to find and fill, and what a shopper actually has in mind
/// when the parcel lands is one opinion about the whole delivery. So: the
/// question first, then a row of stars per store and one comment box, and a
/// single button.
///
/// Products are not rated - only stores. A shopper knows whether the store
/// packed it well and brought it on time; whether the kettle is any good is
/// not something they can say on the day it arrived.
class RateOrderSheet extends ConsumerStatefulWidget {
  const RateOrderSheet({super.key, required this.order});

  final OrderToRate order;

  /// Opens the sheet over the whole app. Returns once it is closed.
  static Future<void> show(BuildContext context, OrderToRate order) =>
      AppDialogs.bottomSheet<void>(
        context,
        builder: (_) => RateOrderSheet(order: order),
      );

  @override
  ConsumerState<RateOrderSheet> createState() => _RateOrderSheetState();
}

class _RateOrderSheetState extends ConsumerState<RateOrderSheet> {
  /// Store id to the stars it was given. Empty until one is tapped.
  final Map<String, int> _stars = <String, int>{};
  final _comment = TextEditingController();

  /// Null while the first question is unanswered.
  bool? _arrived;
  bool _isSending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send(Future<Object?> Function() request) async {
    setState(() => _isSending = true);
    final failure = await request();
    if (!mounted) return;
    setState(() => _isSending = false);
    Navigator.of(context).pop();
    if (failure != null) return;
  }

  /// Saved before the stars are asked for, so the answer stands however
  /// the sheet is closed.
  Future<void> _yes() async {
    setState(() => _isSending = true);
    final failure = await ref
        .read(rateOrderProvider)
        .arrived(widget.order.orderId);
    if (!mounted) return;
    setState(() {
      _isSending = false;
      if (failure == null) _arrived = true;
    });
    if (failure != null) AppSnackBar.failure(context, failure);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rate = ref.read(rateOrderProvider);
    final order = widget.order;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Answered, the question makes way for the stars'.
            Text(
              _arrived == true ? l10n.howWasYourOrder : l10n.didYourOrderArrive,
              style: AppTypography.subsectionTitle(context),
            ),
            const SizedBox(height: AppSpacing.xxs),
            // Which store is being asked about, from the first question: it
            // was named only after "Yes, it arrived" (BUGS.md 85).
            Text(
              [
                order.orderNumber,
                order.stores.map((store) => store.storeName).join(l10n.comma),
              ].join(' · '),
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (_arrived != true) ...[
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: l10n.yesItArrived,
                      onPressed: _isSending ? null : _yes,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      label: l10n.notYet,
                      variant: AppButtonVariant.secondary,
                      isLoading: _isSending,
                      onPressed: _isSending
                          ? null
                          : () => _send(() => rate.notArrived(order.orderId)),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // A row of stars per store, so an order from two shops can say
              // that one was good and the other was not.
              for (final store in order.stores) ...[
                Text(store.storeName, style: context.textStyles.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                _StarRow(
                  storeId: store.id,
                  value: _stars[store.id] ?? 0,
                  storeName: store.storeName,
                  onChanged: (stars) =>
                      setState(() => _stars[store.id] = stars),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AppTextField(
                label: l10n.anythingToAdd,
                hint: context.exampleOf(context.l10n.exReview),
                controller: _comment,
                maxLines: 3,
                maxLength: 300,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: l10n.submit,
                isLoading: _isSending,
                // Nothing to send until at least one store has its stars.
                onPressed: _stars.isEmpty || _isSending
                    ? null
                    : () => _send(
                        () => rate.rate(
                          orderId: order.orderId,
                          stars: _stars,
                          comment: _comment.text.trim().isEmpty
                              ? null
                              : _comment.text.trim(),
                        ),
                      ),
              ),
            ],

            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: l10n.notNow,
              variant: AppButtonVariant.text,
              onPressed: _isSending
                  ? null
                  : () => _send(() => rate.notNow(order.orderId)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Five stars to tap, filling up to the one pressed.
class _StarRow extends StatelessWidget {
  const _StarRow({
    required this.storeId,
    required this.value,
    required this.storeName,
    required this.onChanged,
  });

  final String storeId;
  final int value;
  final String storeName;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Row(
      children: [
        for (var star = 1; star <= 5; star++)
          Semantics(
            button: true,
            label: '$storeName $star',
            child: InkResponse(
              // Named, so a test can press "three stars for Nova" without
              // turning semantics on to read the label.
              key: ValueKey<String>('rate-$storeId-$star'),
              onTap: () => onChanged(star),
              radius: AppSizes.minTapTarget / 2,
              child: Padding(
                // Small stars, but each one is still a real tap target.
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: SabaIcon(
                  star <= value ? SabaIcons.starFilled : SabaIcons.star,
                  size: AppSizes.iconLg,
                  color: star <= value ? market.star : market.textMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
