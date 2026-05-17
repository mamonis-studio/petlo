// ============================================================================
// petlo - Weight Record Screen
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../providers/weights_providers.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../../widgets/health/weight_input_field.dart';
import '../../widgets/records/date_time_picker_row.dart';
import '../../widgets/records/record_delete_helper.dart';
import 'weight_form_controller.dart';
import 'weight_form_state.dart';

class WeightRecordScreen extends ConsumerStatefulWidget {
  const WeightRecordScreen({this.editingWeightId, super.key});

  final int? editingWeightId;

  static Future<bool?> push(BuildContext context, {int? editingWeightId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            WeightRecordScreen(editingWeightId: editingWeightId),
      ),
    );
  }

  @override
  ConsumerState<WeightRecordScreen> createState() =>
      _WeightRecordScreenState();
}

class _WeightRecordScreenState extends ConsumerState<WeightRecordScreen> {
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

  void _syncControllers(WeightFormState s) {
    if (_initialSynced) return;
    if (!s.isEditing) {
      _initialSynced = true;
      return;
    }
    if (s.measuredAt == null) return;
    _notesC.text = s.notes;
    _initialSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final WeightFormState s =
        ref.watch(weightFormControllerProvider(widget.editingWeightId));
    final WeightFormController controller =
        ref.read(weightFormControllerProvider(widget.editingWeightId).notifier);

    _syncControllers(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          s.isEditing
              ? AppLocalizations.of(context).appbar_edit_weight.toUpperCase()
              : AppLocalizations.of(context).appbar_new_weight.toUpperCase(),
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
          if (s.isEditing && widget.editingWeightId != null)
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

              WeightInputField(
                weightG: s.weightG,
                unit: s.unit,
                required: true,
                errorText: s.errors.weightG,
                onWeightChanged: controller.updateWeightG,
                onUnitChanged: controller.updateUnit,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              SectionLabel(AppLocalizations.of(context).common_when),
              DateTimePickerRow(
                value: s.measuredAt,
                onChanged: controller.updateMeasuredAt,
                errorText: s.errors.measuredAt,
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
              const SizedBox(height: AppDimensions.paddingSection * 1.5),

              PrimaryButton(
                label: s.isSubmitting
                    ? AppLocalizations.of(context).common_saving
                    : (s.isEditing
                        ? AppLocalizations.of(context).common_update
                        : AppLocalizations.of(context).common_save),
                onPressed:
                    s.isSubmitting ? null : () => _onSave(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onDelete() async {
    if (widget.editingWeightId == null) return;
    final bool ok = await RecordDeleteHelper.confirm(context);
    if (!ok || !mounted) return;
    final bool deleted = await ref
        .read(weightsRepositoryProvider)
        .softDelete(widget.editingWeightId!);
    if (!mounted) return;
    if (deleted) {
      ref.invalidate(weightFormControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).common_deleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onSave(WeightFormController controller) async {
    final r = await controller.save();
    switch (r) {
      case WeightFormSaveOutcome.success:
        if (mounted) {
          ref.invalidate(weightFormControllerProvider);
          Navigator.of(context).pop(true);
        }
      case WeightFormSaveOutcome.validationFailed:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_input_invalid),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case WeightFormSaveOutcome.dbError:
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
