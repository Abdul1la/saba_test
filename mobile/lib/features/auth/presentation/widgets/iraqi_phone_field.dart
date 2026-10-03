import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_text_field.dart';

/// An Iraqi mobile number: the country code fixed in front, the rest typed
/// on the number pad. Sign-up, sign-in and password reset all ask for it
/// this one way.
class IraqiPhoneField extends StatelessWidget {
  const IraqiPhoneField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.serverError,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
    this.helper,
  });

  final TextEditingController controller;
  final bool autofocus;
  final String? serverError;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  /// A line under the field: what the number is for.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // +964 before the number in both languages: a phone number is read left
    // to right in Arabic too, and in a right-to-left row the code sat after
    // the number, so it read backwards.
    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed rather than a country picker: Saba is an Iraq marketplace,
        // and a picker here is a list of 200 countries in front of the one
        // answer every single user gives.
        const _CountryPrefix(),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppTextField(
            label: l10n.phone,
            hint: '7xx xxx xxxx',
            controller: controller,
            isRequired: true,
            helper: helper,
            autofocus: autofocus,
            keyboardType: TextInputType.phone,
            textInputAction: textInputAction,
            prefixIcon: SabaIcons.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              const _AfterCountryCode(),
            ],
            serverError: serverError,
            validator: (value) => Validators.iraqiPhone(value, l10n),
            onSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }
}

/// What is typed after +964: the 0 of the number at home, or a pasted 964,
/// is dropped, so "+964 0770..." cannot be typed; ten digits at most, as in
/// the hint.
class _AfterCountryCode extends TextInputFormatter {
  const _AfterCountryCode();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text;
    if (digits.startsWith('00964')) digits = digits.substring(5);
    if (digits.startsWith('964') && digits.length > 10) {
      digits = digits.substring(3);
    }
    digits = digits.replaceFirst(RegExp('^0+'), '');
    if (digits.length > 10) digits = digits.substring(0, 10);
    if (digits == newValue.text) return newValue;
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

class _CountryPrefix extends StatelessWidget {
  const _CountryPrefix();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lines the box up with the text field's box, which sits below its label.
      padding: const EdgeInsets.only(top: 26),
      child: Container(
        height: AppSizes.buttonHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.market.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.action),
          border: Border.all(color: context.market.border),
        ),
        child: Text(
          '+964',
          style: context.textStyles.titleSmall,
          // The dial code is a number and reads left-to-right in Arabic too.
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}
