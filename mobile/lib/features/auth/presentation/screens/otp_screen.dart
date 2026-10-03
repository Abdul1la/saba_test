import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../domain/entities.dart';
import '../auth_providers.dart';
import '../widgets/otp_code_field.dart';
import '../widgets/sign_up_step_header.dart';
import '../../../../core/utils/iraqi_phone.dart';

/// Step two of sign-up: the code from the SMS.
///
/// Drawn as six boxes, one per digit, centred with the button under them -
/// but typed into one field. Six real fields are worse in the hand: focus has
/// to be shuffled between them, a pasted code lands in the first box only,
/// and a backspace at the start of one has to be taught to jump back. So the
/// boxes are only a drawing of a single invisible field laid over them, which
/// takes a paste, takes an SMS autofill, and needs none of that machinery.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    super.key,
    required this.isMerchant,
    required this.phone,
    this.demoCode,
  });

  final bool isMerchant;
  final String phone;

  /// Only ever non-null in a demo build — see [OtpChallenge].
  final String? demoCode;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const int _codeLength = 6;

  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// The code is too short, or the server refused it.
  String? _error;

  Timer? _ticker;
  int _secondsLeft = 60;
  bool _isSubmitting = false;
  bool _isResending = false;
  String? _demoCode;

  @override
  void initState() {
    super.initState();
    _demoCode = widget.demoCode;
    _startCooldown(60);
    // The focused box is outlined, so the boxes redraw as focus moves.
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _ticker?.cancel();
    setState(() => _secondsLeft = seconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final l10n = context.l10n;
    setState(() => _error = null);
    if (_controller.text.trim().length != _codeLength) {
      setState(() => _error = l10n.validationOtpLength);
      _focus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();

    setState(() => _isSubmitting = true);
    final result = await ref
        .read(authRepositoryProvider)
        .verifyOtp(phone: widget.phone, code: _controller.text.trim());

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    result.fold(
      // pushReplacement, not push: once the number is verified there is
      // nothing here to come back to, and Back from the form should land on
      // the number entry so a wrong number can be corrected.
      ok: (token) => context.pushReplacement(
        AppRoutes.registerPath(
          merchant: widget.isMerchant,
          phone: widget.phone,
          token: token,
        ),
      ),
      err: (failure) {
        final onField = failure.messageForField('code');
        // The wrong digits go, so the next try is typed straight in: all
        // six had to be deleted by hand first.
        _controller.clear();
        _focus.requestFocus();
        setState(() => _error = onField);
        if (onField == null) AppSnackBar.failure(context, failure);
      },
    );
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    // For sign-up, as the first send was: a resend that did not say so
    // skipped the check, and a number with an account got a code anyway.
    final result = await ref
        .read(authRepositoryProvider)
        .sendOtp(widget.phone, purpose: OtpPurpose.signUp);

    if (!mounted) return;
    setState(() => _isResending = false);

    result.fold(
      ok: (challenge) {
        // The old code is dead now, so the field is cleared rather than left
        // holding digits that are about to be rejected.
        _controller.clear();
        setState(() {
          _demoCode = challenge.demoCode;
          _error = null;
        });
        _startCooldown(challenge.expiresInSeconds);
        AppSnackBar.success(context, context.l10n.codeSentAgain);
      },
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canResend = _secondsLeft <= 0 && !_isResending;

    final codeField = OtpCodeField(
      controller: _controller,
      focusNode: _focus,
      length: _codeLength,
      hasError: _error != null,
      // Six digits is the whole answer, so there is nothing left to wait for
      // - verifying on the sixth saves a tap on a button most people never
      // look at anyway.
      onChanged: (value) {
        setState(() => _error = null);
        if (value.length == _codeLength && !_isSubmitting) _verify();
      },
      onSubmitted: _verify,
    );

    return SignUpStepScaffold(
      step: 2,
      total: 3,
      centered: true,
      title: l10n.enterTheCode,
      subtitle:
          '${l10n.codeSentTo} ${Formatters.ltrIsolate(IraqiPhone.display(widget.phone))}',
      action: AppButton(
        label: l10n.verify,
        isLoading: _isSubmitting,
        onPressed: _verify,
      ),
      footer: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.didNotGetCode, style: context.textStyles.bodySmall),
          TextButton(
            onPressed: canResend ? _resend : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppSizes.minTapTarget),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
            // A disabled button with no stated reason reads as broken. The
            // countdown is the reason, shown in the button's own place.
            child: Text(
              canResend ? l10n.resendCode : l10n.resendAfter(_secondsLeft),
            ),
          ),
        ],
      ),
      children: [
        // Correcting a mistyped number should not mean guessing that Back is
        // how you do it. This says so, right under the number.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => context.pop(),
            icon: SabaIcon(
              SabaIcons.pencil,
              size: AppSizes.iconSm,
              color: context.colors.primary,
            ),
            label: Text(l10n.changeNumber),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppSizes.minTapTarget),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        codeField,
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.error,
            ),
          ),
        ],
        if (_demoCode != null) ...[
          const SizedBox(height: AppSpacing.md),
          DemoCodeNote(code: _demoCode!),
        ],
      ],
    );
  }
}
