import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/western_digits_formatter.dart';

/// The six code boxes with a single invisible field laid over them, shared by
/// the sign-up code step and the verify-at-sign-in step.
///
/// Six real fields are worse in the hand: focus has to be shuffled between
/// them, a pasted code lands in the first box only, and a backspace at the
/// start of one has to be taught to jump back. So the boxes are only a drawing
/// of one invisible field, which takes a paste, takes an SMS autofill, and
/// needs none of that machinery.
///
/// The parent owns the controller and focus node (it reads the code on submit
/// and clears the field on a wrong code), and redraws this on their changes.
class OtpCodeField extends StatelessWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
    this.length = 6,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final int length;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _CodeBoxes(
          code: controller.text,
          length: length,
          isFocused: focusNode.hasFocus,
          hasError: hasError,
        ),
        // The real input: invisible, over the boxes, so a tap anywhere on
        // them brings up the keyboard and a long press offers Paste.
        Positioned.fill(
          child: Theme(
            data: context.theme.copyWith(
              textSelectionTheme: const TextSelectionThemeData(
                selectionColor: Colors.transparent,
              ),
            ),
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              textDirection: TextDirection.ltr,
              showCursor: false,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                const WesternDigitsFormatter(),
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(length),
              ],
              style: const TextStyle(color: Colors.transparent),
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
              onFieldSubmitted: (_) => onSubmitted(),
            ),
          ),
        ),
      ],
    );
  }
}

/// One box per digit, drawn from the single field's text. The next box to
/// fill is outlined while the field has focus; all of them turn red on an
/// error. Left to right in either language: a code is not a sentence.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.code,
    required this.length,
    required this.isFocused,
    required this.hasError,
  });

  final String code;
  final int length;
  final bool isFocused;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    const gap = AppSpacing.sm + 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = ((constraints.maxWidth - gap * (length - 1)) / length)
            .clamp(0.0, 52.0);

        return Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < length; index++) ...[
                if (index > 0) const SizedBox(width: gap),
                Builder(
                  builder: (context) {
                    final isFilled = index < code.length;
                    final isNext = isFocused && index == code.length;
                    final borderColor = hasError
                        ? context.colors.error
                        : isNext
                        ? context.colors.primary
                        : isFilled
                        ? market.borderStrong
                        : Colors.transparent;

                    return AnimatedContainer(
                      duration: AppMotion.press,
                      width: size,
                      height: size * 1.15,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isFilled
                            ? context.colors.surface
                            : market.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.action),
                        border: Border.all(color: borderColor, width: 1.5),
                      ),
                      child: Text(
                        isFilled ? code[index] : '',
                        style: context.textStyles.headlineSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The code, printed on screen, because a demo build has no SMS gateway.
class DemoCodeNote extends StatelessWidget {
  const DemoCodeNote({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final market = context.market;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: market.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.action),
      ),
      child: Row(
        children: [
          SabaIcon(
            SabaIcons.info,
            size: AppSizes.iconSm,
            color: market.textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${context.l10n.demoCodeNote} $code',
              style: context.textStyles.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
