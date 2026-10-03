import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/location/governorate.dart';
import '../../../../core/location/governorate_picker.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/iraqi_phone.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/saba_tile.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/sticky_bar.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../auth/presentation/widgets/iraqi_phone_field.dart';
import '../../domain/entities.dart';
import '../address_providers.dart';

/// Create or edit a delivery address.
///
/// Asked the way a driver in Iraq finds a house: the city from the list, the
/// area, and the nearest landmark - not a country, a state and a postal code
/// nobody here has. A new address starts with the shopper's own name, number
/// and city, so most people only type where it is.
class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key, this.address});

  /// Null when adding a new address.
  final Address? address;

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _user = ref.read(currentUserProvider);
  late final _label = TextEditingController(text: widget.address?.label);
  late final _fullName = TextEditingController(
    text: widget.address?.fullName ?? _user?.fullName,
  );
  late final _phone = TextEditingController(
    text: switch (widget.address?.phone ?? _user?.phone) {
      final number? => IraqiPhone.local(number),
      null => null,
    },
  );
  late final _area = TextEditingController(text: widget.address?.area);
  late final _landmark = TextEditingController(text: widget.address?.landmark);
  late final _street = TextEditingController(text: widget.address?.street);
  late final _instructions = TextEditingController(
    text: widget.address?.instructions,
  );

  // The city Home delivers to, else the one given at sign-up.
  late Governorate? _governorate = widget.address != null
      ? widget.address!.governorate
      : ref.read(shopperCityProvider);
  String? _governorateError;

  // A first address is the default whatever the switch says, so it starts
  // on; it started off, on an address that was about to be the default.
  late bool _isDefault =
      widget.address?.isDefault ??
      (ref.read(addressListProvider).value?.isEmpty ?? false);
  bool _isSubmitting = false;
  Failure? _failure;

  bool get _isEditing => widget.address != null;

  @override
  void dispose() {
    for (final controller in [
      _label,
      _fullName,
      _phone,
      _area,
      _landmark,
      _street,
      _instructions,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState?.validateAndReveal() ?? false;
    setState(() {
      _failure = null;
      _governorateError = _governorate == null
          ? context.l10n.cityRequired
          : null;
    });
    final city = _governorate;
    if (!valid || city == null) return;

    setState(() => _isSubmitting = true);

    final address = Address(
      id: widget.address?.id ?? '',
      fullName: _fullName.text.trim(),
      phone: IraqiPhone.normalize(_phone.text)!,
      governorate: city,
      area: _area.text.trim(),
      landmark: _landmark.text.trim(),
      street: _optional(_street),
      label: _optional(_label),
      instructions: _optional(_instructions),
      isDefault: _isDefault,
    );

    final controller = ref.read(addressListProvider.notifier);
    final result = _isEditing
        ? await controller.edit(address)
        : await controller.create(address);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    result.fold(
      ok: (_) => Navigator.of(context).pop(),
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

    return Scaffold(
      appBar: SabaAppBar(
        title: _isEditing ? l10n.editAddress : l10n.addAddress,
      ),
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
                        SectionCard(
                          title: l10n.addressWho,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppTextField(
                                label: l10n.fullName,
                                hint: context.exampleOf(
                                  context.l10n.exPersonName,
                                ),
                                controller: _fullName,
                                isRequired: true,
                                prefixIcon: SabaIcons.user,
                                textInputAction: TextInputAction.next,
                                serverError: _failure?.messageForField(
                                  'fullName',
                                ),
                                maxLength: AppConstants.maxPersonNameLength,
                                validator: (value) =>
                                    Validators.minLength(value, 2, l10n),
                              ),
                              gap,
                              IraqiPhoneField(
                                controller: _phone,
                                helper: l10n.driverCallsThisNumber,
                                serverError: _failure?.messageForField('phone'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md + 2),
                        SectionCard(
                          title: l10n.addressWhere,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                              AppTextField(
                                label: l10n.area,
                                hint: l10n.areaHint,
                                controller: _area,
                                isRequired: true,
                                prefixIcon: SabaIcons.mapPin,
                                textInputAction: TextInputAction.next,
                                serverError: _failure?.messageForField('area'),
                                validator: (value) =>
                                    Validators.required(value, l10n),
                              ),
                              gap,
                              AppTextField(
                                label: l10n.nearestLandmark,
                                hint: l10n.nearestLandmarkHint,
                                controller: _landmark,
                                isRequired: true,
                                prefixIcon: SabaIcons.flag,
                                textInputAction: TextInputAction.next,
                                serverError: _failure?.messageForField(
                                  'landmark',
                                ),
                                validator: (value) =>
                                    Validators.required(value, l10n),
                              ),
                              gap,
                              AppTextField(
                                label: l10n.streetAndHouse,
                                hint: context.exampleOf(context.l10n.exStreet),
                                controller: _street,
                                prefixIcon: SabaIcons.home,
                                textInputAction: TextInputAction.next,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md + 2),
                        SectionCard(
                          title: l10n.addressExtras,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppTextField(
                                // Was labelled "Default address", directly above
                                // the switch that actually sets the default.
                                label: l10n.addressNickname,
                                hint: l10n.addressNicknameHint,
                                controller: _label,
                                textInputAction: TextInputAction.next,
                              ),
                              gap,
                              AppTextField(
                                label: l10n.deliveryInstructions,
                                hint: context.exampleOf(
                                  context.l10n.exInstructions,
                                ),
                                controller: _instructions,
                                maxLines: 3,
                                maxLength: 300,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              SabaTile(
                                label: l10n.setAsDefault,
                                onTap: () =>
                                    setState(() => _isDefault = !_isDefault),
                                trailing: Switch.adaptive(
                                  value: _isDefault,
                                  onChanged: (value) =>
                                      setState(() => _isDefault = value),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                StickyBar(
                  child: AppButton(
                    label: _isEditing ? l10n.saveChanges : l10n.save,
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
