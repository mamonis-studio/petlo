// ============================================================================
// petlo - Vomit Record Screen (rev5.5)
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
import '../../providers/vomits_providers.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../../widgets/forms/pet_photo_picker.dart';
import '../../widgets/records/count_stepper.dart';
import '../../widgets/records/date_time_picker_row.dart';
import '../../widgets/records/record_amount_selector.dart';
import '../../widgets/records/record_delete_helper.dart';
import '../../widgets/vomit/vomit_color_selector.dart';
import '../paywall/paywall_screen.dart';
import 'vomit_form_controller.dart';
import 'vomit_form_state.dart';

class VomitRecordScreen extends ConsumerStatefulWidget {
  const VomitRecordScreen({this.editingVomitId, super.key});

  final int? editingVomitId;

  static Future<bool?> push(BuildContext context, {int? editingVomitId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VomitRecordScreen(editingVomitId: editingVomitId),
      ),
    );
  }

  @override
  ConsumerState<VomitRecordScreen> createState() => _VomitRecordScreenState();
}

class _VomitRecordScreenState extends ConsumerState<VomitRecordScreen> {
  late final TextEditingController _notesC;
  bool _initialSynced = false;

  @override
  void initState() {
    super.initState();
    _notesC = TextEditingController();
  }

  @override
  void dispose() {
    _notesC.dispose();
    super.dispose();
  }

  void _syncControllers(VomitFormState s) {
    if (_initialSynced) return;
    if (!s.isEditing) {
      _initialSynced = true;
      return;
    }
    if (s.vomitedAt == null) return;
    _notesC.text = s.notes;
    _initialSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final VomitFormState s =
        ref.watch(vomitFormControllerProvider(widget.editingVomitId));
    final VomitFormController controller =
        ref.read(vomitFormControllerProvider(widget.editingVomitId).notifier);

    _syncControllers(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          s.isEditing
              ? AppLocalizations.of(context).appbar_edit_vomit.toUpperCase()
              : AppLocalizations.of(context).appbar_new_vomit.toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            AppLocalizations.of(context).common_cancel.toUpperCase(),
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9,
              letterSpacing: 9 * 0.15,
              color: colors.fgMuted,
            ),
          ),
        ),
        leadingWidth: 80,
        actions: <Widget>[
          if (s.isEditing && widget.editingVomitId != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: colors.fgMuted, size: 22),
              onPressed: _onDelete,
              tooltip: AppLocalizations.of(context).common_delete,
            ),
        ],
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
                    ? AppLocalizations.of(context).common_editing
                    : AppLocalizations.of(context).common_today,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(
                    0, 0, 0, AppDimensions.paddingSection),
              ),

              // 2階層色 (rev5.5)
              VomitColorSelector(
                value: s.color,
                colorOtherText: s.colorOtherText,
                required: true,
                errorText: s.errors.color ?? s.errors.colorOtherText,
                onChanged: controller.updateColor,
                onOtherTextChanged: controller.updateColorOtherText,
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              RecordAmountSelector(
                value: s.amount,
                required: true,
                errorText: s.errors.amount,
                onChanged: controller.updateAmount,
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              CountStepper(
                label: AppLocalizations.of(context).record_field_count,
                value: s.count,
                onChanged: controller.updateCount,
                unitText: '×',
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              // トグル: contains food + suspect ingestion
              _ToggleRow(
                label: AppLocalizations.of(context).vomit_contains_food,
                value: s.containsFood,
                onChanged: controller.updateContainsFood,
              ),
              const SizedBox(height: AppDimensions.gapMedium),
              _ToggleRow(
                label: AppLocalizations.of(context).vomit_foreign_object,
                value: s.suspectIngestion,
                onChanged: controller.updateSuspectIngestion,
                emphasize: true,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              SectionLabel(AppLocalizations.of(context).common_when),
              DateTimePickerRow(
                value: s.vomitedAt,
                onChanged: controller.updateVomitedAt,
                errorText: s.errors.vomitedAt,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

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

              SectionLabel(AppLocalizations.of(context).common_photo_label),
              PetPhotoPicker(
                label: AppLocalizations.of(context).record_field_photo_label,
                currentPhotoFile: s.photoFile,
                currentRelativePath: s.savedPhotoRelativePath,
                onPicked: controller.updatePhotoFile,
              ),
              const SizedBox(height: AppDimensions.paddingSection * 1.5),

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

  Future<void> _onDelete() async {
    if (widget.editingVomitId == null) return;
    final bool ok = await RecordDeleteHelper.confirm(context);
    if (!ok || !mounted) return;
    final bool deleted = await ref
        .read(vomitsRepositoryProvider)
        .softDelete(widget.editingVomitId!);
    if (!mounted) return;
    if (deleted) {
      ref.invalidate(vomitFormControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).common_deleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onSave(VomitFormController controller) async {
    final r = await controller.save(AppLocalizations.of(context));
    switch (r) {
      case VomitFormSaveOutcome.success:
        if (mounted) {
          ref.invalidate(vomitFormControllerProvider);
          Navigator.of(context).pop(true);
        }
      case VomitFormSaveOutcome.validationFailed:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_input_invalid),
                behavior: SnackBarBehavior.floating),
          );
        }
      case VomitFormSaveOutcome.dbError:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_save_failed),
                behavior: SnackBarBehavior.floating),
          );
        }
      case VomitFormSaveOutcome.proLimitReached:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context).pro_limit_record_monthly),
              behavior: SnackBarBehavior.floating,
            ),
          );
          await PaywallScreen.push(context);
        }
    }
  }
}

/// 切り替えトグル(emphasize=trueで警告色寄り)
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.emphasize = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: typo.bodyMedium.copyWith(
              color: emphasize && value ? colors.accentDanger : colors.fg,
              fontWeight: emphasize && value ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: colors.bg,
          activeTrackColor: emphasize ? colors.accentDanger : colors.fg,
        ),
      ],
    );
  }
}
