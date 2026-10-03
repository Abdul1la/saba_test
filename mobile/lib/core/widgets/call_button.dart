import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import 'app_dialogs.dart';

/// Opens the phone's dialer on [number]. Where there is none - a tablet, a
/// computer - the number is copied instead, and the page says so.
Future<void> callNumber(BuildContext context, String number) async {
  var opened = false;
  try {
    opened = await launchUrl(Uri(scheme: 'tel', path: number));
  } on Object {
    // No dialer, or no plugin behind it: copy the number below.
  }
  if (opened || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: number));
  if (context.mounted) {
    AppSnackBar.info(context, context.l10n.copiedToClipboard);
  }
}

/// "Call", in one tap: the store calls the shopper, the shopper the driver.
class CallButton extends StatelessWidget {
  const CallButton({super.key, required this.number});

  final String number;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: () => callNumber(context, number),
      icon: SabaIcon(SabaIcons.phone, size: 16, color: context.market.success),
      label: Text(context.l10n.call),
      style: FilledButton.styleFrom(
        foregroundColor: context.market.success,
        backgroundColor: context.market.successSoft,
        visualDensity: VisualDensity.compact,
        // The app's buttons are full width; this one sits beside a name.
        minimumSize: const Size(0, 40),
      ),
    );
  }
}
