// ============================================================================
// petlo - Vaccination Record Screen
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../providers/vaccinations_providers.dart';
import '../../widgets/forms/date_field.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../../widgets/forms/pet_photo_picker.dart';
import '../../widgets/records/record_delete_helper.dart';
import 'vaccination_form_controller.dart';
import 'vaccination_form_state.dart';

class VaccinationRecordScreen extends ConsumerStatefulWidget {
  const VaccinationRecordScreen({this.editingVaccinationId, super.key});

  final int? editingVaccinationId;

  static Future<bool?> push(
    BuildContext context, {
    int? editingVaccinationId,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VaccinationRecordScreen(
            editingVaccinationId: editingVaccinationId),
      ),
    );
  }

  @override
  ConsumerState<VaccinationRecordScreen> createState() =>
      _VaccinationRecordScreenState();
}

class _VaccinationRecordScreenState
    extends ConsumerState<VaccinationRecordScreen> {
  late final TextEditingController _kindC;
  late final TextEditingController _clinicC;
  late final TextEditingController _notesC;

  bool _initialSynced = false;

  /// よくあるワクチン種別 (タップで _kindC に挿入)。
  /// build 39: ハードコードを l10n 経由に。FeLV は固有名詞なのでそのまま。
  List<String> _commonKinds(AppLocalizations l10n) => <String>[
        l10n.vaccination_suggestion_combined,
        l10n.vaccination_suggestion_rabies,
        l10n.vaccination_suggestion_leptospira,
        l10n.vaccination_suggestion_cat_three,
        'FeLV',
      ];

  @override
  void initState() {
    super.initState();
    _kindC = TextEditingController();
    _clinicC = TextEditingController();
    _notesC = TextEditingController();
  }

  @override
  void dispose() {
    _kindC.dispose();
    _clinicC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  void _syncControllers(VaccinationFormState s) {
    if (_initialSynced) return;
    if (!s.isEditing) {
      _initialSynced = true;
      return;
    }
    if (s.administeredAt == null) return;
    _kindC.text = s.kind;
    _clinicC.text = s.clinicName;
    _notesC.text = s.notes;
    _initialSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final VaccinationFormState s = ref.watch(
        vaccinationFormControllerProvider(widget.editingVaccinationId));
    final VaccinationFormController controller = ref.read(
        vaccinationFormControllerProvider(widget.editingVaccinationId)
            .notifier);

    _syncControllers(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          s.isEditing
              ? AppLocalizations.of(context).appbar_edit_vaccination.toUpperCase()
              : AppLocalizations.of(context).appbar_new_vaccination.toUpperCase(),
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
          if (s.isEditing && widget.editingVaccinationId != null)
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
                AppLocalizations.of(context).record_vaccination_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(
                    0, 0, 0, AppDimensions.paddingSection),
              ),

              // ===== Kind =====
              EditorialTextField(
                label: AppLocalizations.of(context).record_field_vaccine_kind,
                controller: _kindC,
                required: true,
                hint: AppLocalizations.of(context).record_field_vaccine_kind_hint,
                maxLength: 100,
                errorText: s.errors.kind,
                onChanged: controller.updateKind,
              ),
              const SizedBox(height: AppDimensions.gapMedium),

              // よくある種別の suggestion チップ
              _SuggestionChips(
                kinds: _commonKinds(AppLocalizations.of(context)),
                onTap: (String k) {
                  _kindC.text = k;
                  controller.updateKind(k);
                },
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Dates =====
              SectionLabel(AppLocalizations.of(context).common_when),
              DateField(
                label: AppLocalizations.of(context).record_field_administered,
                value: s.administeredAt,
                required: true,
                errorText: s.errors.administeredAt,
                onChanged: controller.updateAdministeredAt,
                firstDate: DateTime(DateTime.now().year - 10),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              DateField(
                label: AppLocalizations.of(context).record_field_next_due_optional,
                value: s.nextDueAt,
                errorText: s.errors.nextDueAt,
                onChanged: controller.updateNextDueAt,
                firstDate:
                    s.administeredAt ?? DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Clinic =====
              SectionLabel(AppLocalizations.of(context).record_vaccination_section_clinic),
              EditorialTextField(
                label: AppLocalizations.of(context).record_field_clinic_name,
                controller: _clinicC,
                onChanged: controller.updateClinicName,
                maxLength: 100,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Photo (証明書) =====
              SectionLabel(AppLocalizations.of(context).record_vaccination_section_certificate),
              PetPhotoPicker(
                label: AppLocalizations.of(context).record_field_photo_label,
                currentPhotoFile: s.photoFile,
                currentRelativePath: s.savedPhotoRelativePath,
                onPicked: controller.updatePhotoFile,
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
    if (widget.editingVaccinationId == null) return;
    final bool ok = await RecordDeleteHelper.confirm(context);
    if (!ok || !mounted) return;
    final bool deleted = await ref
        .read(vaccinationsRepositoryProvider)
        .softDelete(widget.editingVaccinationId!);
    if (!mounted) return;
    if (deleted) {
      ref.invalidate(vaccinationFormControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).common_deleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onSave(VaccinationFormController controller) async {
    final r = await controller.save(AppLocalizations.of(context));
    switch (r) {
      case VaccinationFormSaveOutcome.success:
        if (mounted) {
          ref.invalidate(vaccinationFormControllerProvider);
          Navigator.of(context).pop(true);
        }
      case VaccinationFormSaveOutcome.validationFailed:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_input_invalid),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case VaccinationFormSaveOutcome.dbError:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_save_failed),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }
}

// ============================================================================
// _SuggestionChips - よくあるワクチン種別を即座に選べる
// ============================================================================
class _SuggestionChips extends StatelessWidget {
  const _SuggestionChips({required this.kinds, required this.onTap});

  final List<String> kinds;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final String k in kinds)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => onTap(k),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.fgMuted, width: 1),
                  ),
                  child: Text(
                    k,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: colors.fg,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
