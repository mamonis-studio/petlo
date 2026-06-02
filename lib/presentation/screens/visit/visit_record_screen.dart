// ============================================================================
// petlo - Visit Record Screen
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../providers/visits_providers.dart';
import '../../widgets/forms/date_field.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../../widgets/forms/multi_photo_picker.dart';
import '../../widgets/records/record_delete_helper.dart';
import '../paywall/paywall_screen.dart';
import 'visit_form_controller.dart';
import 'visit_form_state.dart';

class VisitRecordScreen extends ConsumerStatefulWidget {
  const VisitRecordScreen({this.editingVisitId, super.key});

  final int? editingVisitId;

  static Future<bool?> push(BuildContext context, {int? editingVisitId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VisitRecordScreen(editingVisitId: editingVisitId),
      ),
    );
  }

  @override
  ConsumerState<VisitRecordScreen> createState() => _VisitRecordScreenState();
}

class _VisitRecordScreenState extends ConsumerState<VisitRecordScreen> {
  late final TextEditingController _clinicC;
  late final TextEditingController _vetC;
  late final TextEditingController _reasonC;
  late final TextEditingController _diagnosisC;
  late final TextEditingController _treatmentC;
  late final TextEditingController _costC;
  late final TextEditingController _notesC;

  bool _initialSynced = false;

  @override
  void initState() {
    super.initState();
    _clinicC = TextEditingController();
    _vetC = TextEditingController();
    _reasonC = TextEditingController();
    _diagnosisC = TextEditingController();
    _treatmentC = TextEditingController();
    _costC = TextEditingController();
    _notesC = TextEditingController();
  }

  @override
  void dispose() {
    _clinicC.dispose();
    _vetC.dispose();
    _reasonC.dispose();
    _diagnosisC.dispose();
    _treatmentC.dispose();
    _costC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  void _syncControllers(VisitFormState s) {
    if (_initialSynced) return;
    if (!s.isEditing) {
      _initialSynced = true;
      return;
    }
    if (s.visitedAt == null) return;
    _clinicC.text = s.clinicName;
    _vetC.text = s.vetName;
    _reasonC.text = s.reason;
    _diagnosisC.text = s.diagnosis;
    _treatmentC.text = s.treatment;
    _costC.text = s.costJpy?.toString() ?? '';
    _notesC.text = s.notes;
    _initialSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final VisitFormState s =
        ref.watch(visitFormControllerProvider(widget.editingVisitId));
    final VisitFormController controller =
        ref.read(visitFormControllerProvider(widget.editingVisitId).notifier);

    _syncControllers(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          s.isEditing
              ? AppLocalizations.of(context).appbar_edit_visit.toUpperCase()
              : AppLocalizations.of(context).appbar_new_visit.toUpperCase(),
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
          if (s.isEditing && widget.editingVisitId != null)
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
                AppLocalizations.of(context).record_visit_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(
                    0, 0, 0, AppDimensions.paddingSection),
              ),

              // ===== When =====
              DateField(
                label: AppLocalizations.of(context).record_field_visit_date,
                value: s.visitedAt,
                required: true,
                errorText: s.errors.visitedAt,
                onChanged: controller.updateVisitedAt,
                firstDate: DateTime(DateTime.now().year - 5),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              // ===== Reason =====
              EditorialTextField(
                label: AppLocalizations.of(context).record_field_reason,
                controller: _reasonC,
                required: true,
                hint: AppLocalizations.of(context).record_field_reason_hint,
                maxLength: 200,
                maxLines: 2,
                minLines: 1,
                errorText: s.errors.reason,
                onChanged: controller.updateReason,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Clinic =====
              SectionLabel(AppLocalizations.of(context).record_visit_section_clinic),
              EditorialTextField(
                label: AppLocalizations.of(context).record_field_clinic_name,
                controller: _clinicC,
                onChanged: controller.updateClinicName,
                maxLength: 100,
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              EditorialTextField(
                label: AppLocalizations.of(context).record_field_vet_name,
                controller: _vetC,
                onChanged: controller.updateVetName,
                maxLength: 100,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Outcome =====
              SectionLabel(AppLocalizations.of(context).record_visit_section_outcome),
              EditorialTextField(
                label: AppLocalizations.of(context).record_field_diagnosis,
                controller: _diagnosisC,
                hint: AppLocalizations.of(context).record_field_diagnosis_hint,
                maxLength: 200,
                maxLines: 2,
                minLines: 1,
                onChanged: controller.updateDiagnosis,
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              EditorialTextField(
                label: AppLocalizations.of(context).record_field_treatment,
                controller: _treatmentC,
                hint: AppLocalizations.of(context).record_field_treatment_hint,
                maxLength: 500,
                maxLines: 4,
                minLines: 2,
                onChanged: controller.updateTreatment,
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              EditorialTextField(
                label: AppLocalizations.of(context).record_field_cost_label,
                controller: _costC,
                hint: AppLocalizations.of(context).record_field_amount_optional_hint,
                keyboardType: TextInputType.number,
                suffixText: AppLocalizations.of(context).record_field_cost_suffix,
                errorText: s.errors.costJpy,
                onChanged: (String v) =>
                    controller.updateCostJpy(int.tryParse(v)),
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Photos (検査結果・レシート等、最大5枚) =====
              MultiPhotoPicker(
                label: AppLocalizations.of(context).record_field_photos_label,
                slots: s.photoSlots,
                onSlotsChanged: controller.updatePhotoSlots,
                maxPhotos: 5,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Notes =====
              SectionLabel(AppLocalizations.of(context).common_notes),
              EditorialTextField(
                label: AppLocalizations.of(context).record_field_notes_label,
                controller: _notesC,
                hint: AppLocalizations.of(context).record_field_notes_else_hint,
                maxLines: 3,
                minLines: 2,
                onChanged: controller.updateNotes,
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
    if (widget.editingVisitId == null) return;
    final bool ok = await RecordDeleteHelper.confirm(context);
    if (!ok || !mounted) return;
    final bool deleted = await ref
        .read(visitsRepositoryProvider)
        .softDelete(widget.editingVisitId!);
    if (!mounted) return;
    if (deleted) {
      ref.invalidate(visitFormControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).common_deleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onSave(VisitFormController controller) async {
    final r = await controller.save(AppLocalizations.of(context));
    switch (r) {
      case VisitFormSaveOutcome.success:
        if (mounted) {
          ref.invalidate(visitFormControllerProvider);
          Navigator.of(context).pop(true);
        }
      case VisitFormSaveOutcome.validationFailed:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_input_invalid),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case VisitFormSaveOutcome.dbError:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_save_failed),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case VisitFormSaveOutcome.proLimitReached:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(AppLocalizations.of(context).pro_limit_visit_total),
              behavior: SnackBarBehavior.floating,
            ),
          );
          await PaywallScreen.push(context);
        }
    }
  }
}
