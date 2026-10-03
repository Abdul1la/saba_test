import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/location/governorate.dart';
import '../../../../core/location/governorate_picker.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/sticky_bar.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../merchant/presentation/merchant_providers.dart';
import '../../../../core/utils/iraqi_phone.dart';

/// Edit the signed-in customer's profile.
///
/// Email is shown but not editable here: changing it is a verification flow,
/// not a form field. It used to be drawn as a greyed-out input, which invites
/// a tap that does nothing — it is now plainly a fact about the account, with
/// the one action it does have attached.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _phone;

  /// The shopper's city, from the same list as everywhere else.
  late Governorate? _governorate = ref.read(currentUserProvider)?.governorate;

  bool _isSubmitting = false;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _fullName = TextEditingController(text: user?.fullName ?? '');
    _phone = TextEditingController(
      text: Formatters.ltrIsolate(IraqiPhone.display(user?.phone ?? '')),
    );
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _failure = null);
    if (!(_formKey.currentState?.validateAndReveal() ?? false)) return;

    setState(() => _isSubmitting = true);

    final result = await ref
        .read(authControllerProvider.notifier)
        .updateProfile(
          fullName: _fullName.text.trim(),
          governorate: _governorate?.apiValue,
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    result.fold(
      ok: (_) => AppSnackBar.success(context, context.l10n.profileUpdated),
      err: (failure) {
        setState(() => _failure = failure);
        if (failure.fieldErrors.isEmpty) {
          AppSnackBar.failure(context, failure);
        } else {
          _formKey.currentState?.validateAndReveal();
        }
      },
    );
  }

  Future<void> _deleteAccount() async {
    final l10n = context.l10n;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteAccountTitle,
      message: l10n.deleteAccountMessage,
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final result = await ref
        .read(authControllerProvider.notifier)
        .deleteAccount();
    if (!mounted) return;

    result.fold(
      ok: (_) {},
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  /// A store's account is deleted by request: its orders, returns and last
  /// bill outlive the tap (BACKEND_READY.md, "Deleting a store's account").
  /// The store closes at once; the account goes once they are done.
  Future<void> _deleteStoreAccount() async {
    final l10n = context.l10n;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteStoreAccountTitle,
      message: l10n.deleteStoreAccountMessage,
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final result = await ref.read(merchantRepositoryProvider).requestDeletion();
    if (!mounted) return;

    result.fold(
      ok: (_) => _deletionChanged(),
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  Future<void> _keepStoreAccount() async {
    final l10n = context.l10n;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.keepMyAccountTitle,
      message: l10n.keepMyAccountMessage,
      confirmLabel: l10n.keepMyAccount,
    );
    if (!confirmed || !mounted) return;

    final result = await ref.read(merchantRepositoryProvider).cancelDeletion();
    if (!mounted) return;

    result.fold(
      ok: (_) {
        AppSnackBar.success(context, l10n.accountKept);
        _deletionChanged();
      },
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  /// The account says whether a deletion waits; this page and the
  /// dashboard's switch follow it.
  Future<void> _deletionChanged() async {
    ref
      ..invalidate(storeDeletionProvider)
      ..invalidate(merchantDashboardProvider);
    await ref.read(authControllerProvider.notifier).refreshUser();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = ref.watch(currentUserProvider);
    final isStore = ref.watch(currentRoleProvider).isMerchant;

    if (user == null) {
      return Scaffold(
        appBar: SabaAppBar(title: l10n.myProfile),
        body: NoResultsView(
          icon: SabaIcons.user,
          title: l10n.guestTitle,
          message: l10n.guestMessage,
        ),
      );
    }

    return Scaffold(
      appBar: SabaAppBar(title: l10n.editProfile),
      body: SafeArea(
        top: false,
        child: ContentContainer(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.sm,
                      AppSpacing.screenGutter,
                      AppSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // No email card: v1 has no email.
                        AppTextField(
                          label: l10n.fullName,
                          hint: context.exampleOf(context.l10n.exPersonName),
                          controller: _fullName,
                          isRequired: true,
                          prefixIcon: SabaIcons.user,
                          textInputAction: TextInputAction.next,
                          serverError: _failure?.messageForField('fullName'),
                          maxLength: AppConstants.maxPersonNameLength,
                          validator: (value) =>
                              Validators.minLength(value, 2, l10n),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        // The number the account signs in with, so it is not
                        // changed from here: a new number has to be proven by
                        // SMS first, and support does that.
                        AppTextField(
                          label: l10n.phone,
                          controller: _phone,
                          readOnly: true,
                          helper: l10n.phoneSignInHelper,
                          prefixIcon: SabaIcons.phone,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        GovernorateField(
                          value: _governorate,
                          errorText: _failure?.messageForField('governorate'),
                          onChanged: (value) =>
                              setState(() => _governorate = value),
                        ),
                        const SizedBox(height: AppSpacing.xxxl),
                        // Its own card at the bottom, saying what it does. A
                        // lone red line under the City field read as part of
                        // the form, one short scroll from Save.
                        // A shopper deletes on the spot; a store asks, and
                        // then sees what the deletion waits for.
                        if (!isStore)
                          _EndCard(
                            icon: SabaIcons.trash,
                            title: l10n.deleteAccount,
                            hint: l10n.deleteAccountHint,
                            onTap: _deleteAccount,
                          )
                        else if (user.merchant?.deletionRequestedAt
                            case final askedAt?)
                          _DeletionCard(
                            askedAt: askedAt,
                            onKeep: _keepStoreAccount,
                          )
                        else
                          _EndCard(
                            icon: SabaIcons.trash,
                            title: l10n.deleteAccount,
                            hint: l10n.deleteStoreAccountHint,
                            onTap: _deleteStoreAccount,
                          ),
                      ],
                    ),
                  ),
                ),
                StickyBar(
                  child: AppButton(
                    label: l10n.saveChanges,
                    isLoading: _isSubmitting,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The last card on the page: deleting a shopper's account, or closing a
/// store.
class _EndCard extends StatelessWidget {
  const _EndCard({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final error = context.colors.error;

    return Material(
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: error.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.action),
                ),
                child: SabaIcon(icon, size: AppSizes.iconMd, color: error),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.textStyles.titleMedium?.copyWith(
                        fontSize: 14.5,
                        color: error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(hint, style: context.textStyles.labelSmall),
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

/// A store's account waiting to be deleted: since when, what it still
/// waits for, how the owner hears it is done, and the way back.
class _DeletionCard extends ConsumerWidget {
  const _DeletionCard({required this.askedAt, required this.onKeep});

  final DateTime askedAt;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = l10n.locale.toLanguageTag();
    final error = context.colors.error;
    final deletion = ref.watch(storeDeletionProvider).value;
    final until = deletion?.returnsOpenUntil;
    final lines = [
      if (deletion != null && deletion.openOrders > 0)
        l10n.stillOpenOrders(deletion.openOrders),
      if (deletion != null && deletion.openReturns > 0)
        l10n.openReturns(deletion.openReturns),
      if (until != null)
        l10n.returnsOpenUntil(Formatters.date(until, locale: locale)),
      if (deletion != null && deletion.owed > 0)
        l10n.stillOwed(
          Formatters.money(
            deletion.owed,
            locale: locale,
            currencyCode: deletion.currencyCode,
          ),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.storeDeletionTitle,
            style: context.textStyles.titleMedium?.copyWith(
              fontSize: 14.5,
              color: error,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.storeDeletionAsked(Formatters.date(askedAt, locale: locale)),
            style: context.textStyles.labelSmall,
          ),
          // Until it has loaded, nothing rather than a wrong "nothing left".
          if (deletion != null) ...[
            const SizedBox(height: AppSpacing.md),
            if (lines.isEmpty)
              Text(l10n.storeDeletionSoon)
            else ...[
              Text(l10n.storeDeletionWaitsFor),
              const SizedBox(height: AppSpacing.xs),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(line, style: context.textStyles.titleSmall),
                ),
              // Never paid, never deleted: the store stays closed.
              if (deletion.owed > 0)
                Text(
                  l10n.storeDeletionUnpaid,
                  style: context.textStyles.labelSmall,
                ),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.storeDeletionSms, style: context.textStyles.labelSmall),
          const SizedBox(height: AppSpacing.xs),
          TextButton(onPressed: onKeep, child: Text(l10n.keepMyAccount)),
        ],
      ),
    );
  }
}
