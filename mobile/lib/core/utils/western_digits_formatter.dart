import 'package:flutter/services.dart';

import 'formatters.dart';

/// Arabic ٠-٩ and Persian ۰-۹, typed on an Arabic or Kurdish keyboard,
/// become 0-9 as they are typed.
///
/// A number field filtered to digits dropped them, so someone typing their
/// phone number on an Arabic keyboard saw nothing appear and could not sign
/// in. It goes first, before any filter; one character for one, so the
/// cursor stays where it was.
class WesternDigitsFormatter extends TextInputFormatter {
  const WesternDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = Formatters.western(newValue.text);
    return text == newValue.text ? newValue : newValue.copyWith(text: text);
  }
}
