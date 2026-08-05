// ============================================================================
// petlo - Prevention Course Detail Screen
// ============================================================================
//
// 予防コースの詳細 (build 72)。
//
// 構成:
//   - 検査ステータス行
//   - 進捗バー + 次回予定日
//   - 月グリッド (タップで PreventionDoseSheet)
//   - コース外の記録 (再 materialize で範囲外に出た実績)
//   - 医療免責 (最下部・常設)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prevention/prevention_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/widgets/outlined_action_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../data/repositories/prevention_courses_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/notification_coordinator_provider.dart';
import '../../providers/prevention_providers.dart';
import '../../providers/pro_status_provider.dart';
import '../../providers/scope_providers.dart';
import '../../widgets/prevention/prevention_disclaimer.dart';
import '../../widgets/prevention/prevention_dose_sheet.dart';
import '../../widgets/prevention/prevention_month_grid.dart';
import '../../widgets/prevention/prevention_progress_bar.dart';
import 'prevention_course_form_screen.dart';

class PreventionCourseDetailScreen extends ConsumerWidget {
  const PreventionCourseDetailScreen({required this.courseId, super.key});

  final int courseId;

  static Future<void> push(BuildContext context, {required int courseId}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PreventionCourseDetailScreen(courseId: courseId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool canEdit = ref.watch(canEditProvider);
    final AsyncValue<PreventionCourseEntity?> courseAsync =
        ref.watch(preventionCourseProvider(courseId));
    final AsyncValue<List<PreventionDoseEntity>> dosesAsync =
        ref.watch(preventionDosesProvider(courseId));

    final PreventionCourseEntity? course = courseAsync.valueOrNull;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: colors.fg),
        title: Text(
          course == null
              ? l10n.prevention_section_title.toUpperCase()
              : PreventionLabels.kind(course.kind, l10n).toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        actions: <Widget>[
          if (canEdit && course != null) ...<Widget>[
            IconButton(
              icon: Icon(Icons.edit_outlined, color: colors.fgMuted, size: 22),
              tooltip: l10n.common_edit,
              onPressed: () => PreventionCourseFormScreen.push(
                context,
                editingCourseId: courseId,
              ),
            ),
            IconButton(
              icon:
                  Icon(Icons.delete_outline, color: colors.fgMuted, size: 22),
              tooltip: l10n.common_delete,
              onPressed: () => _onDelete(context, ref),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: course == null
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.paddingPage,
                  AppDimensions.paddingSection,
                  AppDimensions.paddingPage,
                  AppDimensions.paddingPage * 2,
                ),
                child: dosesAsync.maybeWhen(
                  data: (List<PreventionDoseEntity> doses) =>
                      _Body(course: course, doses: doses),
                  orElse: () => const SizedBox.shrink(),
                ),
              ),
      ),
    );
  }

  Future<void> _onDelete(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.of(ctx).bg,
        title: Text(l10n.prevention_delete_confirm_title),
        content: Text(l10n.prevention_delete_confirm_body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.common_delete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final scheduler = ref.read(preventionNotificationSchedulerProvider);
    await scheduler.cancelCourse(courseId);
    await ref.read(preventionCoursesRepositoryProvider).softDelete(courseId);
    await ref
        .read(notificationCoordinatorProvider)
        .rescheduleAll(isPro: ref.read(isProProvider));
    if (context.mounted) Navigator.of(context).pop();
  }
}

// ============================================================================
// _Body
// ============================================================================
class _Body extends ConsumerWidget {
  const _Body({required this.course, required this.doses});

  final PreventionCourseEntity course;
  final List<PreventionDoseEntity> doses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String localeTag = Localizations.localeOf(context).toLanguageTag();

    // コース範囲内 / コース外 (再 materialize で取り残された実績) に分ける
    final List<PreventionDoseEntity> inRange = <PreventionDoseEntity>[];
    final List<PreventionDoseEntity> orphans = <PreventionDoseEntity>[];
    for (final PreventionDoseEntity d in doses) {
      if (PreventionCoursesRepository.isOrphanDose(course, d)) {
        orphans.add(d);
      } else {
        inRange.add(d);
      }
    }

    final int done = inRange
        .where((PreventionDoseEntity d) => d.administeredAt != null)
        .length;
    final PreventionDoseEntity? next = _nextDose(inRange);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ===== 期間・投与日 =====
        Text(
          PreventionLabels.period(
            startMonth: course.startMonth,
            endMonth: course.endMonth,
            l10n: l10n,
            localeTag: localeTag,
          ),
          style: typo.bodyMedium,
        ),
        const SizedBox(height: AppDimensions.gapTight),
        Text(
          l10n.prevention_day_value(course.dayOfMonth),
          style: typo.metaSmall.copyWith(color: colors.fgMuted),
        ),
        if (course.medicineName != null) ...<Widget>[
          const SizedBox(height: AppDimensions.gapTight),
          Text(
            course.medicineName!,
            style: typo.metaSmall.copyWith(color: colors.fgMuted),
          ),
        ],
        const SizedBox(height: AppDimensions.paddingSection),

        // ===== 検査ステータス =====
        if (course.kind != PreventionKind.flea_tick) ...<Widget>[
          _TestStatusRow(course: course),
          const SizedBox(height: AppDimensions.paddingSection),
        ],

        // ===== 進捗 =====
        PreventionProgressBar(
          done: done,
          total: inRange.length,
          trailing: next == null
              ? null
              : l10n.prevention_next_dose_label(
                  formatMonthDay(
                    DateTime.fromMillisecondsSinceEpoch(next.scheduledDate),
                    localeTag,
                  ),
                ),
        ),
        const SizedBox(height: AppDimensions.paddingSection),

        // ===== 月グリッド =====
        PreventionMonthGrid(
          doses: inRange,
          onDoseTapped: (PreventionDoseEntity d) => PreventionDoseSheet.show(
            context,
            course: course,
            dose: d,
          ),
        ),

        // ===== コース外の記録 =====
        if (orphans.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppDimensions.paddingSection),
          SectionLabel(
            l10n.prevention_orphan_section,
            padding: const EdgeInsets.only(bottom: AppDimensions.gapMedium),
          ),
          PreventionMonthGrid(
            doses: orphans,
            onDoseTapped: (PreventionDoseEntity d) => PreventionDoseSheet.show(
              context,
              course: course,
              dose: d,
            ),
          ),
        ],

        const SizedBox(height: AppDimensions.paddingSection * 1.5),
        // 医療免責は最下部に常設 (§9.1)
        const PreventionDisclaimer(PreventionDisclaimerKind.period),
      ],
    );
  }

  /// 次に投与すべき回 (未投与・未スキップで最も早いもの)
  PreventionDoseEntity? _nextDose(List<PreventionDoseEntity> list) {
    PreventionDoseEntity? best;
    for (final PreventionDoseEntity d in list) {
      if (d.administeredAt != null || d.skipped) continue;
      if (best == null || d.scheduledDate < best.scheduledDate) best = d;
    }
    return best;
  }
}

// ============================================================================
// _TestStatusRow - シーズン前検査
// ============================================================================
class _TestStatusRow extends ConsumerWidget {
  const _TestStatusRow({required this.course});

  final PreventionCourseEntity course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String localeTag = Localizations.localeOf(context).toLanguageTag();
    final bool canEdit = ref.watch(canEditProvider);
    final int? testedAt = course.testedAt;

    // build 73: 状態と操作を同じ行に並べていたため、
    // 「未実施」(状態) と「検査済み」(ボタン) が並んで矛盾して見えた。
    // 状態を上、操作を下の行に分け、ボタンは枠付きにして
    // 押せるものだと分かる形にする。
    return Container(
      padding: const EdgeInsets.all(AppDimensions.paddingCompact),
      decoration: BoxDecoration(border: Border.all(color: colors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ===== 状態 =====
          Text(
            l10n.prevention_test_section,
            style: typo.metaSmall.copyWith(color: colors.fgMuted),
          ),
          const SizedBox(height: AppDimensions.gapTight),
          Text(
            testedAt == null
                ? l10n.prevention_test_status_pending
                : l10n.prevention_test_status_done(
                    formatMonthDay(
                      DateTime.fromMillisecondsSinceEpoch(testedAt),
                      localeTag,
                    ),
                  ),
            style: typo.bodyMedium,
          ),

          // ===== 操作 =====
          if (canEdit && testedAt == null) ...<Widget>[
            const SizedBox(height: AppDimensions.gapMedium),
            OutlinedActionButton(
              label: l10n.prevention_test_record_action,
              onPressed: () => _markTested(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _markTested(BuildContext context, WidgetRef ref) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    await ref
        .read(preventionCoursesRepositoryProvider)
        .setTestedAt(course.id, picked.millisecondsSinceEpoch);
    if (!context.mounted) return;
    // 検査リマインドを止めるため通知を積み直す
    await ref
        .read(notificationCoordinatorProvider)
        .rescheduleAll(isPro: ref.read(isProProvider));
  }
}
