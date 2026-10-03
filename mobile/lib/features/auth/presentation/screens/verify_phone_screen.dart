import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/iraqi_phone.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/saba_logo.dart';
import '../../domain/entities.dart';
import '../auth_providers.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/otp_code_field.dart';

/// Verify-at-sign-in: the password was right, but the number was never checked
/// and Saba has SMS checks on again, so sign-in was refused with
/// [PhoneNotVerifiedFailure]. A code is sent here, and the second sign-in
/// carries it.
///
/// It holds the password it was handed rather than asking again: the person
/// just typed it on the sign-in screen, and sending it on with the code is the
/// whole of this step. The password rides in `extra`, never the URL.
class VerifyPhoneScreen extends ConsumerStatefulWidget {
  const VerifyPhoneScreen({
    super.key,
    required this.phone,
    required this.password,
  });

  /// In full international form.
  final String phone;
  final String password;

  @override
  ConsumerState<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen> {
  static const int _codeLength = 6;

  final _controller = TextEditingController();
  final _focus = FocusNode();

  String? _error;
  Timer? _ticker;
  int _secondsLeft = 60;
  bool _isSubmitting = false;
  bool _isResending = false;
  String? _demoCode;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    // A code goes out the moment the screen opens: the person did not ask for
    // one, they tried to sign in, so making them press "resend" first is a
    // step with no purpose.
    WidgetsBinding.instance.addPostFrameCallback((_) => _send(initial: true));
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

  Future<void> _send({required bool initial}) async {
    if (!initial) setState(() => _isResending = true);
    final result = await ref
        .read(authRepositoryProvider)
        .sendOtp(widget.phone, purpose: OtpPurpose.verifyPhone);

    if (!mounted) return;
    if (!initial) setState(() => _isResending = false);

    result.fold(
      ok: (challenge) {
        _controller.clear();
        setState(() {
          _demoCode = challenge.demoCode;
          _error = null;
        });
        _startCooldown(
          challenge.expiresInSeconds > 0 ? challenge.expiresInSeconds : 60,
        );
        if (!initial) AppSnackBar.success(context, context.l10n.codeSentAgain);
      },
      err: (failure) => AppSnackBar.failure(context, failure),
    );
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
    // The sign-in again, now with the code: the server checks the number, the
    // password, and the code together, and answers with the session.
    final result = await ref
        .read(authControllerProvider.notifier)
        .signIn(
          phone: widget.phone,
          password: widget.password,
          code: _controller.text.trim(),
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    switch (result) {
      case Ok<User>():
        // Signed in: the router's guest-only redirect moves off this screen
        // to home or the dashboard on its own. An admin (never sent here in
        // practice) would not count as signed in, so send them back.
        if (ref.read(isAuthenticatedProvider)) return;
        if (mounted) context.go(AppRoutes.login);
      case Err<User>(:final failure):
        // A wrong or expired code comes back on the `code` field, the same as
        // the other code screens; anything else is a banner.
        final onField = failure.messageForField('code');
        _controller.clear();
        _focus.requestFocus();
        setState(() => _error = onField);
        if (onField == null) AppSnackBar.failure(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canResend = _secondsLeft <= 0 && !_isResending;

    return AuthScaffold(
      title: l10n.verifyNumberTitle,
      subtitle:
          '${l10n.codeSentTo} ${Formatters.ltrIsolate(IraqiPhone.display(widget.phone))}',
      logo: const SabaLogo(),
      children: [
        Text(l10n.verifyNumberWhy, style: context.textStyles.bodySmall),
        const SizedBox(height: AppSpacing.lg),
        OtpCodeField(
          controller: _controller,
          focusNode: _focus,
          length: _codeLength,
          hasError: _error != null,
          onChanged: (value) {
            setState(() => _error = null);
            if (value.length == _codeLength && !_isSubmitting) _verify();
          },
          onSubmitted: _verify,
        ),
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
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: l10n.verify,
          isLoading: _isSubmitting,
          onPressed: _verify,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.didNotGetCode, style: context.textStyles.bodySmall),
            TextButton(
              onPressed: canResend ? () => _send(initial: false) : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppSizes.minTapTarget),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: Text(
                canResend ? l10n.resendCode : l10n.resendAfter(_secondsLeft),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
