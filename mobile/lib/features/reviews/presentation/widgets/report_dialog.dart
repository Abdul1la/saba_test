import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/api_endpoints.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../domain/entities.dart';

/// What the reporter chose.
@immutable
class ReportChoice {
  const ReportChoice({required this.reason, this.description});

  final ReportReason reason;
  final String? description;

  /// The stable code the backend stores. Moderation must never have to parse a
  /// translated sentence, so the free text travels separately.
  String get apiValue => reason.apiValue;
}

/// G11 — one report dialog, used for both products and reviews.
///
/// Returns `null` when the reporter backed out, so the caller can tell that
/// apart from a chosen reason.
class ReportDialog extends StatefulWidget {
  const ReportDialog({super.key, required this.title});

  final String title;

  static Future<ReportChoice?> show(BuildContext context, {String? title}) {
    return showDialog<ReportChoice>(
      context: context,
      builder: (context) =>
          ReportDialog(title: title ?? context.l10n.reportReview),
    );
  }

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  ReportReason? _selected;
  final _details = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  String _label(BuildContext context, ReportReason reason) {
    final l10n = context.l10n;
    return switch (reason) {
      ReportReason.counterfeit => l10n.reportCounterfeit,
      ReportReason.prohibited => l10n.reportProhibited,
      ReportReason.misleading => l10n.reportMisleading,
      ReportReason.offensive => l10n.reportOffensive,
      ReportReason.spam => l10n.reportSpam,
      ReportReason.other => l10n.reportOther,
    };
  }

  void _submit() {
    final selected = _selected;
    if (selected == null) {
      setState(() => _showError = true);
      return;
    }
    final text = _details.text.trim();
    Navigator.of(context).pop(
      ReportChoice(reason: selected, description: text.isEmpty ? null : text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      titleTextStyle: AppTypography.subsectionTitle(context),
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.reportReasonLabel,
                style: context.textStyles.labelMedium,
              ),
              for (final reason in ReportReason.values)
                RadioListTile<ReportReason>(
                  value: reason,
                  // ignore: deprecated_member_use
                  groupValue: _selected,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
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
                    l10n.reportReasonRequired,
                    style: context.textStyles.labelSmall?.copyWith(
                      color: context.market.outOfStock,
                    ),
                  ),
                ),
              AppTextField(
                label: l10n.reportDetails,
                hint: context.exampleOf(context.l10n.exReport),
                controller: _details,
                maxLines: 3,
                maxLength: 500,
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Neutral: this dialog is opened for a review as well as a
        // product, and it used to say "Report product" under the title
        // "Report review".
        DialogActions(confirmLabel: l10n.submit, onConfirm: _submit),
      ],
    );
  }
}

/// What can be reported to Saba, besides a review (Apple 1.2, Google Play).
enum ReportTarget {
  product('PRODUCT'),
  store('STORE'),
  conversation('CONVERSATION');

  const ReportTarget(this.apiValue);

  final String apiValue;
}

/// Asks why, sends it to Saba, and says thank you, or what went wrong. A
/// repeat is kept once by the server.
Future<void> reportToSaba(
  BuildContext context,
  WidgetRef ref, {
  required ReportTarget target,
  required String id,
}) async {
  // Reported by someone Saba can answer: a guest signs in first.
  if (!ref.read(isAuthenticatedProvider)) {
    context.push(AppRoutes.login);
    return;
  }
  final l10n = context.l10n;
  final choice = await ReportDialog.show(
    context,
    title: switch (target) {
      ReportTarget.product => l10n.reportProduct,
      ReportTarget.store => l10n.reportStore,
      ReportTarget.conversation => l10n.reportChat,
    },
  );
  if (choice == null || !context.mounted) return;
  final result = await sendReport(
    ref.read(apiClientProvider),
    target: target,
    id: id,
    choice: choice,
  );
  if (!context.mounted) return;
  result.fold(
    ok: (_) => AppSnackBar.success(context, l10n.reportThanks),
    err: (failure) => AppSnackBar.failure(context, failure),
  );
}

/// The report itself, as the server takes it.
Future<Result<void>> sendReport(
  ApiClient client, {
  required ReportTarget target,
  required String id,
  required ReportChoice choice,
}) => client.command(
  ApiEndpoints.reports,
  data: <String, dynamic>{
    'targetType': target.apiValue,
    'targetId': id,
    'reason': choice.apiValue,
    'description': ?choice.description,
  },
);
