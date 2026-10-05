import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities.dart';

/// The reasons a store gives for declining an order, as the codes the
/// server keeps. The store picks from these; the shopper reads them in
/// their own language.
const List<String> declineReasonCodes = <String>[
  'OUT_OF_STOCK',
  'CANNOT_FULFIL',
  'ADDRESS_PROBLEM',
  'CUSTOMER_ASKED',
];

/// Why a store declines a return, as codes: the shopper reads them in
/// their own language. A decline asked for no reason at all (the tester).
const List<String> returnDeclineCodes = <String>[
  'USED',
  'INCOMPLETE',
  'NOT_AS_SAID',
  'OTHER',
];

/// A reason code in the reader's language, or null for one this app does
/// not know. A code is never shown as it is: "CHANGED_MIND" and
/// "DELIVERY_TOO_SLOW" reached the shopper's screen that way.
String? reasonLabel(AppLocalizations l10n, String code) => switch (code) {
  'CHANGED_MIND' => l10n.cancelReasonChangedMind,
  'FOUND_CHEAPER' => l10n.cancelReasonFoundCheaper,
  'DELIVERY_TOO_SLOW' => l10n.cancelReasonDeliveryTooSlow,
  'ORDERED_BY_MISTAKE' => l10n.cancelReasonOrderedByMistake,
  'OTHER' => l10n.cancelReasonOther,
  'OUT_OF_STOCK' => l10n.reasonOutOfStock,
  'CANNOT_FULFIL' => l10n.reasonCannotFulfil,
  'ADDRESS_PROBLEM' => l10n.reasonAddressProblem,
  'CUSTOMER_ASKED' => l10n.reasonCustomerAsked,
  'CUSTOMER_CANCELLED' => l10n.reasonCustomerCancelled,
  // Why a shopper returns something: "DAMAGED" reached the return page.
  'DAMAGED' => l10n.returnReasonDamaged,
  'WRONG_ITEM' => l10n.returnReasonWrongItem,
  'NOT_AS_DESCRIBED' => l10n.returnReasonNotAsDescribed,
  'MISSING_PARTS' => l10n.returnReasonMissingParts,
  // Why a store declines a return.
  'USED' => l10n.returnDeclineUsed,
  'INCOMPLETE' => l10n.returnDeclineIncomplete,
  'NOT_AS_SAID' => l10n.returnDeclineNotAsSaid,
  // Words someone typed are shown as typed; an unknown code is not.
  _ when RegExp(r'^[A-Z_]+$').hasMatch(code) => null,
  _ => code,
};

/// The line under a step of an order's history, in the reader's language.
///
/// The server keeps codes and names, not sentences: a note written as a
/// sentence stayed in the language the order was placed in, so an Arabic
/// reader saw "Order received".
String? timelineNote(AppLocalizations l10n, OrderTimelineEntry entry) {
  final reason = entry.reasonCode == null
      ? null
      : reasonLabel(l10n, entry.reasonCode!);
  final parts = <String>[
    if (entry.noteCode == 'ORDER_RECEIVED') l10n.noteOrderReceived,
    // The store never pressed "Delivered": Saba did, 5 days after it was sent.
    if (entry.noteCode == 'AUTO_DELIVERED') l10n.noteAutoDelivered,
    ?entry.storeName,
    ?reason,
    ?entry.note,
  ];
  return parts.isEmpty ? null : parts.join(': ');
}
