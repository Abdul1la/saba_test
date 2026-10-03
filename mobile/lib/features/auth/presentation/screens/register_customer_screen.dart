import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/location/governorate.dart';
import '../../../../core/location/governorate_picker.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/entities.dart';
import '../../../legal/legal_screen.dart';
import '../auth_providers.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/sign_up_step_header.dart';

/// Customer sign-up.
///
/// The role is never sent by the client: this endpoint always produces a
/// CUSTOMER server-side, which is what makes privilege escalation through
/// public registration impossible (specification section 5).
class RegisterCustomerScreen extends ConsumerStatefulWidget {
  const RegisterCustomerScreen({
    super.key,
    this.verifiedPhone,
    this.phoneToken,
  });

  /// Handed over by the code screen. When present the number is already
  /// proven, so it is filled in and locked rather than asked for a second
  /// time — retyping it is how a person ends up with an account attached to a
  /// number that is not the one they verified.
  final String? verifiedPhone;
  final String? phoneToken;

  bool get _isPhoneVerified => (verifiedPhone ?? '').isNotEmpty;

  @override
  ConsumerState<RegisterCustomerScreen> createState() =>
      _RegisterCustomerScreenState();
}

class _RegisterCustomerScreenState
    extends ConsumerState<RegisterCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  Governorate? _governorate;
  String? _governorateError;

  bool _isSubmitting = false;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    if (widget._isPhoneVerified) {
      _phoneController.text = widget.verifiedPhone!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _failure = null;
      _governorateError = _governorate == null
          ? context.l10n.cityRequired
          : null;
    });
    final valid = _formKey.currentState?.validateAndReveal() ?? false;
    final city = _governorate;
    if (!valid || city == null) return;

    setState(() => _isSubmitting = true);

    final result = await ref
        .read(authControllerProvider.notifier)
        .registerCustomer(
          CustomerRegistration(
            fullName: _nameController.text.trim(),
            password: _passwordController.text,
            phone: _phoneController.text.trim(),
            phoneVerificationToken: widget.phoneToken,
            governorate: city.apiValue,
          ),
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    switch (result) {
      case Ok<User>():
        // What they just chose is where Home shops from.
        // The router moves to the customer shell. It said "Verification
        // email sent." here, and Saba sends no email.
        await ref.read(shopperGovernorateProvider.notifier).choose(city);
      case Err<User>(:final failure):
        setState(() => _failure = failure);
        if (failure.fieldErrors.isEmpty) {
          AppSnackBar.failure(context, failure);
        } else {
          _formKey.currentState?.validateAndReveal();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SignUpStepScaffold(
      step: 3,
      total: 3,
      title: l10n.yourProfile,
      subtitle: l10n.yourProfileSubtitle,
      action: AppButton(
        label: l10n.signUp,
        isLoading: _isSubmitting,
        onPressed: _submit,
      ),
      // A Wrap, not a Row. Two texts side by side have no give: at a large text
      // size, or in a language whose words are longer, the pair runs past the edge
      // and the link is cut off or unreachable. Wrap drops the link onto its own
      // line instead.
      footer: Column(
        children: [
          LegalLinks(note: l10n.agreeToTerms),
          AuthSwitchLink(
            prompt: l10n.haveAccount,
            label: l10n.signIn,
            onPressed: () => context.go(AppRoutes.login),
          ),
        ],
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: l10n.fullName,
                hint: context.exampleOf(context.l10n.exPersonName),
                controller: _nameController,
                isRequired: true,
                textInputAction: TextInputAction.next,
                prefixIcon: SabaIcons.user,
                autofillHints: const [AutofillHints.name],
                serverError: _failure?.messageForField('fullName'),
                maxLength: AppConstants.maxPersonNameLength,
                validator: (value) => Validators.minLength(value, 2, l10n),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: l10n.phone,
                controller: _phoneController,
                isRequired: true,
                readOnly: widget._isPhoneVerified,
                helper: widget._isPhoneVerified ? l10n.numberVerified : null,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                prefixIcon: SabaIcons.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                serverError: _failure?.messageForField('phone'),
                validator: (value) => Validators.phone(value, l10n),
              ),
              // The city, picked from Iraq's 19 governorates: Home shops from
              // it. No country - Saba sells in Iraq only.
              const SizedBox(height: AppSpacing.lg),
              GovernorateField(
                value: _governorate,
                errorText:
                    _governorateError ??
                    _failure?.messageForField('governorate'),
                onChanged: (value) => setState(() {
                  _governorate = value;
                  _governorateError = null;
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: l10n.password,
                hint: context.l10n.passwordHelper,
                controller: _passwordController,
                isRequired: true,
                obscureText: true,
                textInputAction: TextInputAction.next,
                prefixIcon: SabaIcons.lock,
                autofillHints: const [AutofillHints.newPassword],
                helper: l10n.passwordHelper,
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
                textInputAction: TextInputAction.done,
                prefixIcon: SabaIcons.lock,
                validator: (value) => Validators.confirmPassword(
                  value,
                  _passwordController.text,
                  l10n,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
