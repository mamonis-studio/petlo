// ============================================================================
// petlo - Prevention Courses Repository
// ============================================================================
//
// 予防コース (build 72) の CRUD と dose の materialize。
//
// 設計の芯:
//   - コース設定 (期間・投与日・剤型) を変更したら dose を再 materialize する。
//   - 再 materialize では **投与済み / スキップ済みの dose を絶対に消さない**。
//     コース範囲外に出た実績は seq を末尾へ退避して残す (= orphan)。
//     UI では isOrphanDose() で判定し「コース外の記録」として別枠表示する。
//
// 通知は扱わない。呼び出し側 (provider / 画面) が
// PreventionNotificationScheduler を叩く。既存の schedules と同じ分担。
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

/// materialize 計画上の 1 回分 (年, 月)
typedef PreventionPlannedMonth = ({int year, int month});

class PreventionCoursesRepository extends BaseRepository {
  PreventionCoursesRepository(super.db);

  // ==========================================================================
  // 計画ロジック (純粋関数。テストしやすいよう static)
  // ==========================================================================

  /// 指定年月に dayOfMonth が存在しなければ月末日に丸める。
  /// 例: 2026年2月 + dayOfMonth=31 → 2026-02-28
  static int clampDay(int year, int month, int dayOfMonth) {
    final int lastDay = DateTime(year, month + 1, 0).day;
    return dayOfMonth > lastDay ? lastDay : dayOfMonth;
  }

  /// 予定日 (ローカル 00:00) を UTC msec で返す。
  static int scheduledDateFor(int year, int month, int dayOfMonth) {
    return DateTime(year, month, clampDay(year, month, dayOfMonth))
        .millisecondsSinceEpoch;
  }

  /// コース設定から「あるべき dose の (年, 月)」を seq 順で算出する。
  ///
  /// - form == injection: 1 件のみ (year / startMonth)
  /// - endMonth >= startMonth: 同年内 startMonth..endMonth
  /// - endMonth <  startMonth: 越年。year の startMonth..12 + (year+1) の 1..endMonth
  static List<PreventionPlannedMonth> plannedMonths({
    required int year,
    required int startMonth,
    required int endMonth,
    required PreventionForm form,
  }) {
    if (form == PreventionForm.injection) {
      return <PreventionPlannedMonth>[(year: year, month: startMonth)];
    }
    final List<PreventionPlannedMonth> out = <PreventionPlannedMonth>[];
    if (endMonth >= startMonth) {
      for (int m = startMonth; m <= endMonth; m++) {
        out.add((year: year, month: m));
      }
    } else {
      for (int m = startMonth; m <= 12; m++) {
        out.add((year: year, month: m));
      }
      for (int m = 1; m <= endMonth; m++) {
        out.add((year: year + 1, month: m));
      }
    }
    return out;
  }

  /// コースの計画月一覧 (エンティティ版)
  static List<PreventionPlannedMonth> plannedMonthsOf(
    PreventionCourseEntity course,
  ) {
    return plannedMonths(
      year: course.year,
      startMonth: course.startMonth,
      endMonth: course.endMonth,
      form: course.form,
    );
  }

  /// dose がコースの現行範囲から外れているか (= コース外の記録)。
  /// 再 materialize で実績が範囲外に取り残されたケースを UI で別枠表示する。
  static bool isOrphanDose(
    PreventionCourseEntity course,
    PreventionDoseEntity dose,
  ) {
    final DateTime d =
        DateTime.fromMillisecondsSinceEpoch(dose.scheduledDate);
    return !plannedMonthsOf(course).any(
      (PreventionPlannedMonth p) => p.year == d.year && p.month == d.month,
    );
  }

  // ==========================================================================
  // Read
  // ==========================================================================

  /// ペットの予防コース (年の新しい順 → 種別順)
  Stream<List<PreventionCourseEntity>> watchForPet(int petId) {
    return (db.select(db.preventionCourses)
          ..where((PreventionCourses t) =>
              t.petId.equals(petId) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<PreventionCourses>>[
            (PreventionCourses t) =>
                OrderingTerm(expression: t.year, mode: OrderingMode.desc),
            (PreventionCourses t) => OrderingTerm(expression: t.kind),
          ]))
        .watch();
  }

  /// グループの予防コース全件
  Stream<List<PreventionCourseEntity>> watchForGroup(String groupId) {
    return (db.select(db.preventionCourses)
          ..where((PreventionCourses t) =>
              t.groupId.equals(groupId) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<PreventionCourses>>[
            (PreventionCourses t) =>
                OrderingTerm(expression: t.year, mode: OrderingMode.desc),
            (PreventionCourses t) => OrderingTerm(expression: t.kind),
          ]))
        .watch();
  }

  Future<PreventionCourseEntity?> getById(int id) {
    return (db.select(db.preventionCourses)
          ..where((PreventionCourses t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 生存している全コース (created_at 昇順)。
  /// 無料枠判定 (先着 1 件) と通知の再スケジュールで使う。
  Future<List<PreventionCourseEntity>> getAllActiveByCreation() {
    return (db.select(db.preventionCourses)
          ..where((PreventionCourses t) => t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<PreventionCourses>>[
            (PreventionCourses t) => OrderingTerm(expression: t.createdAt),
            (PreventionCourses t) => OrderingTerm(expression: t.id),
          ]))
        .get();
  }

  /// 生存コース数 (無料枠のカウント用)
  Future<int> countActive() async {
    final List<PreventionCourseEntity> all = await getAllActiveByCreation();
    return all.length;
  }

  // ==========================================================================
  // Write
  // ==========================================================================

  Future<int> create({
    required String groupId,
    required int petId,
    required PreventionKind kind,
    required int year,
    required int startMonth,
    required int endMonth,
    required int dayOfMonth,
    String notifyTime = '09:00',
    String? medicineName,
    String? dosage,
    PreventionForm form = PreventionForm.chewable,
    PreventionRegion region = PreventionRegion.custom,
    int? testedAtMsec,
    bool? testReminderEnabled,
    bool notificationEnabled = true,
    String? notes,
    String? createdBy,
  }) async {
    _validate(
      startMonth: startMonth,
      endMonth: endMonth,
      dayOfMonth: dayOfMonth,
      notifyTime: notifyTime,
    );

    final meta = buildCreateMetadata(groupId: groupId);
    // フィラリア系はシーズン前検査のリマインドを既定 ON、ノミダニは OFF。
    final bool testReminder = testReminderEnabled ??
        (kind != PreventionKind.flea_tick && testedAtMsec == null);

    late int newId;
    await db.transaction(() async {
      newId = await db.into(db.preventionCourses).insert(
            PreventionCoursesCompanion.insert(
              groupId: Value(groupId),
              petId: petId,
              kind: kind,
              year: year,
              startMonth: startMonth,
              endMonth: endMonth,
              dayOfMonth: dayOfMonth,
              notifyTime: Value(notifyTime),
              medicineName: Value(_emptyToNull(medicineName)),
              dosage: Value(_emptyToNull(dosage)),
              form: Value(form),
              region: Value(region),
              testedAt: Value(testedAtMsec),
              testReminderEnabled: Value(testReminder),
              notificationEnabled: Value(notificationEnabled),
              notes: Value(_emptyToNull(notes)),
              createdBy: Value(createdBy),
              syncStatus: Value(meta.initialSyncStatus),
              createdAt: meta.createdAt,
              updatedAt: meta.updatedAt,
              lastModifiedAtClient: Value(meta.lastModifiedAtClient),
            ),
          );

      final PreventionCourseEntity? saved = await (db
            .select(db.preventionCourses)
          ..where((PreventionCourses t) => t.id.equals(newId)))
          .getSingleOrNull();
      if (saved != null) {
        await _materializeDoses(saved);
      }
    });

    await enqueueSyncIfShared(
      groupId: groupId,
      operation: SyncOperation.insert,
      targetTable: 'prevention_courses',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'petId': petId,
        'kind': kind.name,
        'year': year,
        'startMonth': startMonth,
        'endMonth': endMonth,
        'dayOfMonth': dayOfMonth,
      }),
    );
    await _enqueueDosesSync(groupId: groupId, courseId: newId);
    return newId;
  }

  /// コース設定を更新し、dose を再 materialize する。
  /// 投与済み / スキップ済みの dose は範囲外になっても削除しない。
  Future<bool> update({
    required int courseId,
    PreventionKind? kind,
    int? year,
    int? startMonth,
    int? endMonth,
    int? dayOfMonth,
    String? notifyTime,
    String? medicineName,
    String? dosage,
    PreventionForm? form,
    PreventionRegion? region,
    int? testedAtMsec,
    bool clearTestedAt = false,
    bool? testReminderEnabled,
    bool? notificationEnabled,
    String? notes,
  }) async {
    final PreventionCourseEntity? existing = await getById(courseId);
    if (existing == null) {
      throw StateError('PreventionCourse not found: id=$courseId');
    }

    _validate(
      startMonth: startMonth ?? existing.startMonth,
      endMonth: endMonth ?? existing.endMonth,
      dayOfMonth: dayOfMonth ?? existing.dayOfMonth,
      notifyTime: notifyTime ?? existing.notifyTime,
    );

    final meta = buildUpdateMetadata(groupId: existing.groupId);
    int affected = 0;

    await db.transaction(() async {
      affected = await (db.update(db.preventionCourses)
            ..where((PreventionCourses t) => t.id.equals(courseId)))
          .write(PreventionCoursesCompanion(
        kind: kind == null ? const Value.absent() : Value(kind),
        year: year == null ? const Value.absent() : Value(year),
        startMonth:
            startMonth == null ? const Value.absent() : Value(startMonth),
        endMonth: endMonth == null ? const Value.absent() : Value(endMonth),
        dayOfMonth:
            dayOfMonth == null ? const Value.absent() : Value(dayOfMonth),
        notifyTime:
            notifyTime == null ? const Value.absent() : Value(notifyTime),
        medicineName: medicineName == null
            ? const Value.absent()
            : Value(_emptyToNull(medicineName)),
        dosage:
            dosage == null ? const Value.absent() : Value(_emptyToNull(dosage)),
        form: form == null ? const Value.absent() : Value(form),
        region: region == null ? const Value.absent() : Value(region),
        testedAt: clearTestedAt
            ? const Value<int?>(null)
            : (testedAtMsec == null
                ? const Value.absent()
                : Value<int?>(testedAtMsec)),
        testReminderEnabled: testReminderEnabled == null
            ? const Value.absent()
            : Value(testReminderEnabled),
        notificationEnabled: notificationEnabled == null
            ? const Value.absent()
            : Value(notificationEnabled),
        notes: notes == null ? const Value.absent() : Value(_emptyToNull(notes)),
        syncStatus: Value(meta.updatedSyncStatus),
        updatedAt: Value(meta.updatedAt),
        lastModifiedAtClient: Value(meta.lastModifiedAtClient),
      ));

      if (affected > 0) {
        final PreventionCourseEntity? saved = await (db
              .select(db.preventionCourses)
            ..where((PreventionCourses t) => t.id.equals(courseId)))
            .getSingleOrNull();
        if (saved != null) {
          await _materializeDoses(saved);
        }
      }
    });

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.update,
        targetTable: 'prevention_courses',
        recordId: courseId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
      await _enqueueDosesSync(
          groupId: existing.groupId, courseId: courseId);
    }
    return affected > 0;
  }

  /// シーズン前検査の実施日を記録 / 取り消す。
  Future<bool> setTestedAt(int courseId, int? testedAtMsec) {
    return update(
      courseId: courseId,
      testedAtMsec: testedAtMsec,
      clearTestedAt: testedAtMsec == null,
    );
  }

  /// コースを論理削除する。dose も一緒に論理削除する。
  /// (投与実績そのものは medications 側に残るので「記録は消えない」)
  Future<bool> softDelete(int courseId) async {
    final PreventionCourseEntity? existing = await getById(courseId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);
    final List<int> affectedDoseIds = <int>[];
    int affected = 0;

    await db.transaction(() async {
      final List<PreventionDoseEntity> doses = await (db
            .select(db.preventionDoses)
          ..where((PreventionDoses t) =>
              t.courseId.equals(courseId) & t.deletedAt.isNull()))
          .get();
      for (final PreventionDoseEntity d in doses) {
        affectedDoseIds.add(d.id);
      }

      await (db.update(db.preventionDoses)
            ..where((PreventionDoses t) =>
                t.courseId.equals(courseId) & t.deletedAt.isNull()))
          .write(PreventionDosesCompanion(
        deletedAt: Value(meta.deletedAt),
        syncStatus: Value(meta.updatedSyncStatus),
        updatedAt: Value(meta.updatedAt),
        lastModifiedAtClient: Value(meta.lastModifiedAtClient),
      ));

      affected = await (db.update(db.preventionCourses)
            ..where((PreventionCourses t) => t.id.equals(courseId)))
          .write(PreventionCoursesCompanion(
        deletedAt: Value(meta.deletedAt),
        syncStatus: Value(meta.updatedSyncStatus),
        updatedAt: Value(meta.updatedAt),
        lastModifiedAtClient: Value(meta.lastModifiedAtClient),
      ));
    });

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'prevention_courses',
        recordId: courseId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
      for (final int doseId in affectedDoseIds) {
        await enqueueSyncIfShared(
          groupId: existing.groupId,
          operation: SyncOperation.delete,
          targetTable: 'prevention_doses',
          recordId: doseId,
          payloadJson: '{}',
        );
      }
    }
    return affected > 0;
  }

  // ==========================================================================
  // materialize
  // ==========================================================================

  /// コースの dose を現在の設定に合わせて作り直す。
  /// **呼び出し元でトランザクションを張ること。**
  ///
  /// 手順 (§4.3):
  ///   1. 新しい設定から「あるべき dose の (年, 月) 集合」を算出
  ///   2. 既存 dose を全件取得 (論理削除済みも含む)
  ///   3a. 新集合に含まれる年月 → scheduledDate / seq / isFinal を UPDATE
  ///       (administeredAt / medicationId / notes は不変。論理削除済みなら復活)
  ///   3b. 新集合に無い かつ 未投与・未スキップ → 論理削除
  ///   3c. 新集合に無い が 投与済み or スキップ済み → 残す。seq を末尾へ退避
  ///   4. 新集合にあって既存 dose が無い年月 → INSERT
  ///
  /// build 73 (§8.4): 年をまるごとずらすと (年, 月) キーが 1 つも一致せず、
  /// 全 dose が「INSERT + 旧行の論理削除」になってしまう。実績が無いのに
  /// 行 ID が総入れ替えになるのは §13 #17 の「全 dose が単純 UPDATE される」
  /// に反するため、キー一致で埋まらなかった枠には **実績を持たない既存 dose**
  /// を通し番号順で当てるフォールバックを設けた。
  ///
  /// 段取りを 3 パスに分けているのは、フォールバックが「後続の枠がキー一致で
  /// 使うはずだった行」を先に奪わないようにするため。
  Future<void> _materializeDoses(PreventionCourseEntity course) async {
    final List<PreventionPlannedMonth> planned = plannedMonthsOf(course);

    // build 73: syncStatus / タイムスタンプを手で組まず BaseRepository に寄せる。
    // INSERT は create、既存行の書き換えは update、範囲外の除去は delete と
    // 用途ごとにメタを使い分ける。createdAt を触ってよいのは INSERT だけ。
    final createMeta = buildCreateMetadata(groupId: course.groupId);
    final updateMeta = buildUpdateMetadata(groupId: course.groupId);
    final deleteMeta = buildDeleteMetadata(groupId: course.groupId);

    final List<PreventionDoseEntity> existing = await (db
          .select(db.preventionDoses)
        ..where((PreventionDoses t2) => t2.courseId.equals(course.id))
        ..orderBy(<OrderClauseGenerator<PreventionDoses>>[
          (PreventionDoses t2) => OrderingTerm(expression: t2.seq),
          (PreventionDoses t2) => OrderingTerm(expression: t2.id),
        ]))
        .get();

    // (年, 月) → 候補 dose 群
    final Map<String, List<PreventionDoseEntity>> byMonth =
        <String, List<PreventionDoseEntity>>{};
    for (final PreventionDoseEntity d in existing) {
      final DateTime dt =
          DateTime.fromMillisecondsSinceEpoch(d.scheduledDate);
      byMonth.putIfAbsent('${dt.year}-${dt.month}', () => <PreventionDoseEntity>[])
          .add(d);
    }

    final Set<int> consumed = <int>{};
    final List<PreventionDoseEntity?> assigned =
        List<PreventionDoseEntity?>.filled(planned.length, null);

    // ---- パス 1: (年, 月) キーで一致させる ----
    // 生存 dose を優先。無ければ論理削除済みを復活させて行の増殖を防ぐ。
    for (int i = 0; i < planned.length; i++) {
      final PreventionPlannedMonth p = planned[i];
      final List<PreventionDoseEntity> candidates =
          byMonth['${p.year}-${p.month}'] ?? const <PreventionDoseEntity>[];

      PreventionDoseEntity? match;
      for (final PreventionDoseEntity c in candidates) {
        if (consumed.contains(c.id)) continue;
        if (c.deletedAt == null) {
          match = c;
          break;
        }
      }
      if (match == null) {
        for (final PreventionDoseEntity c in candidates) {
          if (consumed.contains(c.id)) continue;
          match = c;
          break;
        }
      }
      if (match != null) {
        consumed.add(match.id);
        assigned[i] = match;
      }
    }

    // ---- パス 2: 余った枠に「ユーザーの入力を持たない既存 dose」を当てる ----
    // 年をずらしたケース (§8.4) で行 ID を保つための経路。
    //
    // 流用してよいのは「ユーザーが何も置いていない空の行」だけ。
    //   - 投与済み / スキップ済み → 実績なので動かさない (§4.3)
    //   - notes あり → 未投与でもユーザーがその行に情報を置いた状態。
    //     別の月へ流用するとメモが黙って違う日付に移る。実績と同じ扱いにする。
    final List<PreventionDoseEntity> reusable = existing
        .where((PreventionDoseEntity d) =>
            !consumed.contains(d.id) && _isBlankDose(d))
        .toList()
      // 生存行を先に使う。論理削除済みは INSERT の代わりに復活させる。
      ..sort((PreventionDoseEntity a, PreventionDoseEntity b) {
        final int liveA = a.deletedAt == null ? 0 : 1;
        final int liveB = b.deletedAt == null ? 0 : 1;
        if (liveA != liveB) return liveA.compareTo(liveB);
        final int c = a.seq.compareTo(b.seq);
        return c != 0 ? c : a.id.compareTo(b.id);
      });

    int reuseIdx = 0;
    for (int i = 0; i < planned.length; i++) {
      if (assigned[i] != null) continue;
      if (reuseIdx >= reusable.length) break;
      final PreventionDoseEntity d = reusable[reuseIdx++];
      consumed.add(d.id);
      assigned[i] = d;
    }

    // ---- パス 3: 反映 (UPDATE / INSERT) ----
    for (int i = 0; i < planned.length; i++) {
      final PreventionPlannedMonth p = planned[i];
      final int seq = i + 1;
      final bool isFinal = i == planned.length - 1;
      final int scheduled =
          scheduledDateFor(p.year, p.month, course.dayOfMonth);
      final PreventionDoseEntity? match = assigned[i];

      if (match != null) {
        await (db.update(db.preventionDoses)
              ..where((PreventionDoses t2) => t2.id.equals(match.id)))
            .write(PreventionDosesCompanion(
          petId: Value(course.petId),
          groupId: Value(course.groupId),
          seq: Value(seq),
          scheduledDate: Value(scheduled),
          isFinal: Value(isFinal),
          deletedAt: const Value<int?>(null),
          syncStatus: Value(updateMeta.updatedSyncStatus),
          updatedAt: Value(updateMeta.updatedAt),
          lastModifiedAtClient: Value(updateMeta.lastModifiedAtClient),
          // createdAt は書かない。行の生成時刻は不変。
        ));
      } else {
        await db.into(db.preventionDoses).insert(
              PreventionDosesCompanion.insert(
                groupId: Value(course.groupId),
                courseId: course.id,
                petId: course.petId,
                seq: seq,
                scheduledDate: scheduled,
                isFinal: Value(isFinal),
                createdBy: Value(course.createdBy),
                syncStatus: Value(createMeta.initialSyncStatus),
                createdAt: createMeta.createdAt,
                updatedAt: createMeta.updatedAt,
                lastModifiedAtClient: Value(createMeta.lastModifiedAtClient),
              ),
            );
      }
    }

    // 計画から外れた既存 dose の後始末
    int orphanSeq = planned.length;
    for (final PreventionDoseEntity d in existing) {
      if (consumed.contains(d.id)) continue;
      if (d.deletedAt != null) continue; // 既に消えている
      // build 73: 「ユーザーが何か置いた行」は投与済みと同じ扱いで残す。
      // メモだけの行を論理削除すると、書いた本人から見えなくなる。
      // 流用を止めておきながらここで消しては意味がない。
      if (!_isBlankDose(d)) {
        // 実績あり → 絶対に消さない。seq を末尾へ退避して残す。
        orphanSeq++;
        await (db.update(db.preventionDoses)
              ..where((PreventionDoses t2) => t2.id.equals(d.id)))
            .write(PreventionDosesCompanion(
          seq: Value(orphanSeq),
          isFinal: const Value(false),
          syncStatus: Value(updateMeta.updatedSyncStatus),
          updatedAt: Value(updateMeta.updatedAt),
          lastModifiedAtClient: Value(updateMeta.lastModifiedAtClient),
        ));
      } else {
        await (db.update(db.preventionDoses)
              ..where((PreventionDoses t2) => t2.id.equals(d.id)))
            .write(PreventionDosesCompanion(
          deletedAt: Value(deleteMeta.deletedAt),
          syncStatus: Value(deleteMeta.updatedSyncStatus),
          updatedAt: Value(deleteMeta.updatedAt),
          lastModifiedAtClient: Value(deleteMeta.lastModifiedAtClient),
        ));
      }
    }
  }

  /// 共有スコープのとき、コース配下の dose を sync_queue に積む。
  /// materialize はトランザクション内で走るので、キュー投入は tx の外で行う。
  Future<void> _enqueueDosesSync({
    required String groupId,
    required int courseId,
  }) async {
    if (!isSharedScope(groupId)) return;
    final List<PreventionDoseEntity> doses = await (db
          .select(db.preventionDoses)
        ..where((PreventionDoses t) => t.courseId.equals(courseId)))
        .get();
    for (final PreventionDoseEntity d in doses) {
      await enqueueSyncIfShared(
        groupId: groupId,
        operation: d.deletedAt != null
            ? SyncOperation.delete
            : SyncOperation.update,
        targetTable: 'prevention_doses',
        recordId: d.id,
        payloadJson: jsonEncode(<String, dynamic>{
          'courseId': courseId,
          'seq': d.seq,
          'scheduledDate': d.scheduledDate,
        }),
      );
    }
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  /// 「ユーザーが何も置いていない空の dose」か。
  ///
  /// materialize のパス 2 で他の月へ流用してよいのはこれだけ。
  /// 投与実績・スキップ・メモのいずれかがあれば、その行はユーザーの
  /// 持ち物なので予定日を勝手に動かさない。
  static bool _isBlankDose(PreventionDoseEntity d) {
    if (d.administeredAt != null) return false;
    if (d.skipped) return false;
    if (d.notes != null && d.notes!.trim().isNotEmpty) return false;
    return true;
  }

  static void _validate({
    required int startMonth,
    required int endMonth,
    required int dayOfMonth,
    required String notifyTime,
  }) {
    if (startMonth < 1 || startMonth > 12) {
      throw ArgumentError('startMonth must be 1-12: $startMonth');
    }
    if (endMonth < 1 || endMonth > 12) {
      throw ArgumentError('endMonth must be 1-12: $endMonth');
    }
    if (dayOfMonth < 1 || dayOfMonth > 31) {
      throw ArgumentError('dayOfMonth must be 1-31: $dayOfMonth');
    }
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(notifyTime)) {
      throw ArgumentError('notifyTime must be HH:mm: $notifyTime');
    }
  }

  static String? _emptyToNull(String? s) {
    if (s == null) return null;
    final String trimmed = s.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
