// ============================================================================
// petlo - Temperature Record Screen
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../providers/temperatures_providers.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../../widgets/health/temperature_input_field.dart';
import '../../widgets/records/date_time_picker_row.dart';
import '../../widgets/records/record_delete_helper.dart';
import 'temperature_form_controller.dart';
import 'temperature_form_state.dart';

class TemperatureRecordScreen extends ConsumerStatefulWidget {
  const TemperatureRecordScreen({this.editingTempId, super.key});

  final int? editingTempId;

  static Future<bool?> push(BuildContext context, {int? editingTempId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            TemperatureRecordScreen(editingTempId: editingTempId),
      ),
    );
  }

  @override
  ConsumerState<TemperatureRecordScreen> createState() =>
      _TemperatureRecordScreenState();
}

class _TemperatureRecordScreenState
    extends ConsumerState<TemperatureRecordScreen> {
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

  void _syncControllers(TemperatureFormState s) {
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
    final TemperatureFormState s = ref
        .watch(temperatureFormControllerProvider(widget.editingTempId));
    final TemperatureFormController controller = ref.read(
        temperatureFormControllerProvider(widget.editingTempId).notifier);

    _syncControllers(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          s.isEditing
              ? AppLocalizations.of(context).appbar_edit_temperature.toUpperCase()
              : AppLocalizations.of(context).appbar_new_temperature.toUpperCase(),
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
          if (s.isEditing && widget.editingTempId != null)
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
              EyebrowText(AppLocalizations.of(context).common_today),
              const SizedBox(height: 8),
              Text(
                s.isEditing
                    ? AppLocalizations.of(context).common_update
                    : AppLocalizations.of(context).record_hero_temperature,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontStyle: FontStyle.italic,
                  fontSize: 40,
                  letterSpacing: -40 * 0.04,
                  height: 1.0,
                  color: colors.fg,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              TemperatureInputField(
                tempCelsiusX10: s.tempCelsiusX10,
                unit: s.unit,
                petType: s.petType, // 正常範囲ヒント表示
                required: true,
                errorText: s.errors.tempCelsiusX10,
                onTemperatureChanged: controller.updateTempCelsiusX10,
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
    if (widget.editingTempId == null) return;
    final bool ok = await RecordDeleteHelper.confirm(context);
    if (!ok || !mounted) return;
    final bool deleted = await ref
        .read(temperaturesRepositoryProvider)
        .softDelete(widget.editingTempId!);
    if (!mounted) return;
    if (deleted) {
      ref.invalidate(temperatureFormControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).common_deleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onSave(TemperatureFormController controller) async {
    final r = await controller.save();
    switch (r) {
      case TemperatureFormSaveOutcome.success:
        if (mounted) {
          ref.invalidate(temperatureFormControllerProvider);
          Navigator.of(context).pop(true);
        }
      case TemperatureFormSaveOutcome.validationFailed:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_input_invalid),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case TemperatureFormSaveOutcome.dbError:
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
