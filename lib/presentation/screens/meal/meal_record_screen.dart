// ============================================================================
// petlo - Meal Record Screen
// ============================================================================
//
// 食事記録の新規/編集画面。
//
// 構造:
//   ┌──────────────────────────┐
//   │ ← Cancel  NEW MEAL       │
//   ├──────────────────────────┤
//   │ Today's meal             │
//   │ Quietly noted.           │
//   │                          │
//   │ § RECENT                 │
//   │ [Royal] [Hill's] [Other] │
//   │                          │
//   │ Food                     │
//   │ ___________________       │  ← フリー入力 or 直近選択
//   │                          │
//   │ Amount [80] g            │
//   │                          │
//   │ Appetite                 │
//   │ ●●●●● Ate all 等の5択     │
//   │                          │
//   │ When [2026/05/04 19:30] │
//   │                          │
//   │ Notes (optional)         │
//   │                          │
//   │ Photo                    │
//   │                          │
//   │ [SAVE]                   │
//   └──────────────────────────┘
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../widgets/forms/date_field.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../../widgets/forms/pet_photo_picker.dart';
import '../../providers/meals_providers.dart';
import '../../widgets/meal/meal_appetite_selector.dart';
import '../../widgets/meal/recent_foods_row.dart';
import '../../widgets/records/record_delete_helper.dart';
import 'meal_form_controller.dart';
import 'meal_form_state.dart';

class MealRecordScreen extends ConsumerStatefulWidget {
  const MealRecordScreen({this.editingMealId, super.key});

  /// 編集モード時の食事記録ID。null なら新規作成。
  final int? editingMealId;

  static Future<bool?> push(BuildContext context, {int? editingMealId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => MealRecordScreen(editingMealId: editingMealId),
      ),
    );
  }

  @override
  ConsumerState<MealRecordScreen> createState() => _MealRecordScreenState();
}

class _MealRecordScreenState extends ConsumerState<MealRecordScreen> {
  late final TextEditingController _foodC;
  late final TextEditingController _amountC;
  late final TextEditingController _notesC;

  bool _initialSynced = false;

  @override
  void initState() {
    super.initState();
    _foodC = TextEditingController();
    _amountC = TextEditingController();
    _notesC = TextEditingController();
  }

  @override
  void dispose() {
    _foodC.dispose();
    _amountC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  void _syncControllers(MealFormState s) {
    if (_initialSynced) return;
    if (!s.isEditing) {
      _initialSynced = true;
      return;
    }
    // 編集時のロード後にControllerに反映
    if (s.foodNameFreeText.isEmpty && s.eatenAt == null) return;
    _foodC.text = s.foodNameFreeText;
    _amountC.text = s.amountG?.toString() ?? '';
    _notesC.text = s.notes;
    _initialSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final MealFormState s =
        ref.watch(mealFormControllerProvider(widget.editingMealId));
    final MealFormController controller =
        ref.read(mealFormControllerProvider(widget.editingMealId).notifier);

    _syncControllers(s);

    // 銘柄選択時に foodC.text を同期
    ref.listen<MealFormState>(
      mealFormControllerProvider(widget.editingMealId),
      (MealFormState? prev, MealFormState next) {
        // foodIdが変わった (= 直近チップが選ばれた) ときだけテキスト同期
        if (prev?.foodId != next.foodId &&
            next.foodId != null &&
            _foodC.text != next.foodNameFreeText) {
          _foodC.text = next.foodNameFreeText;
        }
        // amountG が外部から変わったとき (e.g. defaultAmountG コピー)
        if (prev?.amountG != next.amountG &&
            next.amountG != null &&
            _amountC.text != next.amountG.toString()) {
          _amountC.text = next.amountG.toString();
        }
      },
    );

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: _buildAppBar(s),
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
              _buildPageTitle(s.isEditing),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Recent Foods =====
              RecentFoodsRow(
                selectedFoodId: s.foodId,
                onFoodSelected: controller.selectExistingFood,
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              // ===== Food Name (free text) =====
              EditorialTextField(
                label: AppLocalizations.of(context).record_field_food,
                controller: _foodC,
                required: true,
                hint: AppLocalizations.of(context).record_field_food_hint,
                errorText: s.errors.foodName,
                onChanged: controller.updateFoodNameFreeText,
                maxLength: 100,
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              // ===== Amount =====
              EditorialTextField(
                label: AppLocalizations.of(context).record_field_amount,
                controller: _amountC,
                hint: AppLocalizations.of(context).record_field_amount_optional_hint,
                suffixText: 'g',
                keyboardType: TextInputType.number,
                errorText: s.errors.amountG,
                onChanged: (String v) =>
                    controller.updateAmountG(int.tryParse(v)),
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              // ===== Appetite =====
              MealAppetiteSelector(
                value: s.appetite,
                required: true,
                errorText: s.errors.appetite,
                onChanged: controller.updateAppetite,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== When =====
              SectionLabel(AppLocalizations.of(context).common_when),
              _DateTimePickerRow(
                value: s.eatenAt,
                onChanged: controller.updateEatenAt,
                errorText: s.errors.eatenAt,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Notes =====
              SectionLabel(AppLocalizations.of(context).common_notes),
              EditorialTextField(
                label: AppLocalizations.of(context).record_field_notes_label,
                controller: _notesC,
                hint: AppLocalizations.of(context).record_field_notes_hint,
                maxLines: 3,
                minLines: 2,
                onChanged: controller.updateNotes,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Photo =====
              SectionLabel(AppLocalizations.of(context).common_photo_label),
              PetPhotoPicker(
                label: AppLocalizations.of(context).record_field_photo_label,
                currentPhotoFile: s.photoFile,
                currentRelativePath: s.savedPhotoRelativePath,
                onPicked: controller.updatePhotoFile,
              ),
              const SizedBox(height: AppDimensions.paddingSection * 1.5),

              // ===== Save =====
              PrimaryButton(
                label: s.isSubmitting
                    ? AppLocalizations.of(context).common_saving
                    : (s.isEditing
                        ? AppLocalizations.of(context).common_update
                        : AppLocalizations.of(context).common_save),
                onPressed: s.isSubmitting ? null : () => _onSave(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // AppBar
  // ============================================================================
  PreferredSizeWidget _buildAppBar(MealFormState s) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return AppBar(
      backgroundColor: colors.bg,
      foregroundColor: colors.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Text(
        s.isEditing
            ? AppLocalizations.of(context).appbar_edit_meal.toUpperCase()
            : AppLocalizations.of(context).appbar_new_meal.toUpperCase(),
        style: typo.metaSmall.copyWith(letterSpacing: 10 * 0.2),
      ),
      centerTitle: true,
      leading: TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(
          AppLocalizations.of(context).common_cancel.toUpperCase(),
          style: typo.metaSmall.copyWith(color: colors.fgMuted),
        ),
      ),
      leadingWidth: 80,
      actions: <Widget>[
        if (s.isEditing && widget.editingMealId != null)
          IconButton(
            icon: Icon(Icons.delete_outline, color: colors.fgMuted, size: 22),
            onPressed: () => _onDelete(),
            tooltip: AppLocalizations.of(context).common_delete,
          ),
      ],
    );
  }

  Future<void> _onDelete() async {
    if (widget.editingMealId == null) return;
    final bool ok = await RecordDeleteHelper.confirm(context);
    if (!ok || !mounted) return;
    final bool deleted =
        await ref.read(mealsRepositoryProvider).softDelete(widget.editingMealId!);
    if (!mounted) return;
    if (deleted) {
      ref.invalidate(mealFormControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).common_deleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  // ============================================================================
  // Page title
  // ============================================================================
  Widget _buildPageTitle(bool isEditing) {
    return Builder(
      builder: (BuildContext context) {
        return SectionLabel(
          isEditing
              ? AppLocalizations.of(context).common_editing
              : AppLocalizations.of(context).common_today,
          size: EyebrowSize.large,
          padding: EdgeInsets.zero,
        );
      },
    );
  }

  // ============================================================================
  // Save
  // ============================================================================
  Future<void> _onSave(MealFormController controller) async {
    final MealFormSaveOutcome outcome =
        await controller.save(AppLocalizations.of(context));

    switch (outcome) {
      case MealFormSaveOutcome.success:
        if (mounted) {
          ref.invalidate(mealFormControllerProvider);
          Navigator.of(context).pop(true);
        }

      case MealFormSaveOutcome.validationFailed:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_input_invalid),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

      case MealFormSaveOutcome.dbError:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).pet_form_error_save_failed),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }
}

// ============================================================================
// DateTime picker (date + time)
// ============================================================================
class _DateTimePickerRow extends StatelessWidget {
  const _DateTimePickerRow({
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            // Date
            Expanded(
              flex: 3,
              child: DateField(
                label: AppLocalizations.of(context).record_field_date,
                value: value,
                firstDate: DateTime(DateTime.now().year - 1),
                lastDate: DateTime.now(),
                onChanged: (DateTime? picked) {
                  if (picked == null) {
                    onChanged(null);
                  } else {
                    final DateTime t = value ?? DateTime.now();
                    onChanged(DateTime(picked.year, picked.month, picked.day,
                        t.hour, t.minute));
                  }
                },
              ),
            ),
            const SizedBox(width: AppDimensions.gapMedium),
            // Time
            Expanded(
              flex: 2,
              child: _TimeField(
                value: value,
                onChanged: (TimeOfDay? t) {
                  if (t == null) return;
                  final DateTime base = value ?? DateTime.now();
                  onChanged(DateTime(base.year, base.month, base.day, t.hour, t.minute));
                },
              ),
            ),
          ],
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: typo.bodySmall.copyWith(color: colors.accentDanger),
          ),
        ],
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.value,
    required this.onChanged,
  });

  final DateTime? value;
  final ValueChanged<TimeOfDay?> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final TimeOfDay? tod = value == null
        ? null
        : TimeOfDay(hour: value!.hour, minute: value!.minute);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(AppLocalizations.of(context).common_time),
        const SizedBox(height: AppDimensions.gapSmall),
        InkWell(
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: tod ?? TimeOfDay.now(),
              builder: (BuildContext c, Widget? child) {
                return Theme(
                  data: Theme.of(c).copyWith(
                    colorScheme: ColorScheme.light(
                      primary: AppColors.of(c).fg,
                      onPrimary: AppColors.of(c).bg,
                      surface: AppColors.of(c).bg,
                      onSurface: AppColors.of(c).fg,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  tod == null
                      ? AppLocalizations.of(context).record_field_tap_to_select
                      : tod.format(context),
                  style: typo.bodyLarge.copyWith(
                    color: tod == null ? colors.fgFaint : colors.fg,
                    fontFeatures: <FontFeature>[
                      const FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Icon(Icons.access_time, size: 18, color: colors.fgMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
