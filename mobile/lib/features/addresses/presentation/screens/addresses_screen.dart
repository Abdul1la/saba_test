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
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/results_chrome.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/sticky_bar.dart';
import '../../domain/entities.dart';
import '../address_providers.dart';
import '../../../../core/utils/iraqi_phone.dart';

/// Where the customer's orders go.
///
/// "Add an address" sits in a sticky bar rather than a floating button: the
/// design has no FAB, and a circle that hovers over the last card hides part
/// of what it is meant to be added to.
class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final addresses = ref.watch(addressListProvider);
    final controller = ref.read(addressListProvider.notifier);

    return Scaffold(
      appBar: SabaAppBar(title: l10n.addresses),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: AsyncStateView<List<Address>>(
                value: addresses,
                onRetry: () => ref.invalidate(addressListProvider),
                loadingBuilder: (_) => const ListSkeleton(itemHeight: 140),
                builder: (items) {
                  if (items.isEmpty) {
                    return NoResultsView(
                      icon: SabaIcons.mapPin,
                      title: l10n.emptyAddresses,
                      message: l10n.emptyAddressesMessage,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenGutter,
                        AppSpacing.sm,
                        AppSpacing.screenGutter,
                        AppSpacing.xl,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md + 2),
                      itemBuilder: (context, index) => _AddressCard(
                        address: items[index],
                        onEdit: () => context.push(
                          AppRoutes.addressForm,
                          extra: items[index],
                        ),
                        onDelete: () =>
                            _confirmDelete(context, ref, items[index]),
                        // The callback one line above reports its failure;
                        // this one dropped the Result, so a failed change
                        // left the badge where it was and said nothing.
                        onSetDefault: () async {
                          final result = await controller.setDefault(
                            items[index].id,
                          );
                          if (!context.mounted) return;
                          result.fold(
                            ok: (_) {},
                            err: (failure) =>
                                AppSnackBar.failure(context, failure),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            StickyBar(
              child: AppButton(
                label: l10n.addAddress,
                icon: SabaIcons.plus,
                onPressed: () => context.push(AppRoutes.addressForm),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Address address,
  ) async {
    final l10n = context.l10n;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteAddressTitle,
      message: l10n.deleteAddressMessage,
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final result = await ref
        .read(addressListProvider.notifier)
        .delete(address.id);
    if (!context.mounted) return;

    result.fold(
      ok: (_) {},
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }
}

/// One saved address.
///
/// The default one is marked with a badge rather than only a coloured border:
/// "which one will this order go to" is a question a border alone answers
/// poorly, and not at all to someone who cannot separate the two colours.
class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  final Address address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final isDefault = address.isDefault;
    final label = address.label;

    // The whole card opens the address to edit; the Edit button says so.
    return Material(
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: isDefault
              ? market.success.withValues(alpha: 0.45)
              : market.border,
          width: isDefault ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDefault ? market.successSoft : market.infoSoft,
                      borderRadius: BorderRadius.circular(AppRadius.action),
                    ),
                    child: SabaIcon(
                      SabaIcons.mapPin,
                      size: AppSizes.iconLg,
                      color: isDefault ? market.success : market.info,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label ?? address.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (label != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            address.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.bodySmall?.copyWith(
                              fontSize: 13,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isDefault) ...[
                    const SizedBox(width: AppSpacing.sm),
                    StatusBadge(
                      label: l10n.defaultAddress,
                      tone: StatusTone.positive,
                      compact: true,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.md + 2),
              // Where and who to call, each by its own icon, in the text
              // size the rest of the app is read at.
              _Line(
                icon: SabaIcons.home,
                text: address.formattedIn(l10n.locale.languageCode),
              ),
              if (address.landmark.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _Line(
                  icon: SabaIcons.flag,
                  text: '${l10n.nearestLandmark}: ${address.landmark}',
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              _Line(
                icon: SabaIcons.phone,
                text: Formatters.ltrIsolate(IraqiPhone.display(address.phone)),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Big, and each saying what it does: a small grey pencil and
              // two plain words were missed. Edit and "Set as default" are
              // the second level, purple on white; only Delete is red. One
              // height for all, should a word take two lines.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _CardAction(
                        icon: SabaIcons.pencil,
                        label: l10n.edit,
                        ink: context.colors.primary,
                        fill: context.colors.surface,
                        outlined: true,
                        onTap: onEdit,
                      ),
                    ),
                    if (!isDefault) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _CardAction(
                          icon: SabaIcons.check,
                          label: l10n.setAsDefault,
                          ink: context.colors.primary,
                          fill: context.colors.surface,
                          outlined: true,
                          onTap: onSetDefault,
                        ),
                      ),
                    ],
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _CardAction(
                        icon: SabaIcons.trash,
                        label: l10n.delete,
                        ink: context.colors.error,
                        fill: market.errorSoft,
                        onTap: onDelete,
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

/// A line of the address card: its icon, then the words.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: SabaIcon(
            icon,
            size: AppSizes.iconSm,
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: context.textStyles.bodyMedium?.copyWith(
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the card's buttons: a coloured tile, the icon over its word.
/// Stacked rather than side by side so three fit a phone in either language.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.ink,
    required this.fill,
    required this.onTap,
    this.outlined = false,
  });

  final String icon;
  final String label;
  final Color ink;
  final Color fill;
  final VoidCallback onTap;

  /// Edged in [ink]: the second button level.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.action);

    return Semantics(
      button: true,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: outlined ? BorderSide(color: ink, width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm + 2,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SabaIcon(icon, size: AppSizes.iconMd, color: ink),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.textStyles.labelMedium?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ink,
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
