import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/iraqi_phone.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/entities.dart';
import '../auth_providers.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/iraqi_phone_field.dart';
import '../widgets/otp_code_field.dart';

/// A way back in for someone who forgot their password: the number, then
/// the code sent to it and a new password on the same screen.
///
/// Passwords are in v1, and without this a forgotten one locked the account
/// for good. The real backend must check the code before it changes the
/// password (BUGS.md 122).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSubmitting = false;

  /// The number the code went to, once it has, and the demo's code with it.
  String? _codeSentTo;
  String? _demoCode;

  Failure? _failure;

  @override
  void dispose() {
    for (final controller in [
      _phoneController,
      _codeController,
      _passwordController,
      _confirmController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _failed(Failure failure) {
    setState(() => _failure = failure);
    if (failure.fieldErrors.isEmpty) {
      AppSnackBar.failure(context, failure);
    } else {
      _formKey.currentState?.validateAndReveal();
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _failure = null);
    if (!(_formKey.currentState?.validateAndReveal() ?? false)) return;

    setState(() => _isSubmitting = true);
    final auth = ref.read(authRepositoryProvider);
    final sentTo = _codeSentTo;

    if (sentTo == null) {
      final phone = IraqiPhone.normalize(_phoneController.text)!;
      final result = await auth.sendOtp(
        phone,
        purpose: OtpPurpose.passwordReset,
      );
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      result.fold(
        ok: (challenge) => setState(() {
          _codeSentTo = phone;
          _demoCode = challenge.demoCode;
        }),
        err: _failed,
      );
      return;
    }

    final result = await auth.resetPassword(
      phone: sentTo,
      code: _codeController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    result.fold(
      ok: (_) {
        AppSnackBar.success(context, context.l10n.passwordChanged);
        context.go(AppRoutes.login);
      },
      err: _failed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sentTo = _codeSentTo;
    final demoCode = _demoCode;

    return AuthScaffold(
      title: l10n.forgotPasswordTitle,
      subtitle: sentTo == null
          ? l10n.forgotPasswordPhoneSubtitle
          : '${l10n.codeSentTo} ${Formatters.ltrIsolate(IraqiPhone.display(sentTo))}',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sentTo == null)
                IraqiPhoneField(
                  controller: _phoneController,
                  autofocus: true,
                  serverError: _failure?.messageForField('phone'),
                  onSubmitted: (_) => _submit(),
                )
              else ...[
                if (demoCode != null) ...[
                  DemoCodeNote(code: demoCode),
                  const SizedBox(height: AppSpacing.lg),
                ],
                AppTextField(
                  label: l10n.enterTheCode,
                  hint: context.exampleOf('123456'),
                  controller: _codeController,
                  isRequired: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  prefixIcon: SabaIcons.lock,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  serverError: _failure?.messageForField('code'),
                  validator: (value) => (value ?? '').trim().length == 6
                      ? null
                      : l10n.validationOtpLength,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: l10n.newPassword,
                  hint: context.l10n.passwordHelper,
                  controller: _passwordController,
                  isRequired: true,
                  obscureText: true,
                  prefixIcon: SabaIcons.lock,
                  helper: l10n.passwordHelper,
                  autofillHints: const [AutofillHints.newPassword],
                  serverError: _failure?.messageForField('password'),
                  validator: (value) => Validators.password(value, l10n),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: l10n.confirmPassword,
                  hint: context.l10n.exRepeatPassword,
                  controller: _confirmController,
                  isRequired: true,
                  obscureText: true,
                  prefixIcon: SabaIcons.lock,
                  validator: (value) => Validators.confirmPassword(
                    value,
                    _passwordController.text,
                    l10n,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: sentTo == null ? l10n.sendCode : l10n.saveNewPassword,
                isLoading: _isSubmitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
