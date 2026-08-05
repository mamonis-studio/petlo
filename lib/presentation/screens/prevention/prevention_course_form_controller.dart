// ============================================================================
// petlo - Prevention Course Form Controller
// ============================================================================
//
// 予防コースの作成 / 編集 (build 72)。
//
// 保存後の dose materialize は repository が担う。
// 通知の積み直しは画面側が PreventionNotificationScheduler を呼ぶ。
//
// ============================================================================

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/prevention/prevention_region_presets.dart';
import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/prevention_providers.dart';
import '../../providers/pro_status_provider.dart';
import '../../providers/scope_providers.dart';
import 'prevention_course_form_state.dart';

enum PreventionCourseSaveOutcome {
  success,
  validationFailed,
  dbError,
  proLimitReached,
}

final NotifierProviderFamily<PreventionCourseFormController,
        PreventionCourseFormState, int?> preventionCourseFormControllerProvider =
    NotifierProviderFamily<PreventionCourseFormController,
        PreventionCourseFormState, int?>(
  PreventionCourseFormController.new,
);

class PreventionCourseFormController
    extends FamilyNotifier<PreventionCourseFormState, int?> {
  @override
  PreventionCourseFormState build(int? editingCourseId) {
    if (editingCourseId == null) {
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId = (petIdStr == null || petIdStr == kAllPetsId)
          ? null
          : int.tryParse(petIdStr);
      final PreventionPeriod period = PreventionRegionPresets.periodFor(
        kind: PreventionKind.filaria,
        region: PreventionRegion.kanto,
      );
      return PreventionCourseFormState(
        petId: petId,
        startMonth: period.startMonth,
        endMonth: period.endMonth,
      );
    }
    Future<void>.microtask(() => _loadExisting(editingCourseId));
    return const PreventionCourseFormState();
  }

  Future<void> _loadExisting(int courseId) async {
    try {
      final PreventionCourseEntity? c = await ref
          .read(preventionCoursesRepositoryProvider)
          .getById(courseId);
      if (c == null) return;

      // §8.4: 投与済み / スキップ済みが 1 件でもあれば年をロックする。
      final List<PreventionDoseEntity> doses =
          await ref.read(preventionDosesRepositoryProvider).getForCourse(c.id);
      final bool hasRecorded = doses.any((PreventionDoseEntity d) =>
          d.administeredAt != null || d.skipped);

      final List<String> hhmm = c.notifyTime.split(':');
      state = PreventionCourseFormState(
        editingCourseId: c.id,
        petId: c.petId,
        kind: c.kind,
        year: c.year,
        region: c.region,
        startMonth: c.startMonth,
        endMonth: c.endMonth,
        dayOfMonth: c.dayOfMonth,
        notifyTime: TimeOfDay(
          hour: int.tryParse(hhmm.first) ?? 9,
          minute: hhmm.length > 1 ? (int.tryParse(hhmm[1]) ?? 0) : 0,
        ),
        medicineName: c.medicineName ?? '',
        dosage: c.dosage ?? '',
        form: c.form,
        testedAt: c.testedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(c.testedAt!),
        testReminderEnabled: c.testReminderEnabled,
        notificationEnabled: c.notificationEnabled,
        notes: c.notes ?? '',
        hasRecordedDoses: hasRecorded,
      );
    } catch (e, st) {
      PetloLogger.instance.w('Failed to load prevention course for editing',
          error: e, stackTrace: st);
    }
  }

  // ==========================================================================
  // フィールド更新
  // ==========================================================================

  void updatePetId(int? v) => state = state.copyWith(petId: v);

  /// 対象年を変更する (§8.4)。編集モードかつ実績 0 件のときだけ通す。
  /// 保存時に再 materialize が走るが、実績が無いので §4.3 のケース (c) は
  /// 発生せず、全 dose が単純に UPDATE される。
  void updateYear(int v) {
    if (!state.canEditYear) return;
    if (v < PreventionCourseFormState.minSelectableYear ||
        v > PreventionCourseFormState.maxSelectableYear) {
      return;
    }
    state = state.copyWith(year: v);
  }

  /// 種別を変えると、その種別の地域プリセットで期間を引き直す。
  void updateKind(PreventionKind v) {
    final PreventionPeriod period = PreventionRegionPresets.periodFor(
      kind: v,
      region: state.region,
    );
    state = state.copyWith(
      kind: v,
      startMonth: period.startMonth,
      endMonth: period.endMonth,
      // ノミダニ単独は検査対象外なのでリマインドを落とす
      testReminderEnabled:
          v == PreventionKind.flea_tick ? false : state.testReminderEnabled,
    );
  }

  /// 地域を選ぶと開始月・終了月が自動入力される (§8.3 step 3)。
  /// これは医学的な指示ではなく目安。UI には必ず免責文を併記する。
  void updateRegion(PreventionRegion v) {
    final PreventionPeriod period = PreventionRegionPresets.periodFor(
      kind: state.kind,
      region: v,
    );
    state = state.copyWith(
      region: v,
      startMonth: period.startMonth,
      endMonth: period.endMonth,
    );
  }

  /// 月を手で動かしたら地域プリセットからは外れたものとして custom に落とす。
  void updateStartMonth(int v) {
    if (v < 1 || v > 12) return;
    state = state.copyWith(startMonth: v, region: PreventionRegion.custom);
  }

  void updateEndMonth(int v) {
    if (v < 1 || v > 12) return;
    state = state.copyWith(endMonth: v, region: PreventionRegion.custom);
  }

  void updateDayOfMonth(int v) {
    if (v < 1 || v > 31) return;
    state = state.copyWith(dayOfMonth: v);
  }

  void updateNotifyTime(TimeOfDay v) => state = state.copyWith(notifyTime: v);
  void updateMedicineName(String v) => state = state.copyWith(medicineName: v);
  void updateDosage(String v) => state = state.copyWith(dosage: v);
  void updateForm(PreventionForm v) => state = state.copyWith(form: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);
  void updateNotificationEnabled(bool v) =>
      state = state.copyWith(notificationEnabled: v);

  /// 検査済みにする / 未実施に戻す。
  /// 検査済みにしたらリマインドは不要なので落とす。
  void updateTestedAt(DateTime? v) {
    state = state.copyWith(
      testedAt: v,
      testReminderEnabled: v != null ? false : state.testReminderEnabled,
    );
  }

  void updateTestReminderEnabled(bool v) =>
      state = state.copyWith(testReminderEnabled: v);

  // ==========================================================================
  // Save
  // ==========================================================================

  Future<PreventionCourseSaveOutcome> save(AppLocalizations l10n) async {
    final PreventionCourseFormState validated = state.validate(l10n);
    if (validated.errors.hasAny) {
      state = validated;
      return PreventionCourseSaveOutcome.validationFailed;
    }

    // 無料枠: created_at 昇順で先着 freeMaxPreventionCourses 件まで (§7)。
    // year 基準にすると「年を変えれば何個でも作れる」抜け道が生まれる。
    if (!state.isEditing && !ref.read(isProProvider)) {
      try {
        final int count = await ref
            .read(preventionCoursesRepositoryProvider)
            .countActive();
        if (count >= AppConstants.freeMaxPreventionCourses) {
          return PreventionCourseSaveOutcome.proLimitReached;
        }
      } catch (e, st) {
        PetloLogger.instance.w('prevention course count check failed',
            error: e, stackTrace: st);
      }
    }

    state = validated.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(preventionCoursesRepositoryProvider);
      final int? testedAtMsec = state.testedAt?.millisecondsSinceEpoch;

      if (state.isEditing) {
        await repo.update(
          courseId: state.editingCourseId!,
          kind: state.kind,
          year: state.resolvedYear,
          startMonth: state.startMonth,
          endMonth: state.endMonth,
          dayOfMonth: state.dayOfMonth,
          notifyTime: state.notifyTimeText,
          medicineName: state.medicineName,
          dosage: state.dosage,
          form: state.form,
          region: state.region,
          testedAtMsec: testedAtMsec,
          clearTestedAt: testedAtMsec == null,
          testReminderEnabled: state.testReminderEnabled,
          notificationEnabled: state.notificationEnabled,
          notes: state.notes,
        );
      } else {
        await repo.create(
          groupId: ref.read(currentGroupIdProvider),
          petId: state.petId!,
          kind: state.kind,
          year: state.resolvedYear,
          startMonth: state.startMonth,
          endMonth: state.endMonth,
          dayOfMonth: state.dayOfMonth,
          notifyTime: state.notifyTimeText,
          medicineName: state.medicineName,
          dosage: state.dosage,
          form: state.form,
          region: state.region,
          testedAtMsec: testedAtMsec,
          testReminderEnabled: state.testReminderEnabled,
          notificationEnabled: state.notificationEnabled,
          notes: state.notes,
        );
      }

      state = state.copyWith(isSubmitting: false);
      return PreventionCourseSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to save prevention course', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return PreventionCourseSaveOutcome.dbError;
    }
  }
}
