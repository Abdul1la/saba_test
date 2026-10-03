import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/config/api_endpoints.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/location/governorate.dart';
import '../../../../core/location/governorate_picker.dart';
import '../../../../core/location/store_delivery.dart';
import '../../../media/domain/entities.dart';
import '../../../media/presentation/media_providers.dart';
import '../../../media/presentation/widgets/media_upload_field.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json_reader.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/option_sheet.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/presentation/auth_providers.dart';

/// Editable store profile (specification section 22).
class StoreSettings {
  const StoreSettings({
    required this.storeName,
    this.description,
    this.businessAddress,
    this.businessType,
    this.governorate,
    this.returnPolicy,
    this.logoUrl,
    this.delivery,
  });

  final String storeName;
  final String? description;

  /// Where the shop is. Asked here, not at sign-up: a store starts with its
  /// name and city.
  final String? businessAddress;
  final String? businessType;
  final Governorate? governorate;
  final String? returnPolicy;

  /// The store's own picture. Every store used to be a grey box for ever.
  final String? logoUrl;

  /// Where the store delivers and what it asks.
  final StoreDelivery? delivery;
}

final storeSettingsProvider = FutureProvider<StoreSettings>((ref) async {
  ref.watch(accountIdProvider);
  final result = await ref
      .watch(apiClientProvider)
      .get<StoreSettings>(
        ApiEndpoints.merchantStoreSettings,
        decoder: (envelope) {
          final json = envelope.dataAsMap;
          return StoreSettings(
            storeName: Json.str(json, const [
              'storeName',
              'name',
              'businessName',
            ]),
            description: Json.strOrNull(json, const ['description', 'about']),
            businessAddress: Json.strOrNull(json, const ['businessAddress']),
            businessType: Json.strOrNull(json, const ['businessType']),
            governorate: Governorate.fromApi(
              json['governorate'] ?? json['city'],
            ),
            logoUrl: Json.strOrNull(json, const ['logoUrl', 'logo']),
            returnPolicy: Json.strOrNull(json, const ['returnPolicy']),
            delivery: StoreDelivery.fromJson(json['delivery']),
          );
        },
      );
  return result.unwrap();
});

class MerchantStoreSettingsScreen extends ConsumerWidget {
  const MerchantStoreSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storeSettingsProvider);

    return Scaffold(
      appBar: SabaAppBar(
        title: context.l10n.storeSettings,
        backFallback: AppRoutes.merchantAccount,
      ),
      body: AsyncStateView<StoreSettings>(
        value: settings,
        onRetry: () => ref.invalidate(storeSettingsProvider),
        builder: (value) => _StoreSettingsForm(settings: value),
      ),
    );
  }
}

class _StoreSettingsForm extends ConsumerStatefulWidget {
  const _StoreSettingsForm({required this.settings});

  final StoreSettings settings;

  @override
  ConsumerState<_StoreSettingsForm> createState() => _StoreSettingsFormState();
}

class _StoreSettingsFormState extends ConsumerState<_StoreSettingsForm> {
  final _formKey = GlobalKey<FormState>();

  late final _storeName = TextEditingController(
    text: widget.settings.storeName,
  );
  late final _description = TextEditingController(
    text: widget.settings.description ?? '',
  );
  late final _businessAddress = TextEditingController(
    text: widget.settings.businessAddress ?? '',
  );

  /// Required: shoppers see it on every card of the store. Iraq only, so
  /// there is no country to ask for.
  late Governorate? _governorate = widget.settings.governorate;
  String? _governorateError;

  // Delivery: where to, and at what fee and time, in its own city and out.
  late final Set<Governorate> _deliversTo = {
    ...?widget.settings.delivery?.governorates,
  };
  late final MediaSlot _logoSlot = MediaSlot(
    id: 'store-logo',
    constraints: MediaConstraints.avatar,
  );

  late final _feeInside = TextEditingController(
    text: widget.settings.delivery?.feeInside.round().toString() ?? '',
  );
  late final _feeOutside = TextEditingController(
    text: widget.settings.delivery?.feeOutside?.round().toString() ?? '',
  );
  late DeliveryTime? _timeInside = widget.settings.delivery?.timeInside;
  late DeliveryTime? _timeOutside = widget.settings.delivery?.timeOutside;
  String? _timeInsideError;
  String? _timeOutsideError;

  bool _isSubmitting = false;
  Failure? _failure;

  /// Every city it delivers to; its own always, wherever that is now.
  Set<Governorate> get _cities => {..._deliversTo, ?_governorate};

  bool get _goesOut => _cities.any((city) => city != _governorate);

  @override
  void initState() {
    super.initState();
    // Opens holding the logo the store has, so what it shows is what is
    // saved; it opened empty, and a new logo looked as if it had not taken.
    // The frame after, as the product form seeds its photos.
    final logo = widget.settings.logoUrl;
    if (logo != null && logo.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(mediaUploadProvider(_logoSlot).notifier).setExisting([
          UploadedMedia(id: logo, url: logo, kind: MediaKind.image),
        ]);
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _storeName,
      _description,
      _businessAddress,
      _feeInside,
      _feeOutside,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _pickTime({required bool inside}) async {
    final l10n = context.l10n;
    final picked = await AppDialogs.bottomSheet<DeliveryTime>(
      context,
      builder: (_) => OptionSheet<DeliveryTime>(
        title: inside ? l10n.timeInYourCity : l10n.timeOtherCities,
        options: DeliveryTime.values,
        labelOf: (time) => time.label(context),
        current: inside ? _timeInside : _timeOutside,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (inside) {
        _timeInside = picked;
        _timeInsideError = null;
      } else {
        _timeOutside = picked;
        _timeOutsideError = null;
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final l10n = context.l10n;
    setState(() {
      _failure = null;
      _governorateError = _governorate == null ? l10n.cityRequired : null;
      _timeInsideError = _timeInside == null ? l10n.chooseDeliveryTime : null;
      _timeOutsideError = _goesOut && _timeOutside == null
          ? l10n.chooseDeliveryTime
          : null;
    });
    final valid = _formKey.currentState?.validateAndReveal() ?? false;
    if (!valid ||
        _governorate == null ||
        _timeInsideError != null ||
        _timeOutsideError != null) {
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await ref
        .read(apiClientProvider)
        .command(
          ApiEndpoints.merchantStoreSettings,
          method: 'PUT',
          data: <String, dynamic>{
            'storeName': _storeName.text.trim(),
            'description': ?_optional(_description),
            'businessAddress': ?_optional(_businessAddress),
            // Always sent: empty is the store taking its logo away.
            'logoUrl': ref
                .read(mediaUploadProvider(_logoSlot).notifier)
                .uploadedMedia
                .firstOrNull
                ?.url,
            'governorate': _governorate!.apiValue,
            'delivery': StoreDelivery(
              governorates: _cities,
              feeInside: Formatters.typedNumber(_feeInside.text)!,
              timeInside: _timeInside!,
              feeOutside: _goesOut
                  ? Formatters.typedNumber(_feeOutside.text)!
                  : null,
              timeOutside: _goesOut ? _timeOutside : null,
            ).toJson(),
          },
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    result.fold(
      ok: (_) {
        ref.invalidate(storeSettingsProvider);
        // The store name shows in the merchant shell, so refresh the session.
        ref.read(authControllerProvider.notifier).refreshUser();
        // This screen edits the store, not the person. "Profile" is the
        // word the merchant account screen uses for their own details.
        AppSnackBar.success(context, context.l10n.storeUpdated);
      },
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const gap = SizedBox(height: AppSpacing.lg);
    final digits = [FilteringTextInputFormatter.digitsOnly];

    return SafeArea(
      child: ContentContainer(
        maxWidth: 720,
        child: Form(
          key: _formKey,
          // A column, not a list: a list builds only the fields on screen,
          // and a form checks only the fields that are built, so a mistake
          // scrolled out of sight went unreported.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  label: l10n.storeName,
                  hint: context.exampleOf(context.l10n.exStoreName),
                  controller: _storeName,
                  isRequired: true,
                  textInputAction: TextInputAction.next,
                  serverError: _failure?.messageForField('storeName'),
                  maxLength: AppConstants.maxStoreNameLength,
                  validator: (value) => Validators.minLength(value, 2, l10n),
                ),
                gap,
                AppTextField(
                  label: l10n.storeDescription,
                  hint: context.exampleOf(context.l10n.exStoreDescription),
                  controller: _description,
                  maxLines: 4,
                  maxLength: 1000,
                ),
                gap,
                AppTextField(
                  label: l10n.businessAddress,
                  hint: context.exampleOf(context.l10n.exBusinessAddress),
                  controller: _businessAddress,
                  maxLength: 120,
                  serverError: _failure?.messageForField('businessAddress'),
                ),
                gap,
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
                gap,
                MediaUploadField(slot: _logoSlot, label: l10n.storeLogo),
                gap,
                SectionCard(
                  title: l10n.deliverySettings,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DeliveryCities(
                        home: _governorate,
                        chosen: _cities,
                        onChanged: (cities) => setState(() {
                          _deliversTo
                            ..clear()
                            ..addAll(cities);
                        }),
                      ),
                      gap,
                      AppTextField(
                        label: l10n.feeInYourCity,
                        hint: context.exampleOf(3000),
                        controller: _feeInside,
                        isRequired: true,
                        helper: l10n.zeroIsFree,
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        serverError: _failure?.messageForField('feeInside'),
                        validator: (value) => Validators.cashFee(value, l10n),
                      ),
                      gap,
                      PickerField(
                        label: l10n.timeInYourCity,
                        value: _timeInside?.label(context),
                        hint: l10n.chooseDeliveryTime,
                        errorText: _timeInsideError,
                        onTap: () => _pickTime(inside: true),
                      ),
                      if (_goesOut) ...[
                        gap,
                        AppTextField(
                          label: l10n.feeOtherCities,
                          hint: context.exampleOf(5000),
                          controller: _feeOutside,
                          isRequired: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: digits,
                          serverError: _failure?.messageForField('feeOutside'),
                          validator: (value) => Validators.cashFee(value, l10n),
                        ),
                        gap,
                        PickerField(
                          label: l10n.timeOtherCities,
                          value: _timeOutside?.label(context),
                          hint: l10n.chooseDeliveryTime,
                          errorText: _timeOutsideError,
                          onTap: () => _pickTime(inside: false),
                        ),
                      ],
                    ],
                  ),
                ),
                gap,
                // One rule for every store, so not a field.
                Text(l10n.returnRuleStore, style: context.textStyles.bodySmall),
                const SizedBox(height: AppSpacing.xxl),
                AppButton(
                  label: l10n.saveChanges,
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Iraq's governorates as chips, the store's own always on, with the two
/// answers most stores give one tap away.
class _DeliveryCities extends StatelessWidget {
  const _DeliveryCities({
    required this.home,
    required this.chosen,
    required this.onChanged,
  });

  final Governorate? home;
  final Set<Governorate> chosen;
  final ValueChanged<Set<Governorate>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.whereYouDeliver, style: context.textStyles.titleSmall),
        // Under the title, not beside it: side by side, they ran off a
        // narrow phone.
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            TextButton(
              onPressed: () => onChanged(Governorate.values.toSet()),
              child: Text(l10n.wholeIraq),
            ),
            TextButton(
              onPressed: () => onChanged({?home}),
              child: Text(l10n.onlyMyCity),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs + 2,
          runSpacing: AppSpacing.xs + 2,
          children: [
            for (final city in Governorate.values)
              FilterChip(
                label: Text(city.label(context)),
                selected: chosen.contains(city),
                // On the grey of a chip that cannot change, a white tick
                // would vanish.
                checkmarkColor: city == home
                    ? context.colors.onSurfaceVariant
                    : null,
                // A locked chip's own colours were dark on dark in dark mode
                // (the tester): the page's muted fill and its text colour.
                disabledColor: context.market.surfaceMuted,
                labelStyle: city == home
                    ? TextStyle(color: context.colors.onSurface)
                    : null,
                // Its own city is where it is; it always delivers there.
                onSelected: city == home
                    ? null
                    : (on) => onChanged(
                        on ? {...chosen, city} : ({...chosen}..remove(city)),
                      ),
              ),
          ],
        ),
      ],
    );
  }
}
