import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/option_sheet.dart';
import 'governorate.dart';

extension GovernorateLabel on Governorate {
  /// Its name in the app's language.
  String label(BuildContext context) =>
      nameIn(context.l10n.locale.languageCode);
}

/// The list of governorates in a sheet; the one tapped, or null if closed.
Future<Governorate?> pickGovernorate(
  BuildContext context, {
  Governorate? current,
}) => AppDialogs.bottomSheet<Governorate>(
  context,
  builder: (sheetContext) => ConstrainedBox(
    // Nineteen rows would fill the whole screen; the sheet scrolls instead.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
    ),
    child: OptionSheet<Governorate>(
      title: context.l10n.yourCity,
      options: Governorate.values,
      labelOf: (governorate) => governorate.label(context),
      current: current,
    ),
  ),
);

/// A form row for a governorate, drawn like the fields around it.
class GovernorateField extends StatelessWidget {
  const GovernorateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final Governorate? value;
  final ValueChanged<Governorate> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PickerField(
      label: l10n.city,
      value: value?.label(context),
      hint: l10n.chooseYourCity,
      errorText: errorText,
      onTap: () async {
        final picked = await pickGovernorate(context, current: value);
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// "📍 Basra" - where a store is, the same small line on every card of it.
class StoreCity extends StatelessWidget {
  const StoreCity({super.key, required this.city});

  final Governorate city;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SabaIcon(SabaIcons.mapPin, size: 12, color: context.market.textMuted),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            city.label(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.labelSmall?.copyWith(
              fontSize: 11,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The city the shopper is shopping from, kept on this device. Chosen from
/// Home; null until they choose.
class ShopperGovernorate extends Notifier<Governorate?> {
  @override
  Governorate? build() =>
      Governorate.fromApi(ref.watch(appPreferencesProvider).governorate);

  Future<void> choose(Governorate governorate) async {
    state = governorate;
    await ref.read(appPreferencesProvider).setGovernorate(governorate.apiValue);
  }
}

final shopperGovernorateProvider =
    NotifierProvider<ShopperGovernorate, Governorate?>(ShopperGovernorate.new);

/// Where a store is: a pin and the city, small and in the accent colour.
/// Every product is where its store is.
class CityLabel extends StatelessWidget {
  const CityLabel(this.city, {super.key, this.size = 11});

  final Governorate city;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colour = context.market.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SabaIcon(SabaIcons.mapPin, size: size, color: colour),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            city.label(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.labelSmall?.copyWith(
              color: colour,
              fontSize: size,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
