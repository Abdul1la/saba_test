import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/saba_icons.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/localization/failure_messages.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/iraqi_phone.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/entities.dart';
import '../auth_providers.dart';
import '../../../../core/widgets/saba_logo.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/iraqi_phone_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.phone});

  /// A number to start with, in full international form.
  final String? phone;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;

  /// Field-level errors returned by the backend for this submission.
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    // As the field takes it after +964.
    if (widget.phone case final phone?) {
      _phoneController.text = IraqiPhone.local(phone);
    }
  }

  /// Reached again with a number - "Sign in instead" on the number step,
  /// which a first launch now opens from here - this is the same screen, so
  /// its field takes the number: it kept the old one, and the number had to
  /// be typed again.
  @override
  void didUpdateWidget(LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phone case final phone? when phone != oldWidget.phone) {
      _phoneController.text = IraqiPhone.local(phone);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _failure = null);

    if (!(_formKey.currentState?.validateAndReveal() ?? false)) return;

    setState(() => _isSubmitting = true);

    final result = await ref
        .read(authControllerProvider.notifier)
        .signIn(
          // By number only: v1 accounts have no email.
          phone: IraqiPhone.normalize(_phoneController.text),
          password: _passwordController.text,
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    switch (result) {
      case Ok<User>(:final value):
        await _handleSignedIn(value);
      case Err<User>(:final failure):
        // The password was right, but Saba has not checked this number: the
        // code screen, carrying the number and password so the second sign-in
        // sends the code with them. The password rides in `extra`, not a URL.
        if (failure is PhoneNotVerifiedFailure) {
          final phone = IraqiPhone.normalize(_phoneController.text);
          if (phone != null) {
            context.push(
              AppRoutes.verifyPhone,
              extra: (phone, _passwordController.text),
            );
            return;
          }
        }
        setState(() => _failure = failure);
        // Field errors render on the inputs; anything else needs a banner.
        if (failure.fieldErrors.isEmpty) {
          AppSnackBar.failure(context, failure);
        } else {
          _formKey.currentState?.validateAndReveal();
        }
    }
  }

  /// Where a signed-in account belongs.
  ///
  /// Saba's own staff sign in here like anyone else and the router takes them
  /// to `/admin`. This used to sign an admin straight back out with "admin
  /// accounts use the web panel" - written before there was an admin screen,
  /// and left behind when step 4 built one, so the whole demo admin was
  /// unreachable in the running app. Only the tests that called the
  /// controller directly ever got in.
  Future<void> _handleSignedIn(User user) async {
    // Saba's staff use the web panel: the in-app admin is gone (Q12, BUGS
    // 145), so an admin is told where to go, not let into a shopper's app.
    if (user.role == UserRole.unknown || user.role == UserRole.admin) {
      await ref.read(authControllerProvider.notifier).signOut();
      if (!mounted) return;
      AppSnackBar.error(
        context,
        user.role == UserRole.admin
            ? context.l10n.staffUseWebPanel
            : context.l10n.errorGeneric,
      );
      return;
    }

    // Opened on top of a page - Add to cart while signed out - sign-in goes
    // back to that page, just as it was left. The router's redirect only
    // sees the page underneath, so it never closed this form: a customer
    // who signed in correctly was left looking at sign-in. Reached by a
    // redirect instead, the redirect sends them on to where they were going.
    //
    // After the frame, because signing in has already set off the router's
    // refresh, which finishes a moment later and would put this page back.
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final top = router.routerDelegate.currentConfiguration.last;
      if (top.matchedLocation == AppRoutes.login && router.canPop()) {
        router.pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AuthScaffold(
      title: l10n.welcomeToSaba,
      subtitle: l10n.signInSubtitle,
      showBackButton: false,
      logo: const SabaLogo(),
      children: [
        // Demo builds only. Without it the two demo accounts are undiscoverable
        // - the role is decided by whether the address contains "merchant",
        // which nobody can guess - so the seller half of the app is unreachable
        // to anyone who was not told the trick. Disappears with AppConfig.
        if (AppConfig.isDemoMode) ...[
          _DemoAccounts(
            onPick: (number) {
              // As the field takes it after +964: no leading 0.
              _phoneController.text = number.replaceFirst(RegExp('^0'), '');
              _passwordController.text = 'demo1234';
            },
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IraqiPhoneField(
                controller: _phoneController,
                serverError: _failure?.messageForField('phone'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                label: l10n.password,
                hint: context.l10n.passwordHelper,
                controller: _passwordController,
                isRequired: true,
                obscureText: true,
                textInputAction: TextInputAction.done,
                prefixIcon: SabaIcons.lock,
                autofillHints: const [AutofillHints.password],
                serverError: _failure?.messageForField('password'),
                validator: (value) => Validators.password(value, l10n),
                onSubmitted: (_) => _submit(),
              ),
              // With passwords in v1, a forgotten one had no way back in.
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => context.push(AppRoutes.forgotPassword),
                  style: TextButton.styleFrom(
                    foregroundColor: context.market.accent,
                  ),
                  child: Text(l10n.forgotPassword),
                ),
              ),
              if (_failure != null && _failure!.fieldErrors.isEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _ErrorBanner(message: _failure!.localizedMessage(l10n)),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: l10n.signIn,
                isLoading: _isSubmitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
        // Under the sign-in, not pinned to the foot of the screen: this is
        // the first screen now, and a new person's way in. Straight to the
        // number: shopping is the default, and the number step offers "Open
        // a store on Saba" for the rest.
        AuthSwitchLink(
          prompt: l10n.noAccount,
          label: l10n.createAnAccount,
          onPressed: () =>
              context.push(AppRoutes.registerPhonePath(merchant: false)),
        ),
        // The "or" divider is gone with the button that used to sit under
        // it. A divider separating a form from nothing is a promise of a
        // second way in that the screen does not have; the design's second
        // way in is phone sign-in, and that arrives with the OTP flow.
      ],
    );
  }
}

/// Inline banner for errors that belong to the form as a whole rather than to
/// one field, such as "invalid credentials".
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          SabaIcon(
            SabaIcons.alertCircle,
            size: AppSizes.iconMd,
            color: context.colors.onErrorContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two demo accounts, spelled out.
class _DemoAccounts extends StatelessWidget {
  const _DemoAccounts({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: market.infoSoft,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SabaIcon(
                SabaIcons.info,
                size: AppSizes.iconSm,
                color: market.info,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                l10n.demoAccountsTitle,
                style: context.textStyles.titleSmall?.copyWith(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(l10n.demoAccountsNote, style: context.textStyles.labelSmall),
          const SizedBox(height: AppSpacing.sm),
          _DemoChip(
            label: l10n.demoShopper,
            number: '07701234567',
            icon: SabaIcons.shoppingBag,
            tint: (market.info, market.infoSoft),
            onTap: onPick,
          ),
          const SizedBox(height: AppSpacing.sm),
          // Two stores, so one shopper can buy from both and each owner
          // sees only their own part of the order. One under the other, full
          // width: side by side, a 320-wide phone cut Nova to "Nova Elec…".
          _DemoChip(
            label: 'Nova Electronics',
            number: '07711234567',
            icon: SabaIcons.store,
            tint: (market.accent, market.accentSoft),
            onTap: onPick,
          ),
          const SizedBox(height: AppSpacing.sm),
          _DemoChip(
            label: 'Atlas Home',
            number: '07801234567',
            icon: SabaIcons.store,
            tint: (market.success, market.successSoft),
            onTap: onPick,
          ),
        ],
      ),
    );
  }
}

class _DemoChip extends StatelessWidget {
  const _DemoChip({
    required this.label,
    required this.number,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String label;

  /// The local form people type, 0770...
  final String number;
  final String icon;

  /// `(ink, fill)` for the icon tile, so the two accounts differ at a glance.
  final (Color, Color) tint;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.action);

    return Material(
      color: context.colors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: () => onTap(number),
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.$2,
                  borderRadius: BorderRadius.circular(AppRadius.xs + 2),
                ),
                child: SabaIcon(icon, size: AppSizes.iconSm, color: tint.$1),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleSmall?.copyWith(
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      number,
                      // Digits read left to right in Arabic too.
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.labelSmall?.copyWith(
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
