// ============================================================================
// petlo - Prevention Doses Repository
// ============================================================================
//
// 予防コースの 1 回分 (build 72) の読み書き。
//
// 投与記録は単一トランザクションで
//   medications へ INSERT → dose.medicationId / administeredAt を UPDATE
// を行う。これで予防の実績が既存の投薬履歴と同じ器に載る。
//
// 取り消しは逆向きに、medications 行を論理削除して dose を未投与へ戻す。
//
// 通知は扱わない。呼び出し側 (provider / 画面) が
// PreventionNotificationScheduler を叩く。
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class PreventionDosesRepository extends BaseRepository {
  PreventionDosesRepository(super.db);

  // ==========================================================================
  // 導出ロジック
  // ==========================================================================

  /// dose の表示状態を導出する。DB には保存しない。
  /// [nowMsec] を渡すとテストから時刻を固定できる。
  static PreventionDoseStatus statusOf(
    PreventionDoseEntity dose, {
    int? nowMsec,
  }) {
    if (dose.skipped) return PreventionDoseStatus.skipped;
    if (dose.administeredAt != null) {
      return PreventionDoseStatus.administered;
    }
    final DateTime now = nowMsec == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(nowMsec);
    final DateTime scheduled =
        DateTime.fromMillisecondsSinceEpoch(dose.scheduledDate);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day =
        DateTime(scheduled.year, scheduled.month, scheduled.day);
    if (day.isAtSameMomentAs(today)) return PreventionDoseStatus.due;
    if (day.isBefore(today)) return PreventionDoseStatus.overdue;
    return PreventionDoseStatus.upcoming;
  }

  // ==========================================================================
  // Read
  // ==========================================================================

  /// コース配下の dose (seq 昇順)
  Stream<List<PreventionDoseEntity>> watchForCourse(int courseId) {
    return (db.select(db.preventionDoses)
          ..where((PreventionDoses t) =>
              t.courseId.equals(courseId) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<PreventionDoses>>[
            (PreventionDoses t) => OrderingTerm(expression: t.seq),
          ]))
        .watch();
  }

  Future<List<PreventionDoseEntity>> getForCourse(int courseId) {
    return (db.select(db.preventionDoses)
          ..where((PreventionDoses t) =>
              t.courseId.equals(courseId) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<PreventionDoses>>[
            (PreventionDoses t) => OrderingTerm(expression: t.seq),
          ]))
        .get();
  }

  Future<PreventionDoseEntity?> getById(int id) {
    return (db.select(db.preventionDoses)
          ..where((PreventionDoses t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  // build 73: getUpcomingUnrecorded() を削除した。
  // v2 §5.4 で「1 コースあたり直近 2 件」の固定キャップを廃止した以上、
  // limit 付きの取得口を残しておくと同じキャップを容易に再導入できてしまう。
  // 配分は PreventionSlotPlanner が全 dose を見た上で決める。
  // 再び必要になったら書き直すこと。

  // ==========================================================================
  // Write
  // ==========================================================================

  /// 投与を記録する。
  ///
  /// 単一トランザクションで:
  ///   1. medications へ INSERT (reminderId は必ず null。schedules 系の参照なので
  ///      予防 dose の id を入れてはならない)
  ///   2. 1 の id を dose.medicationId へ
  ///   3. dose.administeredAt を更新 (skipped は解除)
  ///
  /// [medicineNameFallback] はコースに薬剤名が無いときに使う表示名。
  /// l10n を持たないレイヤなので、呼び出し側 (UI) が種別のローカライズ名を渡す。
  Future<bool> recordAdministration({
    required int doseId,
    required int administeredAtMsec,
    String? medicineNameFallback,
    String? notes,
  }) async {
    final PreventionDoseEntity? dose = await getById(doseId);
    if (dose == null || dose.deletedAt != null) return false;

    final PreventionCourseEntity? course = await (db
          .select(db.preventionCourses)
        ..where((PreventionCourses t) => t.id.equals(dose.courseId))
        ..limit(1))
        .getSingleOrNull();
    if (course == null) {
      throw StateError('PreventionCourse not found: id=${dose.courseId}');
    }

    // medications は新規行なので create、dose は既存行なので update の
    // メタを使い分ける (v2 §6.3 #1)。
    // medications には読み手がまだ居ないため、ここが崩れても誰も痛みを
    // 感じない。読み手が生える前に BaseRepository 経由で揃えておく。
    final meta = buildCreateMetadata(groupId: course.groupId);
    final doseMeta = buildUpdateMetadata(groupId: course.groupId);
    final String medicineName = _firstNonEmpty(<String?>[
          course.medicineName,
          medicineNameFallback,
        ]) ??
        course.kind.name;

    int medicationId = 0;
    int affected = 0;

    await db.transaction(() async {
      medicationId = await db.into(db.medications).insert(
            MedicationsCompanion.insert(
              groupId: Value(course.groupId),
              petId: course.petId,
              // 予防 dose を reminderId に入れてはならない (§6.3 #5)
              reminderId: const Value<int?>(null),
              medicineName: medicineName,
              dosage: Value(course.dosage),
              administeredAt: administeredAtMsec,
              notes: Value(_emptyToNull(notes) ?? dose.notes),
              createdBy: Value(course.createdBy),
              syncStatus: Value(meta.initialSyncStatus),
              createdAt: meta.createdAt,
              updatedAt: meta.updatedAt,
              lastModifiedAtClient: Value(meta.lastModifiedAtClient),
            ),
          );

      affected = await (db.update(db.preventionDoses)
            ..where((PreventionDoses t) => t.id.equals(doseId)))
          .write(PreventionDosesCompanion(
        administeredAt: Value<int?>(administeredAtMsec),
        medicationId: Value<int?>(medicationId),
        skipped: const Value(false),
        notes: notes == null
            ? const Value.absent()
            : Value<String?>(_emptyToNull(notes)),
        syncStatus: Value(doseMeta.updatedSyncStatus),
        updatedAt: Value(doseMeta.updatedAt),
        lastModifiedAtClient: Value(doseMeta.lastModifiedAtClient),
      ));
    });

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: course.groupId,
        operation: SyncOperation.insert,
        targetTable: 'medications',
        recordId: medicationId,
        payloadJson: jsonEncode(<String, dynamic>{
          'petId': course.petId,
          'medicineName': medicineName,
          'administeredAt': administeredAtMsec,
        }),
      );
      await enqueueSyncIfShared(
        groupId: course.groupId,
        operation: SyncOperation.update,
        targetTable: 'prevention_doses',
        recordId: doseId,
        payloadJson: jsonEncode(<String, dynamic>{
          'administeredAt': administeredAtMsec,
          'medicationId': medicationId,
        }),
      );
    }
    return affected > 0;
  }

  /// 投与記録を取り消す。紐づく medications 行を論理削除して未投与へ戻す。
  Future<bool> undoAdministration(int doseId) async {
    final PreventionDoseEntity? dose = await getById(doseId);
    if (dose == null || dose.deletedAt != null) return false;
    if (dose.administeredAt == null && dose.medicationId == null) {
      return false;
    }

    // medications は論理削除、dose は更新なのでメタを使い分ける (v2 §6.3 #3)。
    final delMeta = buildDeleteMetadata(groupId: dose.groupId);
    final doseMeta = buildUpdateMetadata(groupId: dose.groupId);
    final int? medicationId = dose.medicationId;
    int affected = 0;

    await db.transaction(() async {
      if (medicationId != null) {
        await (db.update(db.medications)
              ..where((Medications t) => t.id.equals(medicationId)))
            .write(MedicationsCompanion(
          deletedAt: Value(delMeta.deletedAt),
          syncStatus: Value(delMeta.updatedSyncStatus),
          updatedAt: Value(delMeta.updatedAt),
          lastModifiedAtClient: Value(delMeta.lastModifiedAtClient),
        ));
      }

      affected = await (db.update(db.preventionDoses)
            ..where((PreventionDoses t) => t.id.equals(doseId)))
          .write(PreventionDosesCompanion(
        administeredAt: const Value<int?>(null),
        medicationId: const Value<int?>(null),
        syncStatus: Value(doseMeta.updatedSyncStatus),
        updatedAt: Value(doseMeta.updatedAt),
        lastModifiedAtClient: Value(doseMeta.lastModifiedAtClient),
      ));
    });

    if (affected > 0) {
      if (medicationId != null) {
        await enqueueSyncIfShared(
          groupId: dose.groupId,
          operation: SyncOperation.delete,
          targetTable: 'medications',
          recordId: medicationId,
          payloadJson: '{}',
        );
      }
      await enqueueSyncIfShared(
        groupId: dose.groupId,
        operation: SyncOperation.update,
        targetTable: 'prevention_doses',
        recordId: doseId,
        payloadJson: jsonEncode(<String, dynamic>{'administeredAt': null}),
      );
    }
    return affected > 0;
  }

  /// この回をスキップする / スキップを解除する。
  /// 投与済みの回をスキップする場合は先に記録を取り消す。
  Future<bool> setSkipped(int doseId, bool skipped) async {
    final PreventionDoseEntity? dose = await getById(doseId);
    if (dose == null || dose.deletedAt != null) return false;

    if (skipped && dose.administeredAt != null) {
      await undoAdministration(doseId);
    }

    final meta = buildUpdateMetadata(groupId: dose.groupId);
    final int affected = await (db.update(db.preventionDoses)
          ..where((PreventionDoses t) => t.id.equals(doseId)))
        .write(PreventionDosesCompanion(
      skipped: Value(skipped),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: dose.groupId,
        operation: SyncOperation.update,
        targetTable: 'prevention_doses',
        recordId: doseId,
        payloadJson: jsonEncode(<String, dynamic>{'skipped': skipped}),
      );
    }
    return affected > 0;
  }

  /// dose のメモだけを更新する。
  Future<bool> updateNotes(int doseId, String? notes) async {
    final PreventionDoseEntity? dose = await getById(doseId);
    if (dose == null || dose.deletedAt != null) return false;

    final meta = buildUpdateMetadata(groupId: dose.groupId);
    final int affected = await (db.update(db.preventionDoses)
          ..where((PreventionDoses t) => t.id.equals(doseId)))
        .write(PreventionDosesCompanion(
      notes: Value<String?>(_emptyToNull(notes)),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: dose.groupId,
        operation: SyncOperation.update,
        targetTable: 'prevention_doses',
        recordId: doseId,
        payloadJson: '{}',
      );
    }
    return affected > 0;
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final String? c in candidates) {
      final String? v = _emptyToNull(c);
      if (v != null) return v;
    }
    return null;
  }

  static String? _emptyToNull(String? s) {
    if (s == null) return null;
    final String trimmed = s.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
