import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/iraqi_phone.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../domain/entities.dart';
import '../auth_providers.dart';
import '../../../../core/widgets/saba_logo.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/iraqi_phone_field.dart';
import '../widgets/sign_up_step_header.dart';
import '../../../../core/widgets/app_text_field.dart';

/// Step one of sign-up, for both roles: the phone number.
///
/// The number comes first because it is the one thing the marketplace cannot
/// work without — it is how a buyer is reached about a delivery and how a
/// seller is reached about an order — and because asking for it alone is a
/// far smaller ask than a ten-field form. Nothing is created here; the account
/// does not exist until the form at the end of the chain is submitted.
class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key, required this.isMerchant});

  final bool isMerchant;

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  bool _isSubmitting = false;
  Failure? _failure;

  /// The number already has an account: said here, with the way in.
  bool _taken = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Always stored and sent in full international form, never as the local
  /// `07xx` a person types. A number that changes shape depending on where it
  /// was entered cannot be matched against itself later.
  String get _fullNumber => IraqiPhone.normalize(_controller.text)!;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _failure = null;
      _taken = false;
    });
    if (!(_formKey.currentState?.validateAndReveal() ?? false)) return;

    setState(() => _isSubmitting = true);
    final phone = _fullNumber;
    final result = await ref
        .read(authRepositoryProvider)
        .sendOtp(phone, purpose: OtpPurpose.signUp);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    result.fold(
      // With SMS checks off the server sends no code and hands back the
      // token itself: skip the code screen, go straight to the details form.
      ok: (challenge) {
        final token = challenge.verificationToken;
        if (token != null) {
          context.push(
            AppRoutes.registerPath(
              merchant: widget.isMerchant,
              phone: phone,
              token: token,
            ),
          );
          return;
        }
        context.push(
          AppRoutes.registerOtpPath(merchant: widget.isMerchant, phone: phone),
          extra: challenge.demoCode,
        );
      },
      err: (failure) {
        if (failure is ConflictFailure) {
          setState(() => _taken = true);
          return;
        }
        setState(() => _failure = failure);
        if (failure.fieldErrors.isEmpty) {
          AppSnackBar.failure(context, failure);
        } else {
          _formKey.currentState?.validateAndReveal();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SignUpStepScaffold(
      centered: true,
      // The logo at the start edge, with the title and the field.
      leading: const Align(
        alignment: AlignmentDirectional.centerStart,
        child: SabaLogo(),
      ),
      step: 1,
      // A seller answers one more question than a buyer - their store - and
      // the bar says so from the first step rather than growing a segment
      // halfway through.
      total: 3,
      title: l10n.whatsYourNumber,
      subtitle: widget.isMerchant
          ? l10n.phoneStepMerchantMessage
          : l10n.phoneStepCustomerMessage,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            label: l10n.sendCode,
            isLoading: _isSubmitting,
            onPressed: _submit,
          ),
          // The role screen is gone from the way in: a shopper starts here,
          // and a store is one tap away.
          if (!widget.isMerchant)
            AuthSwitchLink(
              label: l10n.openStoreOnSaba,
              onPressed: () =>
                  context.push(AppRoutes.registerPhonePath(merchant: true)),
            ),
          AuthSwitchLink(
            prompt: l10n.alreadyHaveAccount,
            label: l10n.signIn,
            onPressed: () => context.go(AppRoutes.login),
          ),
        ],
      ),
      children: [
        Form(
          key: _formKey,
          child: IraqiPhoneField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            serverError: _failure?.messageForField('phone'),
            onSubmitted: (_) => _submit(),
          ),
        ),
        if (_taken) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.phoneTaken,
            style: context.textStyles.bodyMedium?.copyWith(
              color: context.colors.error,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              // The number comes along: it was typed once already.
              onPressed: () => context.go(AppRoutes.signInWith(_fullNumber)),
              child: Text(l10n.signInInstead),
            ),
          ),
        ],
      ],
    );
  }
}
