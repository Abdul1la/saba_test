import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/entities.dart';

/// What the customer chose when cancelling.
@immutable
class CancelReasonChoice {
  const CancelReasonChoice({required this.reason, this.note});

  final CancelReason reason;
  final String? note;

  /// The code the backend stores. A translated sentence would be useless to
  /// the admin panel and to reporting, so the note travels separately.
  String get apiValue => reason.apiValue;
}

/// G7 — asks why, instead of cancelling under a hardcoded reason.
///
/// Returns `null` if the customer backed out, so the caller can tell "cancelled
/// the cancellation" apart from "chose a reason".
class CancelReasonDialog extends StatefulWidget {
  const CancelReasonDialog({super.key});

  static Future<CancelReasonChoice?> show(BuildContext context) {
    return showDialog<CancelReasonChoice>(
      context: context,
      builder: (context) => const CancelReasonDialog(),
    );
  }

  @override
  State<CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<CancelReasonDialog> {
  CancelReason? _selected;
  final _note = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _label(BuildContext context, CancelReason reason) {
    final l10n = context.l10n;
    return switch (reason) {
      CancelReason.changedMind => l10n.cancelReasonChangedMind,
      CancelReason.foundCheaper => l10n.cancelReasonFoundCheaper,
      CancelReason.deliveryTooSlow => l10n.cancelReasonDeliveryTooSlow,
      CancelReason.orderedByMistake => l10n.cancelReasonOrderedByMistake,
      CancelReason.other => l10n.cancelReasonOther,
    };
  }

  void _confirm() {
    final selected = _selected;
    if (selected == null) {
      setState(() => _showError = true);
      return;
    }
    final note = _note.text.trim();
    Navigator.of(context).pop(
      CancelReasonChoice(reason: selected, note: note.isEmpty ? null : note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      titleTextStyle: AppTypography.subsectionTitle(context),
      title: Text(l10n.selectCancelReason),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final reason in CancelReason.values)
                RadioListTile<CancelReason>(
                  value: reason,
                  // ignore: deprecated_member_use
                  groupValue: _selected,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_label(context, reason)),
                  // ignore: deprecated_member_use
                  onChanged: (value) => setState(() {
                    _selected = value;
                    _showError = false;
                  }),
                ),
              if (_showError)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    l10n.cancelReasonRequired,
                    style: context.textStyles.labelSmall?.copyWith(
                      color: context.market.outOfStock,
                    ),
                  ),
                ),
              AppTextField(
                label: l10n.cancelReasonNote,
                hint: context.exampleOf(context.l10n.exCancel),
                controller: _note,
                maxLines: 3,
                maxLength: 500,
              ),
            ],
          ),
        ),
      ),
      actions: [
        // "Cancel" beside "Cancel order" is the word a customer scanning this
        // dialog taps *to cancel the order* — and the destructive one was the
        // ordinary primary blue. The payment sheet already solved this by
        // naming the safe way out; this says what backing out keeps.
        DialogActions(
          cancelLabel: l10n.keepOrder,
          confirmLabel: l10n.cancelOrder,
          onConfirm: _confirm,
          isDestructive: true,
        ),
      ],
    );
  }
}
