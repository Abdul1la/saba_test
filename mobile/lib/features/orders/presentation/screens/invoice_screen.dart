import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/entities.dart';
import '../invoice_providers.dart';
import '../widgets/order_status_chip.dart';
import '../../../../core/widgets/saba_logo.dart';

/// G6 — the invoice for one order (specification section 15).
///
/// Every figure is the server's. Nothing is recomputed here: an invoice has to
/// keep saying what was actually charged even after prices change
/// (specification section 16).
///
/// It is drawn as a document rather than as another list screen — a serif-free
/// letterhead, then the lines, then the sum — because that is what a customer
/// forwards to an employer or keeps for a warranty claim.
class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final invoice = ref.watch(invoiceProvider(orderId));

    return Scaffold(
      // The class comment says this is what a customer forwards to an
      // employer or keeps for a warranty claim — and the screen had no way to
      // send it anywhere. A copy is the one that works with no new
      // dependency and lands straight in the message app people here use.
      appBar: SabaAppBar(
        title: l10n.invoice,
        trailing: invoice.hasValue
            ? TextButton(
                onPressed: () => _copy(context, invoice.requireValue),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  minimumSize: const Size(0, AppSizes.minTapTarget),
                  textStyle: context.textStyles.labelLarge?.copyWith(
                    fontSize: 12.5,
                  ),
                ),
                child: Text(l10n.copy),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: AsyncStateView<Invoice>(
          value: invoice,
          onRetry: () => ref.invalidate(invoiceProvider(orderId)),
          builder: (data) => ContentContainer(
            maxWidth: 720,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.sm,
                AppSpacing.screenGutter,
                AppSpacing.xxl,
              ),
              children: [
                _Letterhead(invoice: data),
                const SizedBox(height: AppSpacing.md + 2),
                _LinesCard(invoice: data),
                const SizedBox(height: AppSpacing.md + 2),
                _TotalsCard(invoice: data),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The invoice as plain text, on the clipboard.
  ///
  /// The figures are the server's, copied across unchanged — this writes out
  /// what is on the screen and recomputes nothing, for the same reason the
  /// screen does not: an invoice has to keep saying what was charged.
  Future<void> _copy(BuildContext context, Invoice invoice) async {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();

    String money(num amount) => Formatters.money(
      amount,
      locale: locale,
      currencyCode: invoice.currencyCode,
    );

    final lines = <String>[
      if (invoice.invoiceNumber != null) invoice.invoiceNumber!,
      '${l10n.orderNumber}: ${invoice.orderNumber}',
      Formatters.date(invoice.issuedAt, locale: locale),
      if (invoice.sellerName != null) invoice.sellerName!,
      '',
      for (final line in invoice.lines)
        [
          '${line.description} × ${line.quantity}  ${money(line.total)}',
          // With no one seller, each line says whose it is.
          if (invoice.sellerName == null && line.merchantName != null)
            '(${line.merchantName})',
        ].join('  '),
      '',
      '${l10n.subtotal}: ${money(invoice.subtotal)}',
      if (invoice.discount > 0)
        '${l10n.discount}: ${Formatters.deduction(invoice.discount, locale: locale, currencyCode: invoice.currencyCode)}',
      if (invoice.shipping > 0) '${l10n.shipping}: ${money(invoice.shipping)}',
      if (invoice.tax > 0) '${l10n.tax}: ${money(invoice.tax)}',
      '${l10n.grandTotal}: ${money(invoice.total)}',
      if (invoice.isCancelled) l10n.cancelledNothingCharged,
      if (invoice.paymentMethodLabel != null)
        '${l10n.paymentMethod}: ${invoice.paymentMethodLabel}',
    ];

    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!context.mounted) return;
    AppSnackBar.success(context, l10n.copiedToClipboard);
  }
}

/// Who charged whom, for what, and when.
class _Letterhead extends StatelessWidget {
  const _Letterhead({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A document, so the quiet navy logo, not the purple one; white on
          // a dark card, where navy would vanish.
          SabaLogo(
            size: 28,
            tone: context.isDarkMode ? SabaMarkTone.white : SabaMarkTone.navy,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.invoiceNumber} ${invoice.reference}',
                      style: context.textStyles.titleLarge?.copyWith(
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${l10n.issuedOn} '
                      '${Formatters.date(invoice.issuedAt, locale: locale)}',
                      style: context.textStyles.labelSmall,
                    ),
                    Text(
                      '${l10n.orderNumber} ${invoice.orderNumber}',
                      style: context.textStyles.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Whether this has actually been paid is the first thing anyone
              // checks on an invoice. The entity has carried it all along and
              // the screen never showed it.
              PaymentStatusBadge(status: invoice.paymentStatus),
            ],
          ),
          if (invoice.sellerName != null || invoice.billedTo != null) ...[
            const SizedBox(height: AppSpacing.lg + 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (invoice.sellerName != null)
                  Expanded(
                    child: _Party(
                      label: l10n.soldBy,
                      name: invoice.sellerName!,
                    ),
                  ),
                if (invoice.sellerName != null && invoice.billedTo != null)
                  const SizedBox(width: AppSpacing.lg),
                if (invoice.billedTo != null)
                  Expanded(
                    child: _Party(
                      label: l10n.billedTo,
                      name: invoice.billedTo!.fullName,
                      detail: invoice.billedTo!.formattedIn(
                        l10n.locale.languageCode,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Party extends StatelessWidget {
  const _Party({required this.label, required this.name, this.detail});

  final String label;
  final String name;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: context.textStyles.labelSmall?.copyWith(
            fontSize: 10,
            letterSpacing: 0.6,
            color: context.market.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          name,
          style: context.textStyles.bodyMedium?.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.xxs - 1),
          Text(
            detail!,
            style: context.textStyles.bodySmall?.copyWith(height: 1.45),
          ),
        ],
      ],
    );
  }
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();

    String money(num value) => Formatters.money(
      value,
      locale: locale,
      currencyCode: invoice.currencyCode,
    );

    return SectionCard(
      // "Items" beside "Totals"; it was a lowercase "items".
      title: l10n.orderItems,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < invoice.lines.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Divider(height: 1, color: context.market.border),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.lines[index].description,
                        style: context.textStyles.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          height: 1.35,
                        ),
                      ),
                      if (invoice.lines[index].merchantName != null) ...[
                        const SizedBox(height: AppSpacing.xxs - 1),
                        Text(
                          invoice.lines[index].merchantName!,
                          style: context.textStyles.labelSmall,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${invoice.lines[index].quantity} × '
                        '${money(invoice.lines[index].unitPrice)}',
                        style: context.textStyles.labelSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  money(invoice.lines[index].total),
                  textAlign: TextAlign.end,
                  style: context.textStyles.titleSmall?.copyWith(
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();

    String money(num value) => Formatters.money(
      value,
      locale: locale,
      currencyCode: invoice.currencyCode,
    );

    return SectionCard(
      title: l10n.invoiceTotals,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLine(label: l10n.subtotal, value: money(invoice.subtotal)),
          if (invoice.discount != 0)
            CardLine(
              label: l10n.discount,
              value: Formatters.deduction(
                invoice.discount,
                locale: locale,
                currencyCode: invoice.currencyCode,
              ),
              valueColor: context.market.success,
            ),
          if (invoice.shipping != 0)
            CardLine(label: l10n.shipping, value: money(invoice.shipping)),
          if (invoice.tax != 0)
            CardLine(label: l10n.tax, value: money(invoice.tax)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Divider(height: 1, color: context.market.border),
          ),
          // A cancelled invoice's total is crossed out, not the sum to pay,
          // and says so, as the order page does (BUGS 99).
          CardLine(
            label: l10n.total,
            value: money(invoice.total),
            emphasise: !invoice.isCancelled,
            struck: invoice.isCancelled,
            valueColor: invoice.isCancelled ? context.market.textMuted : null,
          ),
          if (invoice.isCancelled) ...[
            CardNote(l10n.cancelledNothingCharged),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (invoice.paymentMethodLabel != null)
            // Was labelled "Amount paid" against the method's name, so the
            // invoice read "Amount paid: Cash on delivery".
            CardLine(
              label: l10n.paymentMethod,
              value: invoice.paymentMethodLabel!,
            ),
        ],
      ),
    );
  }
}
