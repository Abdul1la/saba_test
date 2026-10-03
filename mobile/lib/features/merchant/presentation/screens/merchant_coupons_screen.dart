import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/sticky_bar.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../cart/domain/entities.dart' show CouponOffer;
import '../../../cart/presentation/cart_providers.dart';
import '../../../cart/presentation/widgets/coupon_offers.dart';
import '../../domain/entities.dart';
import '../merchant_providers.dart';

/// The store's discount codes (specification sections 27 and 39).
///
/// Each one is drawn as a ticket: what it takes off on the stub, then the
/// code, whether it is running, when, and how much of it is left. Customers
/// meet the running ones on the store page, on Home and in their cart.
class MerchantCouponsScreen extends ConsumerWidget {
  const MerchantCouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final coupons = ref.watch(merchantCouponsProvider);
    void create() => context.push(AppRoutes.merchantCouponForm);

    return Scaffold(
      appBar: SabaAppBar(
        title: l10n.coupons,
        backFallback: AppRoutes.merchantAccount,
      ),
      body: AsyncStateView<List<MerchantCoupon>>(
        value: coupons,
        onRetry: () => ref.invalidate(merchantCouponsProvider),
        builder: (items) {
          if (items.isEmpty) {
            return EmptyStateView(
              icon: SabaIcons.ticket,
              title: l10n.noCouponsYet,
              message: l10n.noCouponsYetMessage,
              actionLabel: l10n.newCoupon,
              onAction: create,
            );
          }
          final now = DateTime.now();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(merchantCouponsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) =>
                  _CouponTicket(coupon: items[index], now: now),
            ),
          );
        },
      ),
      // Always in reach, and not a floating circle over the last ticket.
      bottomNavigationBar: (coupons.value?.isEmpty ?? true)
          ? null
          : StickyBar(
              child: AppButton(
                label: l10n.newCoupon,
                icon: SabaIcons.plus,
                onPressed: create,
              ),
            ),
    );
  }
}

/// How each status looks, in one place.
(String, StatusTone, Color) _statusLook(
  BuildContext context,
  CouponStatus status,
) {
  final l10n = context.l10n;
  final market = context.market;
  return switch (status) {
    CouponStatus.active => (
      l10n.statusActive,
      StatusTone.positive,
      market.accent,
    ),
    CouponStatus.scheduled => (
      l10n.couponScheduled,
      StatusTone.progress,
      market.info,
    ),
    CouponStatus.paused => (
      l10n.couponPaused,
      StatusTone.caution,
      market.warning,
    ),
    CouponStatus.ended => (
      l10n.couponEnded,
      StatusTone.neutral,
      market.textMuted,
    ),
    CouponStatus.usedUp => (
      l10n.couponUsedUp,
      StatusTone.neutral,
      market.textMuted,
    ),
  };
}

/// "10%" or "5,000 IQD".
String _amountText(BuildContext context, MerchantCoupon coupon) {
  final locale = context.l10n.locale.toLanguageTag();
  return coupon.isPercentage
      ? Formatters.percent(coupon.value, locale: locale)
      : Formatters.money(
          coupon.value,
          locale: locale,
          currencyCode: coupon.currencyCode,
        );
}

class _CouponTicket extends ConsumerWidget {
  const _CouponTicket({required this.coupon, required this.now});

  final MerchantCoupon coupon;
  final DateTime now;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<Result<void>> Function() action, {
    String? done,
  }) async {
    final result = await action();
    if (!context.mounted) return;
    result.fold(
      ok: (_) {
        ref.invalidate(merchantCouponsProvider);
        // What shoppers are offered changed with it.
        ref.invalidate(storeCouponsProvider);
        ref.invalidate(availableCouponsProvider);
        if (done != null) AppSnackBar.success(context, done);
      },
      err: (failure) => AppSnackBar.failure(context, failure),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final sure = await AppDialogs.confirm(
      context,
      title: l10n.deleteCouponQuestion,
      message: l10n.deleteCouponMessage,
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (!sure || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(merchantRepositoryProvider).deleteCoupon(coupon.id),
      done: l10n.couponDeleted,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final market = context.market;
    final locale = l10n.locale.toLanguageTag();
    final status = coupon.statusAt(now);
    final (label, tone, colour) = _statusLook(context, status);
    // Dark mode's status colours are light, and white on them failed (2.5:1
    // on the blue), so there the stub starts a third darker.
    final shade = context.isDarkMode ? 0.35 : 0.0;
    final isOver =
        status == CouponStatus.ended || status == CouponStatus.usedUp;

    String day(DateTime value) => Formatters.date(value, locale: locale);
    final when = status == CouponStatus.scheduled
        ? l10n.startsDate(day(coupon.startsAt))
        : coupon.endsAt == null
        ? l10n.noEndDate
        : l10n.untilDate(day(coupon.endsAt!));
    final minimum = coupon.minOrderAmount;
    final rule = minimum == null
        ? l10n.onAnyOrder
        : '${l10n.onOrdersOver} ${Formatters.money(minimum, locale: locale, currencyCode: coupon.currencyCode)}';
    final limit = coupon.usageLimit;

    void edit() => context.push(AppRoutes.merchantCouponForm, extra: coupon);

    return Material(
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: market.border),
      ),
      child: InkWell(
        onTap: edit,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The stub: what it takes off, in the status's colour.
              Container(
                width: 96,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [
                      Color.lerp(colour, Colors.black, shade)!,
                      Color.lerp(colour, Colors.black, shade + 0.3)!,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SabaIcon(
                      SabaIcons.ticket,
                      size: 18,
                      color: market.onDark.withValues(alpha: 0.85),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _amountText(context, coupon),
                        style: context.textStyles.titleLarge?.copyWith(
                          color: market.onDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const _Perforation(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              coupon.code,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: isOver ? market.textMuted : null,
                              ),
                            ),
                          ),
                          StatusBadge(label: label, tone: tone, compact: true),
                          PopupMenuButton<String>(
                            tooltip: l10n.edit,
                            icon: SabaIcon(
                              SabaIcons.moreVertical,
                              size: AppSizes.iconSm,
                              color: context.colors.onSurfaceVariant,
                            ),
                            onSelected: (choice) => switch (choice) {
                              'edit' => edit(),
                              'toggle' => _run(
                                context,
                                ref,
                                () => ref
                                    .read(merchantRepositoryProvider)
                                    .setCouponActive(
                                      coupon.id,
                                      isActive: !coupon.isActive,
                                    ),
                              ),
                              _ => _delete(context, ref),
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(l10n.edit),
                              ),
                              if (!isOver)
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(
                                    coupon.isActive
                                        ? l10n.pauseCoupon
                                        : l10n.resumeCoupon,
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  l10n.delete,
                                  style: TextStyle(color: context.colors.error),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Text(rule, style: context.textStyles.labelSmall),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          SabaIcon(
                            SabaIcons.clock,
                            size: 13,
                            color: market.textMuted,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              when,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.labelSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (limit != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: limit == 0
                                ? 1
                                : math.min(1, coupon.usedCount / limit),
                            minHeight: 5,
                            color: colour,
                            backgroundColor: market.surfaceMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      Text(
                        l10n.couponUsage(coupon.usedCount, limit),
                        style: context.textStyles.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The torn line between a ticket's stub and its body.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      child: CustomPaint(painter: _DashPainter(color: context.market.border)),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var y = 3.0; y < size.height - 3; y += 8) {
      canvas.drawLine(Offset(0, y), Offset(0, y + 4), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}

/// A new coupon, or one being changed, with the ticket a customer will see
/// drawn live above the fields.
class MerchantCouponFormScreen extends ConsumerStatefulWidget {
  const MerchantCouponFormScreen({super.key, this.coupon});

  /// Null for a new one.
  final MerchantCoupon? coupon;

  @override
  ConsumerState<MerchantCouponFormScreen> createState() =>
      _MerchantCouponFormScreenState();
}

class _MerchantCouponFormScreenState
    extends ConsumerState<MerchantCouponFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _code = TextEditingController(text: widget.coupon?.code ?? '');
  late final _value = TextEditingController(
    text: widget.coupon == null ? '' : '${widget.coupon!.value.round()}',
  );
  late final _minimum = TextEditingController(
    text: widget.coupon?.minOrderAmount?.round().toString() ?? '',
  );
  late final _limit = TextEditingController(
    text: widget.coupon?.usageLimit?.toString() ?? '',
  );

  late bool _isPercentage = widget.coupon?.isPercentage ?? true;
  late DateTime _startsAt = _dayOf(widget.coupon?.startsAt ?? DateTime.now());
  late DateTime? _endsAt = widget.coupon?.endsAt == null
      ? null
      : _dayOf(widget.coupon!.endsAt!);

  bool _isSaving = false;
  Failure? _failure;
  String? _dateError;

  /// The day [value] falls on here. The server sends UTC: Baghdad's
  /// midnight is 21:00 the day before, so the form showed the day before
  /// and saving moved the coupon a day earlier (the backend session).
  static DateTime _dayOf(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  @override
  void dispose() {
    for (final controller in [_code, _value, _minimum, _limit]) {
      controller.dispose();
    }
    super.dispose();
  }

  num? _number(TextEditingController controller) =>
      Formatters.typedNumber(controller.text);

  /// A code from the store's name and the discount: "NOVA10".
  void _suggest() {
    final name = ref.read(currentUserProvider)?.merchant?.storeName ?? '';
    final letters = name.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
    final stem = letters.isEmpty
        ? 'SALE'
        : letters.substring(0, math.min(5, letters.length));
    final tail =
        _number(_value)?.round().toString() ??
        '${10 + math.Random().nextInt(90)}';
    final code = '$stem$tail';
    setState(() {
      _code.text = code
          .substring(0, math.min(15, code.length))
          .padRight(3, '0');
    });
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _startsAt : (_endsAt ?? _startsAt),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startsAt = picked;
      } else {
        _endsAt = picked;
      }
      _dateError = null;
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final l10n = context.l10n;
    setState(() {
      _failure = null;
      _dateError = null;
    });
    final fieldsOk = _formKey.currentState?.validateAndReveal() ?? false;
    final ends = _endsAt;
    if (ends != null && ends.isBefore(_startsAt)) {
      setState(() => _dateError = l10n.endBeforeStart);
      return;
    }
    if (!fieldsOk) return;

    final existing = widget.coupon;
    final coupon = MerchantCoupon(
      id: existing?.id ?? '',
      code: _code.text.trim().toUpperCase(),
      isPercentage: _isPercentage,
      value: _number(_value)!,
      startsAt: _startsAt,
      // To the end of the chosen day, so "Until 30 Sep" includes the 30th.
      endsAt: ends == null
          ? null
          : DateTime(ends.year, ends.month, ends.day, 23, 59, 59),
      minOrderAmount: _number(_minimum),
      usageLimit: _number(_limit)?.toInt(),
      usedCount: existing?.usedCount ?? 0,
      isActive: existing?.isActive ?? true,
    );

    setState(() => _isSaving = true);
    final result = await ref
        .read(merchantRepositoryProvider)
        .saveCoupon(coupon);
    if (!mounted) return;
    setState(() => _isSaving = false);

    result.fold(
      ok: (_) {
        ref.invalidate(merchantCouponsProvider);
        ref.invalidate(storeCouponsProvider);
        ref.invalidate(availableCouponsProvider);
        AppSnackBar.success(context, l10n.couponSaved);
        context.popOrGo(AppRoutes.merchantCoupons);
      },
      err: (failure) {
        setState(() => _failure = failure);
        if (failure.fieldErrors.isEmpty) {
          AppSnackBar.failure(context, failure);
        } else {
          _formKey.currentState?.validateAndReveal();
          final dates =
              failure.messageForField('endsAt') ??
              failure.messageForField('startsAt');
          if (dates != null) setState(() => _dateError = dates);
          // A refusal on anything the form draws no box for was silent,
          // as the product form's was (BUGS 203): said in a message.
          final elsewhere = failure.fieldErrors
              .where((error) => !_fieldsShown.contains(error.field))
              .firstOrNull;
          if (elsewhere != null) AppSnackBar.error(context, elsewhere.message);
        }
      },
    );
  }

  String? _required(String? text, {num? max, bool inDinars = false}) {
    final l10n = context.l10n;
    final value = Formatters.typedNumber(text ?? '');
    if (value == null || value <= 0) return l10n.discountInvalid;
    if (value != value.roundToDouble()) return l10n.wholeNumber;
    if (max != null && value > max) return l10n.percentTooHigh;
    // Money off is handed back in cash, so in steps of the smallest note.
    if (inDinars && value % 250 != 0) return l10n.iqdSteps;
    return null;
  }

  /// The fields a refusal can be shown on, beside their boxes.
  static const _fieldsShown = {
    'code',
    'value',
    'minOrderAmount',
    'usageLimit',
    'startsAt',
    'endsAt',
  };

  String? _optionalWhole(String? text) {
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final value = Formatters.typedNumber(trimmed);
    if (value == null || value <= 0 || value != value.roundToDouble()) {
      return context.l10n.wholeNumber;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final market = context.market;
    final locale = l10n.locale.toLanguageTag();
    final storeName = ref.watch(currentUserProvider)?.merchant?.storeName;
    final digits = <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];

    Widget unit(String text) => Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.md),
      child: Text(
        text,
        style: context.textStyles.labelLarge?.copyWith(color: market.textMuted),
      ),
    );

    final preview = CouponOffer(
      code: _code.text.trim().isEmpty ? 'CODE' : _code.text.trim(),
      isPercentage: _isPercentage,
      value: _number(_value) ?? 0,
      currencyCode: 'IQD',
      minOrderAmount: _number(_minimum),
      merchantId: 'preview',
      merchantName: storeName,
    );

    return Scaffold(
      appBar: SabaAppBar(
        title: widget.coupon == null ? l10n.newCoupon : l10n.editCoupon,
        backFallback: AppRoutes.merchantCoupons,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.couponPreview,
                  style: context.textStyles.labelMedium?.copyWith(
                    color: market.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                IgnorePointer(
                  child: CouponOfferStrip(
                    offers: [preview],
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionCard(
                  title: l10n.discountLabel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTextField(
                        label: l10n.couponCode,
                        hint: context.exampleOf(context.l10n.exCouponCode),
                        controller: _code,
                        helper: l10n.couponCodeHelper,
                        isRequired: true,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[A-Za-z0-9]'),
                          ),
                          LengthLimitingTextInputFormatter(15),
                          _UpperCase(),
                        ],
                        onChanged: (_) => setState(() {}),
                        serverError: _failure?.messageForField('code'),
                        validator: (text) =>
                            RegExp(
                              r'^[A-Z0-9]{3,15}$',
                            ).hasMatch(text?.trim().toUpperCase() ?? '')
                            ? null
                            : l10n.couponCodeInvalid,
                        suffixIcon: TextButton.icon(
                          onPressed: _suggest,
                          icon: SabaIcon(
                            SabaIcons.refresh,
                            size: 15,
                            color: market.accent,
                          ),
                          label: Text(l10n.suggestCode),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: true,
                            label: Text(l10n.discountPercent),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text(l10n.discountAmountIqd),
                          ),
                        ],
                        selected: {_isPercentage},
                        onSelectionChanged: (choice) =>
                            setState(() => _isPercentage = choice.single),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(
                        label: l10n.discountLabel,
                        controller: _value,
                        hint: context.exampleOf(_isPercentage ? 10 : 5000),
                        isRequired: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: digits,
                        onChanged: (_) => setState(() {}),
                        serverError: _failure?.messageForField('value'),
                        validator: (text) => _required(
                          text,
                          max: _isPercentage ? 90 : null,
                          inDinars: !_isPercentage,
                        ),
                        suffixIcon: unit(_isPercentage ? '%' : 'IQD'),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(
                        label: l10n.minimumOrderOptional,
                        hint: context.exampleOf(25000),
                        controller: _minimum,
                        helper: l10n.minimumOrderHelper,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: digits,
                        onChanged: (_) => setState(() {}),
                        validator: _optionalWhole,
                        serverError: _failure?.messageForField(
                          'minOrderAmount',
                        ),
                        suffixIcon: unit('IQD'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _DateField(
                              label: l10n.startsOn,
                              value: Formatters.date(_startsAt, locale: locale),
                              onTap: () => _pickDate(start: true),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: _DateField(
                              label: l10n.endsOn,
                              value: _endsAt == null
                                  ? l10n.noEndDate
                                  : Formatters.date(_endsAt!, locale: locale),
                              onTap: () => _pickDate(start: false),
                              onClear: _endsAt == null
                                  ? null
                                  : () => setState(() => _endsAt = null),
                            ),
                          ),
                        ],
                      ),
                      if (_dateError != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _dateError!,
                          style: context.textStyles.bodySmall?.copyWith(
                            color: context.colors.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(
                        label: l10n.usageLimitOptional,
                        hint: context.exampleOf(100),
                        controller: _limit,
                        helper: l10n.usageLimitHelper,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: digits,
                        validator: _optionalWhole,
                        serverError: _failure?.messageForField('usageLimit'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: StickyBar(
        child: AppButton(
          label: l10n.save,
          icon: SabaIcons.check,
          isLoading: _isSaving,
          onPressed: _save,
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear == null
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SabaIcon(
                    SabaIcons.clock,
                    size: AppSizes.iconSm,
                    color: context.market.textMuted,
                  ),
                )
              : IconButton(
                  onPressed: onClear,
                  tooltip: context.l10n.clear,
                  icon: SabaIcon(SabaIcons.close, size: AppSizes.iconSm),
                ),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.bodyMedium,
        ),
      ),
    );
  }
}

/// Codes are shown and matched in capitals, so they are typed in capitals.
class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
