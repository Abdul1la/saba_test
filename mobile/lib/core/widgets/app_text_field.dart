import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import '../utils/western_digits_formatter.dart';

/// Checks every field of a form and brings the first one with a problem
/// into view.
///
/// A form marked the field in trouble and left it where it was: a store
/// name already taken in Baghdad was refused under a field scrolled off the
/// top, above the "Create account" the person had just pressed, and they
/// never saw why. Used for the form's own checks and for the server's
/// answer alike.
extension RevealProblems on FormState {
  bool validateAndReveal() {
    final valid = validate();
    // Once the fields are built again: the server's answer, set with
    // setState just before this, reaches its field only then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final problems = validateGranularly();
      if (problems.isEmpty) return;
      Scrollable.ensureVisible(
        problems.first.context,
        alignment: 0.2,
        duration: AppMotion.sheet,
      );
    });
    return valid;
  }
}

/// A labelled form field.
///
/// Accepts a [serverError] so a field-level message returned by the API lands
/// on the same field the user is looking at, instead of in a generic banner.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.validator,
    this.serverError,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.autofillHints,
    this.inputFormatters,
    this.focusNode,
    this.isRequired = false,
    this.autofocus = false,
    this.textDirection,
    this.textAlign = TextAlign.start,
    this.style,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? Function(String?)? validator;

  /// A message returned by the backend for this field.
  final String? serverError;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final int maxLines;
  final int? maxLength;

  /// A [SabaIcons] path. Typed as an [IconData] this field could only ever
  /// draw Material's set, which is what kept the old look alive across 21
  /// call sites. Same fix as [AppButton.icon].
  final String? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final bool isRequired;

  /// Opens the keyboard on arrival. Worth it on a screen whose only job is one
  /// field; a nuisance anywhere a form has several.
  final bool autofocus;

  /// Set when the field's contents are always one language, whatever the
  /// interface is in.
  final TextDirection? textDirection;

  /// For a field whose value is read as a whole rather than as words - a
  /// verification code, say - which wants to be centred and spaced out.
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The label had no give: a long one - "Business description", or its
        // Arabic - pushed the asterisk or the "(optional)" note past the right
        // edge of the screen, on every form in the app. The label shrinks now
        // and the marker beside it always stays on screen, because a required
        // field whose asterisk is off the edge reads as optional.
        // Required fields carry no mark. Nearly every field on these forms
        // is required, so the asterisk was decoration on almost all of them
        // and a red one at that - the colour the app uses for things that
        // have gone wrong, on a field nobody has touched yet. The rarer case
        // is the one worth labelling, so only optional fields say so.
        //
        // The label and its mark wrap together onto a second line rather
        // than being cut: "Tell us more (optio…" at phone width.
        Text.rich(
          TextSpan(
            text: widget.label,
            children: [
              // A read-only field asks for nothing, so it is not "optional":
              // the phone in Edit profile said so, over "You sign in with
              // this number".
              if (!widget.isRequired && !widget.readOnly)
                TextSpan(
                  text: ' (${l10n.optional})',
                  style: context.textStyles.labelSmall,
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          validator: _validate,
          keyboardType: widget.keyboardType,
          // A phone number is typed left to right in either language; in an
          // Arabic field its leading plus otherwise jumps to the far end.
          // A field that is always one language - a product's Arabic name in
          // the English interface - says so, or its first word starts off
          // the wrong edge and is cut off.
          textDirection:
              widget.textDirection ??
              (widget.keyboardType == TextInputType.phone
                  ? TextDirection.ltr
                  : null),
          textInputAction: widget.textInputAction,
          obscureText: _obscured,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          maxLines: _obscured ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          onTap: widget.onTap,
          autofillHints: widget.autofillHints,
          autofocus: widget.autofocus,
          textAlign: widget.textAlign,
          style: widget.style,
          // Arabic and Persian digits become 0-9 before any filter sees them.
          inputFormatters: [
            const WesternDigitsFormatter(),
            ...?widget.inputFormatters,
          ],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helper,
            // A rule the field has to explain is often longer than a line:
            // "Use upper and lower case letters and at least one num…".
            helperMaxLines: 3,
            errorMaxLines: 3,
            counterText: '',
            prefixIcon: widget.prefixIcon == null
                ? null
                : Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: AppSpacing.lg - 2,
                      end: AppSpacing.md,
                    ),
                    child: SabaIcon(
                      widget.prefixIcon!,
                      size: AppSizes.iconMd,
                      color: context.market.textMuted,
                    ),
                  ),
            suffixIcon: _suffix(),
          ),
        ),
      ],
    );
  }

  /// The server's message takes priority: it reflects a rule the client may
  /// not know about, and it is the reason the submit actually failed.
  String? _validate(String? value) {
    final serverError = widget.serverError;
    if (serverError != null && serverError.isNotEmpty) return serverError;
    return widget.validator?.call(value);
  }

  Widget? _suffix() {
    if (widget.obscureText) {
      return IconButton(
        onPressed: () => setState(() => _obscured = !_obscured),
        icon: SabaIcon(
          _obscured ? SabaIcons.eye : SabaIcons.eyeOff,
          size: AppSizes.iconLg,
        ),
      );
    }
    return widget.suffixIcon;
  }
}
