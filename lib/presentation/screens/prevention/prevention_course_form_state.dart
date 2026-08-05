// ============================================================================
// petlo - Prevention Course Form State
// ============================================================================
//
// 予防コース作成 / 編集フォームの状態 (build 72)。
//
// 入力の順序は §8.3 で固定されている:
//   ペット → 種別 → 地域 (期間が自動入力される) → 投与日・通知時刻 →
//   薬剤情報 → シーズン前検査 → 保存
//
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';

@immutable
class PreventionCourseFormErrors {
  const PreventionCourseFormErrors({
    this.petId,
    this.dayOfMonth,
    this.testedAt,
  });

  final String? petId;
  final String? dayOfMonth;
  final String? testedAt;

  bool get hasAny => petId != null || dayOfMonth != null || testedAt != null;
}

@immutable
class PreventionCourseFormState {
  const PreventionCourseFormState({
    this.editingCourseId,
    this.petId,
    this.kind = PreventionKind.filaria,
    this.year = 0,
    this.region = PreventionRegion.kanto,
    this.startMonth = 5,
    this.endMonth = 12,
    this.dayOfMonth = 1,
    this.notifyTime = const TimeOfDay(hour: 9, minute: 0),
    this.medicineName = '',
    this.dosage = '',
    this.form = PreventionForm.chewable,
    this.testedAt,
    this.testReminderEnabled = true,
    this.notificationEnabled = true,
    this.notes = '',
    this.hasRecordedDoses = false,
    this.isSubmitting = false,
    this.errors = const PreventionCourseFormErrors(),
  });

  final int? editingCourseId;
  final int? petId;
  final PreventionKind kind;

  /// 対象年。0 は「未確定」を意味し、保存時に解決する。
  final int year;

  final PreventionRegion region;
  final int startMonth;
  final int endMonth;
  final int dayOfMonth;
  final TimeOfDay notifyTime;
  final String medicineName;
  final String dosage;
  final PreventionForm form;

  /// シーズン前検査の実施日。null = 未実施
  final DateTime? testedAt;
  final bool testReminderEnabled;
  final bool notificationEnabled;
  final String notes;

  /// 投与済み / スキップ済みの dose が 1 件以上あるか (build 73 §8.4)。
  /// 年フィールドのロック判定に使う。
  final bool hasRecordedDoses;

  final bool isSubmitting;
  final PreventionCourseFormErrors errors;

  bool get isEditing => editingCourseId != null;

  /// 年フィールドを出すか。**編集モードのみ** (§8.4)。
  /// 作成フローにステップを追加しない (§8.3 の順序は不変)。
  bool get showsYearField => isEditing;

  /// 年を変更できるか。実績があるコースはロックする。
  ///
  /// 年を変えると全 dose の scheduledDate が動く。ここで §4.3 のルール (c)
  /// 「投与済み dose は削除しない」が働くと、実績が軒並み「コース外の記録」に
  /// 退避され、ユーザーからは記録が消えたように見える。曖昧な状態を作らない。
  bool get canEditYear => showsYearField && !hasRecordedDoses;

  /// 年の選択範囲 (現在年 −5 〜 +1)
  static int get minSelectableYear => DateTime.now().year - 5;
  static int get maxSelectableYear => DateTime.now().year + 1;

  /// シーズン前検査のセクションを出すか。
  /// ノミダニ単独は検査の対象外なので出さない。
  bool get showsTestSection => kind != PreventionKind.flea_tick;

  /// 注射 (年 1 回) は「毎月の投与日」ではなく 1 回きりなので、
  /// 期間の終了月を UI から隠す。
  bool get isSingleDose => form == PreventionForm.injection;

  /// "HH:mm" 形式の通知時刻
  String get notifyTimeText =>
      '${notifyTime.hour.toString().padLeft(2, '0')}:'
      '${notifyTime.minute.toString().padLeft(2, '0')}';

  /// 保存時に使う対象年。
  /// 未確定 (0) のときは「シーズンが今年のうちに終わっているなら翌年」を採る。
  /// 例: 12 月に 5〜10 月のコースを作ったら 2027 年のコースとして扱う。
  int get resolvedYear {
    if (year != 0) return year;
    final DateTime now = DateTime.now();
    if (endMonth >= startMonth && endMonth < now.month) {
      return now.year + 1;
    }
    return now.year;
  }

  PreventionCourseFormState validate(AppLocalizations l10n) {
    return copyWith(
      errors: PreventionCourseFormErrors(
        petId: petId == null ? l10n.common_input_invalid : null,
        dayOfMonth: (dayOfMonth < 1 || dayOfMonth > 31)
            ? l10n.common_input_invalid
            : null,
        testedAt: (testedAt != null &&
                testedAt!.isAfter(DateTime.now().add(const Duration(days: 1))))
            ? l10n.common_input_invalid
            : null,
      ),
    );
  }

  PreventionCourseFormState copyWith({
    Object? editingCourseId = _sentinel,
    Object? petId = _sentinel,
    PreventionKind? kind,
    int? year,
    PreventionRegion? region,
    int? startMonth,
    int? endMonth,
    int? dayOfMonth,
    TimeOfDay? notifyTime,
    String? medicineName,
    String? dosage,
    PreventionForm? form,
    Object? testedAt = _sentinel,
    bool? testReminderEnabled,
    bool? notificationEnabled,
    String? notes,
    bool? hasRecordedDoses,
    bool? isSubmitting,
    PreventionCourseFormErrors? errors,
  }) {
    return PreventionCourseFormState(
      editingCourseId: editingCourseId == _sentinel
          ? this.editingCourseId
          : editingCourseId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      kind: kind ?? this.kind,
      year: year ?? this.year,
      region: region ?? this.region,
      startMonth: startMonth ?? this.startMonth,
      endMonth: endMonth ?? this.endMonth,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      notifyTime: notifyTime ?? this.notifyTime,
      medicineName: medicineName ?? this.medicineName,
      dosage: dosage ?? this.dosage,
      form: form ?? this.form,
      testedAt: testedAt == _sentinel ? this.testedAt : testedAt as DateTime?,
      testReminderEnabled: testReminderEnabled ?? this.testReminderEnabled,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
      notes: notes ?? this.notes,
      hasRecordedDoses: hasRecordedDoses ?? this.hasRecordedDoses,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errors: errors ?? this.errors,
    );
  }

  static const Object _sentinel = Object();
}
