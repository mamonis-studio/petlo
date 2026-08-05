// ============================================================================
// petlo - Prevention Dose Sheet
// ============================================================================
//
// 月マスをタップしたときのボトムシート。1 回分の投与を記録 / 取り消す。
//
// 投与を記録すると repository が同一トランザクションで medications へも
// 1 行 INSERT する (§6)。記録・取り消しの直後には必ず通知を積み直す。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prevention/prevention_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/outlined_action_button.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../data/repositories/prevention_doses_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/notification_coordinator_provider.dart';
import '../../providers/prevention_providers.dart';
import '../../providers/pro_status_provider.dart';
import '../../providers/scope_providers.dart';
import '../forms/date_field.dart';

class PreventionDoseSheet extends ConsumerStatefulWidget {
  const PreventionDoseSheet({
    required this.course,
    required this.dose,
    super.key,
  });

  final PreventionCourseEntity course;
  final PreventionDoseEntity dose;

  static Future<void> show(
    BuildContext context, {
    required PreventionCourseEntity course,
    required PreventionDoseEntity dose,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).bg,
      builder: (_) => PreventionDoseSheet(course: course, dose: dose),
    );
  }

  @override
  ConsumerState<PreventionDoseSheet> createState() =>
      _PreventionDoseSheetState();
}

class _PreventionDoseSheetState extends ConsumerState<PreventionDoseSheet> {
  late DateTime _administeredAt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final int? recorded = widget.dose.administeredAt;
    if (recorded != null) {
      _administeredAt = DateTime.fromMillisecondsSinceEpoch(recorded);
    } else {
      // 予定日が未来なら今日、過去なら予定日を初期値にする。
      final DateTime scheduled =
          DateTime.fromMillisecondsSinceEpoch(widget.dose.scheduledDate);
      final DateTime now = DateTime.now();
      _administeredAt = scheduled.isAfter(now) ? now : scheduled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String localeTag = Localizations.localeOf(context).toLanguageTag();
    final bool canEdit = ref.watch(canEditProvider);

    final PreventionDoseEntity dose = widget.dose;
    final PreventionDoseStatus status =
        PreventionDosesRepository.statusOf(dose);
    final DateTime scheduled =
        DateTime.fromMillisecondsSinceEpoch(dose.scheduledDate);
    final bool isRecorded = dose.administeredAt != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppDimensions.paddingPage,
          AppDimensions.paddingSection,
          AppDimensions.paddingPage,
          AppDimensions.paddingSection +
              MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionLabel(
              l10n.prevention_dose_sheet_title(
                PreventionLabels.monthLabel(scheduled.month, localeTag),
              ),
              size: EyebrowSize.large,
              padding: const EdgeInsets.only(bottom: AppDimensions.gapMedium),
            ),

            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    formatFullDate(scheduled, localeTag),
                    style: typo.bodyMedium.copyWith(color: colors.fgMuted),
                  ),
                ),
                Text(
                  PreventionLabels.doseStatus(status, l10n),
                  style: typo.metaSmall.copyWith(
                    color: status == PreventionDoseStatus.overdue
                        ? colors.accentDanger
                        : colors.fg,
                  ),
                ),
              ],
            ),
            if (dose.isFinal) ...<Widget>[
              const SizedBox(height: AppDimensions.gapSmall),
              Text(
                l10n.prevention_final_badge,
                style: typo.metaSmall.copyWith(color: colors.fg),
              ),
            ],
            const SizedBox(height: AppDimensions.paddingSection),

            if (isRecorded) ...<Widget>[
              Text(
                l10n.prevention_dose_recorded_at(
                  formatFullDate(
                    DateTime.fromMillisecondsSinceEpoch(dose.administeredAt!),
                    localeTag,
                  ),
                ),
                style: typo.bodyMedium,
              ),
              const SizedBox(height: AppDimensions.paddingSection),
              if (canEdit)
                OutlinedActionButton(
                  label: l10n.prevention_dose_undo_action,
                  onPressed: _busy ? null : _undo,
                ),
            ] else if (dose.skipped) ...<Widget>[
              if (canEdit)
                OutlinedActionButton(
                  label: l10n.prevention_dose_unskip_action,
                  onPressed: _busy ? null : () => _setSkipped(false),
                ),
            ] else if (canEdit) ...<Widget>[
              DateField(
                label: l10n.prevention_dose_record_action,
                value: _administeredAt,
                firstDate: DateTime(scheduled.year - 1),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                onChanged: (DateTime? v) {
                  if (v != null) setState(() => _administeredAt = v);
                },
              ),
              const SizedBox(height: AppDimensions.paddingSection),
              PrimaryButton(
                label: _busy
                    ? l10n.common_saving
                    : l10n.prevention_dose_record_action,
                onPressed: _busy ? null : _record,
              ),
              const SizedBox(height: AppDimensions.gapMedium),
              OutlinedActionButton(
                label: l10n.prevention_dose_skip_action,
                onPressed: _busy ? null : () => _setSkipped(true),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // Actions
  // ==========================================================================

  Future<void> _record() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await _run(() async {
      await ref.read(preventionDosesRepositoryProvider).recordAdministration(
            doseId: widget.dose.id,
            administeredAtMsec: _administeredAt.millisecondsSinceEpoch,
            medicineNameFallback:
                PreventionLabels.kind(widget.course.kind, l10n),
          );
    });
  }

  Future<void> _undo() async {
    await _run(() async {
      await ref
          .read(preventionDosesRepositoryProvider)
          .undoAdministration(widget.dose.id);
    });
  }

  Future<void> _setSkipped(bool skipped) async {
    await _run(() async {
      await ref
          .read(preventionDosesRepositoryProvider)
          .setSkipped(widget.dose.id, skipped);
    });
  }

  /// DB 更新 → 該当 dose の通知を落として全体を積み直す (§6 step 5-6)。
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      final scheduler = ref.read(preventionNotificationSchedulerProvider);
      await scheduler.cancelDose(widget.dose.id);
      await ref
        .read(notificationCoordinatorProvider)
        .rescheduleAll(isPro: ref.read(isProProvider));
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      PetloLogger.instance
          .w('prevention dose action failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).common_save_failed),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
