// ============================================================================
// petlo - Prevention Course Form Screen
// ============================================================================
//
// 予防コースの作成 / 編集 (build 72)。
//
// 入力順序は §8.3 で固定:
//   1. ペット選択
//   2. 種別選択
//   3. 地域選択 → 開始月・終了月が自動入力される
//        ↓ 直下に免責文 (prevention_disclaimer_period) を常設表示
//   4. 投与日と通知時刻
//   5. 薬剤名・用量・剤型 (任意)
//   6. [フィラリア/オールインワンのみ] シーズン前検査
//        ↓ 免責文 (prevention_disclaimer_test) を常設表示
//   7. 保存 → dose を materialize → 通知スケジュール
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/forms/choice_chips.dart';
import '../../../core/notifications/notification_permission_prompt.dart';
import '../../../core/prevention/prevention_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/pets_providers.dart';
import '../../providers/notification_coordinator_provider.dart';
import '../../providers/pro_status_provider.dart';
import '../../widgets/forms/date_field.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../../widgets/prevention/prevention_disclaimer.dart';
import '../paywall/paywall_screen.dart';
import 'prevention_course_form_controller.dart';
import 'prevention_course_form_state.dart';

class PreventionCourseFormScreen extends ConsumerStatefulWidget {
  const PreventionCourseFormScreen({this.editingCourseId, super.key});

  final int? editingCourseId;

  static Future<bool?> push(BuildContext context, {int? editingCourseId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            PreventionCourseFormScreen(editingCourseId: editingCourseId),
      ),
    );
  }

  @override
  ConsumerState<PreventionCourseFormScreen> createState() =>
      _PreventionCourseFormScreenState();
}

class _PreventionCourseFormScreenState
    extends ConsumerState<PreventionCourseFormScreen> {
  late final TextEditingController _medicineC;
  late final TextEditingController _dosageC;
  bool _initialSynced = false;

  @override
  void initState() {
    super.initState();
    _medicineC = TextEditingController();
    _dosageC = TextEditingController();
  }

  @override
  void dispose() {
    _medicineC.dispose();
    _dosageC.dispose();
    super.dispose();
  }

  void _syncControllers(PreventionCourseFormState s) {
    if (_initialSynced) return;
    // build 73: 編集モードかは **widget が最初から知っている**。
    // 以前は s.isEditing を見ていたが、これは
    // `editingXxxId != null` であり、ロード前の初期 State では false になる。
    // その結果「新規作成」と誤判定して _initialSynced を立ててしまい、
    // 後からデータが届いても controller へ反映されなかった
    // (アプリ再起動後の初回だけ入力欄が空になる不具合)。
    //
    // 「値が無い」と「まだ読めていない」を混同しないこと。
    if (widget.editingCourseId == null) {
      _initialSynced = true;
      return;
    }
    // 編集時は非同期ロードが終わるまで待つ (petId が入ったら確定とみなす)
    if (s.petId == null) return;
    _medicineC.text = s.medicineName;
    _dosageC.text = s.dosage;
    _initialSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String localeTag = Localizations.localeOf(context).toLanguageTag();
    final PreventionCourseFormState s = ref
        .watch(preventionCourseFormControllerProvider(widget.editingCourseId));
    final PreventionCourseFormController controller = ref.read(
        preventionCourseFormControllerProvider(widget.editingCourseId)
            .notifier);

    _syncControllers(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          (s.isEditing
                  ? l10n.prevention_form_appbar_edit
                  : l10n.prevention_form_appbar_new)
              .toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            l10n.common_cancel.toUpperCase(),
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9,
              letterSpacing: 9 * 0.15,
              color: colors.fgMuted,
            ),
          ),
        ),
        leadingWidth: 80,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.paddingPage,
            AppDimensions.paddingPage,
            AppDimensions.paddingPage,
            AppDimensions.paddingPage * 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionLabel(
                s.isEditing
                    ? l10n.prevention_form_hero_edit
                    : l10n.prevention_form_hero_new,
                size: EyebrowSize.large,
                padding: const EdgeInsets.only(
                    bottom: AppDimensions.paddingSection),
              ),

              // ===== 1. ペット =====
              _PetSelector(
                value: s.petId,
                onChanged: controller.updatePetId,
                errorText: s.errors.petId,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 2. 種別 =====
              ChoiceChips<PreventionKind>(
                label: l10n.prevention_kind_label,
                options: PreventionKind.values,
                value: s.kind,
                required: true,
                optionLabel: (PreventionKind k) =>
                    PreventionLabels.kind(k, l10n),
                onChanged: controller.updateKind,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 対象年 (§8.4: 編集モードのみ) =====
              // 作成フローにはステップを足さない。作成時は自動解決のまま。
              if (s.showsYearField) ...<Widget>[
                _YearField(
                  year: s.resolvedYear,
                  enabled: s.canEditYear,
                  onChanged: controller.updateYear,
                ),
                const SizedBox(height: AppDimensions.paddingSection),
              ],

              // ===== 3. 地域 → 期間 =====
              ChoiceChips<PreventionRegion>(
                label: l10n.prevention_region_label,
                options: PreventionRegion.values,
                value: s.region,
                optionLabel: (PreventionRegion r) =>
                    PreventionLabels.region(r, l10n),
                onChanged: controller.updateRegion,
              ),
              const SizedBox(height: AppDimensions.gapLarge),

              _MonthRangeField(
                label: l10n.prevention_period_label,
                startMonth: s.startMonth,
                endMonth: s.endMonth,
                singleMonth: s.isSingleDose,
                localeTag: localeTag,
                onStartChanged: controller.updateStartMonth,
                onEndChanged: controller.updateEndMonth,
              ),
              const SizedBox(height: AppDimensions.gapLarge),

              // 免責は常設・折りたたみ不可 (§9.1)
              const PreventionDisclaimer(PreventionDisclaimerKind.period),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 4. 投与日 / 通知時刻 =====
              _DayOfMonthField(
                value: s.dayOfMonth,
                errorText: s.errors.dayOfMonth,
                onChanged: controller.updateDayOfMonth,
              ),
              const SizedBox(height: AppDimensions.gapLarge),

              _NotifyTimeField(
                value: s.notifyTime,
                onChanged: controller.updateNotifyTime,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 5. 薬剤情報 (任意) =====
              EditorialTextField(
                label: l10n.prevention_medicine_label,
                hint: l10n.prevention_medicine_hint,
                controller: _medicineC,
                maxLength: 100,
                onChanged: controller.updateMedicineName,
              ),
              const SizedBox(height: AppDimensions.gapLarge),

              EditorialTextField(
                label: l10n.prevention_dosage_label,
                hint: l10n.prevention_dosage_hint,
                controller: _dosageC,
                maxLength: 50,
                onChanged: controller.updateDosage,
              ),
              const SizedBox(height: AppDimensions.gapLarge),

              ChoiceChips<PreventionForm>(
                label: l10n.prevention_form_label,
                options: PreventionForm.values,
                value: s.form,
                optionLabel: (PreventionForm f) =>
                    PreventionLabels.form(f, l10n),
                onChanged: controller.updateForm,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 6. シーズン前検査 =====
              if (s.showsTestSection) ...<Widget>[
                SectionLabel(
                  l10n.prevention_test_section,
                  padding: const EdgeInsets.only(
                      bottom: AppDimensions.gapMedium),
                ),
                DateField(
                  label: l10n.prevention_test_date_label,
                  value: s.testedAt,
                  // 未入力状態の表示。選択肢の「まだ」(prevention_test_not_yet)
                  // とは用途が違うので専用キーを使う。
                  placeholder: l10n.prevention_test_date_empty,
                  errorText: s.errors.testedAt,
                  firstDate: DateTime(DateTime.now().year - 5),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  onChanged: controller.updateTestedAt,
                ),
                if (s.testedAt == null) ...<Widget>[
                  const SizedBox(height: AppDimensions.gapMedium),
                  _ToggleRow(
                    label: l10n.prevention_test_reminder_label,
                    value: s.testReminderEnabled,
                    onChanged: controller.updateTestReminderEnabled,
                  ),
                ],
                const SizedBox(height: AppDimensions.gapLarge),
                // 検査は強制フローにしない。注意喚起に留める (§9.2)
                const PreventionDisclaimer(PreventionDisclaimerKind.test),
                const SizedBox(height: AppDimensions.paddingSection),
              ],

              // ===== 通知 ON/OFF =====
              // 以前はここも prevention_time_label ("通知時刻") を使っており、
              // 上の時刻ピッカーと同じラベルが 2 箇所に出ていた。
              // トグルは有効/無効、ピッカーは時刻。役割ごとにラベルを分ける。
              _ToggleRow(
                label: l10n.prevention_notification_enabled_label,
                value: s.notificationEnabled,
                onChanged: controller.updateNotificationEnabled,
              ),
              const SizedBox(height: AppDimensions.paddingSection * 1.5),

              PrimaryButton(
                label: s.isSubmitting
                    ? l10n.common_saving
                    : (s.isEditing ? l10n.common_update : l10n.common_save),
                onPressed: s.isSubmitting ? null : () => _onSave(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSave(PreventionCourseFormController controller) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PreventionCourseSaveOutcome r = await controller.save(l10n);
    if (!mounted) return;

    switch (r) {
      case PreventionCourseSaveOutcome.success:
        // build 73: 通知を期待した文脈で権限を要求する
        if (mounted) {
          await NotificationPermissionPrompt.ensureGranted(context);
        }
        if (!mounted) return;
        // dose を materialize したので通知を積み直す (§5.4 の再構築トリガー)
        await ref
        .read(notificationCoordinatorProvider)
        .rescheduleAll(isPro: ref.read(isProProvider));
        if (!mounted) return;
        ref.invalidate(preventionCourseFormControllerProvider);
        Navigator.of(context).pop(true);
      case PreventionCourseSaveOutcome.proLimitReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.prevention_paywall_courses),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: l10n.chart_range_pro_only_action,
              onPressed: () => PaywallScreen.push(context),
            ),
          ),
        );
      case PreventionCourseSaveOutcome.validationFailed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.common_input_invalid),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case PreventionCourseSaveOutcome.dbError:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.common_save_failed),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }
}

// ============================================================================
// _PetSelector
// ============================================================================
class _PetSelector extends ConsumerWidget {
  const _PetSelector({
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<PetEntity>> petsAsync =
        ref.watch(currentGroupPetsProvider);

    return petsAsync.maybeWhen(
      data: (List<PetEntity> pets) {
        if (pets.isEmpty) return const SizedBox.shrink();
        return ChoiceChips<int>(
          label: l10n.prevention_pet_label,
          options: pets.map((PetEntity p) => p.id).toList(),
          value: value,
          required: true,
          errorText: errorText,
          optionLabel: (int id) => pets
              .firstWhere((PetEntity p) => p.id == id,
                  orElse: () => pets.first)
              .name,
          onChanged: onChanged,
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ============================================================================
// _YearField - 対象年 (build 73 §8.4)
// ============================================================================
//
// 編集モードでのみ表示する。投与済み / スキップ済みの dose が 1 件でもあれば
// ロックし、理由をヒントで示す。
//
// ロックする理由: 年を変えると全 dose の scheduledDate が動く。§4.3 の
// ルール (c) により実績のある dose は削除されず「コース外の記録」へ退避
// されるが、ユーザーからは記録が消えたように見えてしまう。
//
class _YearField extends StatelessWidget {
  const _YearField({
    required this.year,
    required this.enabled,
    required this.onChanged,
  });

  final int year;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int minYear = PreventionCourseFormState.minSelectableYear;
    final int maxYear = PreventionCourseFormState.maxSelectableYear;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(l10n.prevention_year_label),
        const SizedBox(height: AppDimensions.gapMedium),
        if (enabled)
          _Stepper(
            text: '$year',
            onDecrement: () => onChanged(year > minYear ? year - 1 : minYear),
            onIncrement: () => onChanged(year < maxYear ? year + 1 : maxYear),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingCompact,
              vertical: AppDimensions.paddingRow * 0.7,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: colors.line),
              color: colors.bgSoft,
            ),
            child: Text(
              '$year',
              style: typo.bodyMedium.copyWith(color: colors.fgMuted),
            ),
          ),
        if (!enabled) ...<Widget>[
          const SizedBox(height: AppDimensions.gapSmall),
          Text(
            l10n.prevention_year_locked_hint,
            style: typo.metaSmall.copyWith(color: colors.fgMuted, height: 1.5),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// _MonthRangeField - 開始月 / 終了月
// ============================================================================
class _MonthRangeField extends StatelessWidget {
  const _MonthRangeField({
    required this.label,
    required this.startMonth,
    required this.endMonth,
    required this.singleMonth,
    required this.localeTag,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  final String label;
  final int startMonth;
  final int endMonth;

  /// 注射 (年 1 回) は終了月を持たない
  final bool singleMonth;
  final String localeTag;
  final ValueChanged<int> onStartChanged;
  final ValueChanged<int> onEndChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(label),
        const SizedBox(height: AppDimensions.gapMedium),
        // 裸の数字だけだと開始と終了の区別がつかないので、
        // 各ステッパーに見出しを付け、値にも単位 (月) を持たせる。
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _LabeledStepper(
                caption: l10n.prevention_period_start_label,
                text: PreventionLabels.monthValue(
                    startMonth, l10n, localeTag),
                onDecrement: () =>
                    onStartChanged(startMonth == 1 ? 12 : startMonth - 1),
                onIncrement: () =>
                    onStartChanged(startMonth == 12 ? 1 : startMonth + 1),
              ),
            ),
            if (!singleMonth) ...<Widget>[
              const SizedBox(width: AppDimensions.gapMedium),
              Expanded(
                child: _LabeledStepper(
                  caption: l10n.prevention_period_end_label,
                  text: PreventionLabels.monthValue(
                      endMonth, l10n, localeTag),
                  onDecrement: () =>
                      onEndChanged(endMonth == 1 ? 12 : endMonth - 1),
                  onIncrement: () =>
                      onEndChanged(endMonth == 12 ? 1 : endMonth + 1),
                ),
              ),
            ],
          ],
        ),
        if (!singleMonth) ...<Widget>[
          const SizedBox(height: AppDimensions.gapSmall),
          Text(
            PreventionLabels.period(
              startMonth: startMonth,
              endMonth: endMonth,
              l10n: l10n,
              localeTag: localeTag,
            ),
            style: AppTypography.of(context)
                .metaSmall
                .copyWith(color: AppColors.of(context).fgMuted),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// _DayOfMonthField - 毎月の投与日
// ============================================================================
class _DayOfMonthField extends StatelessWidget {
  const _DayOfMonthField({
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(l10n.prevention_day_label),
        const SizedBox(height: AppDimensions.gapMedium),
        _Stepper(
          text: l10n.prevention_day_value(value),
          onDecrement: () => onChanged(value == 1 ? 31 : value - 1),
          onIncrement: () => onChanged(value == 31 ? 1 : value + 1),
        ),
        if (errorText != null) ...<Widget>[
          const SizedBox(height: AppDimensions.gapTight),
          Text(
            errorText!,
            style: typo.metaSmall.copyWith(color: colors.accentDanger),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// _NotifyTimeField
// ============================================================================
class _NotifyTimeField extends StatelessWidget {
  const _NotifyTimeField({required this.value, required this.onChanged});

  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String text = '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(l10n.prevention_time_label),
        const SizedBox(height: AppDimensions.gapMedium),
        InkWell(
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: value,
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingCompact,
              vertical: AppDimensions.paddingRow * 0.7,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: colors.line),
            ),
            child: Text(text, style: typo.bodyMedium),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// _LabeledStepper - 見出し付きのステッパー
// ============================================================================
class _LabeledStepper extends StatelessWidget {
  const _LabeledStepper({
    required this.caption,
    required this.text,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String caption;
  final String text;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          caption,
          style: typo.metaSmall.copyWith(color: colors.fgMuted),
        ),
        const SizedBox(height: AppDimensions.gapTight),
        _Stepper(
          text: text,
          onDecrement: onDecrement,
          onIncrement: onIncrement,
        ),
      ],
    );
  }
}

// ============================================================================
// _Stepper - − / 値 / + の 3 分割
// ============================================================================
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.text,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String text;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return Container(
      decoration: BoxDecoration(border: Border.all(color: colors.line)),
      child: Row(
        children: <Widget>[
          _StepperButton(symbol: '−', onTap: onDecrement),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: typo.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _StepperButton(symbol: '+', onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.symbol, required this.onTap});

  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: AppDimensions.minTapTarget,
        height: AppDimensions.minTapTarget,
        child: Center(
          child: Text(
            symbol,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 16,
              color: colors.fg,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// _ToggleRow
// ============================================================================
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, style: typo.bodyMedium.copyWith(color: colors.fg)),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: colors.bg,
          activeTrackColor: colors.fg,
        ),
      ],
    );
  }
}
