import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/location/governorate.dart';
import '../../../../core/location/governorate_picker.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/entities.dart';
import '../../../legal/legal_screen.dart';
import '../auth_providers.dart';
import '../widgets/sign_up_step_header.dart';

/// Store sign-up, on one screen: the owner's name, the store's name and its
/// city, then the verified number and a password.
///
/// It was two screens, the second asking for a business address and a
/// description as well; both wait for store settings now, and a store starts
/// with its name and city. The account and a store in `PENDING` are created
/// together, and selling stays off until Saba approves the store, which the
/// backend enforces rather than this screen (section 21).
class RegisterMerchantScreen extends ConsumerStatefulWidget {
  const RegisterMerchantScreen({
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
  ConsumerState<RegisterMerchantScreen> createState() =>
      _RegisterMerchantScreenState();
}

class _RegisterMerchantScreenState
    extends ConsumerState<RegisterMerchantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  /// Required: shoppers see where a store is on every card of it.
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
    _storeNameController.dispose();
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
    if (!valid || _governorate == null) return;

    setState(() => _isSubmitting = true);

    final result = await ref
        .read(authControllerProvider.notifier)
        .registerMerchant(
          MerchantRegistration(
            fullName: _nameController.text.trim(),
            password: _passwordController.text,
            phone: _phoneController.text.trim(),
            phoneVerificationToken: widget.phoneToken,
            storeName: _storeNameController.text.trim(),
            // Every v1 store is one shop with one owner. Asking a phone
            // shop to pick between "sole proprietorship" and
            // "distributor" bought nothing and stopped people.
            businessType: 'INDIVIDUAL',
            // The market is Iraq; nobody is asked to type it.
            country: AppConfig.homeCountry,
            governorate: _governorate!.apiValue,
          ),
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    switch (result) {
      case Ok<User>():
        AppSnackBar.info(context, context.l10n.merchantPendingApproval);
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
      title: l10n.yourStore,
      subtitle: l10n.storeSignUpSubtitle,
      action: AppButton(
        label: l10n.signUp,
        isLoading: _isSubmitting,
        onPressed: _submit,
      ),
      footer: LegalLinks(note: l10n.agreeToTerms),
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
                serverError: _failure?.messageForField('fullName'),
                maxLength: AppConstants.maxPersonNameLength,
                validator: (value) => Validators.minLength(value, 2, l10n),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: l10n.storeName,
                hint: context.exampleOf(context.l10n.exStoreName),
                controller: _storeNameController,
                isRequired: true,
                textInputAction: TextInputAction.next,
                prefixIcon: SabaIcons.store,
                serverError: _failure?.messageForField('storeName'),
                maxLength: AppConstants.maxStoreNameLength,
                validator: (value) => Validators.minLength(value, 2, l10n),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Shown to buyers on every card of the store, so a local shop
              // reads as local. The country is not asked: the market is Iraq.
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
                label: l10n.phone,
                controller: _phoneController,
                isRequired: true,
                readOnly: widget._isPhoneVerified,
                helper: widget._isPhoneVerified ? l10n.numberVerified : null,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                prefixIcon: SabaIcons.phone,
                serverError: _failure?.messageForField('phone'),
                validator: (value) => Validators.phone(value, l10n),
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
              const SizedBox(height: AppSpacing.xl),
              // What happens next, not "awaiting approval": the store does
              // not exist until this form is sent.
              _PendingApprovalNotice(message: l10n.storeReviewAfterSignUp),
            ],
          ),
        ),
      ],
    );
  }
}

class _PendingApprovalNotice extends StatelessWidget {
  const _PendingApprovalNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.market.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.market.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SabaIcon(
            SabaIcons.info,
            size: AppSizes.iconMd,
            color: context.market.info,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: context.textStyles.bodySmall)),
        ],
      ),
    );
  }
}
