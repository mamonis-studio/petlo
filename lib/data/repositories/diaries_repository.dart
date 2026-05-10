// ============================================================================
// petlo - Diaries Repository
// ============================================================================
//
// 日記のCRUD。
// rev3 F-08: 写真複数枚 + タグ + フリーテキスト。
// rev5: 無料月10件、Pro無制限。
//
// 設計:
//   - body は必須(タイトルは任意)
//   - photoPaths は List<String> (相対パス)
//   - tags は List<String>、自由記述
//   - eventAt: 出来事の日時(過去日付OK)
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class DiariesRepository extends BaseRepository {
  DiariesRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  /// ペットの日記(新しい順)
  Stream<List<DiaryEntity>> watchForPet(int petId, {int? limit}) {
    final query = db.select(db.diaries)
      ..where((Diaries t) => t.petId.equals(petId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Diaries>>[
        (Diaries t) => OrderingTerm(
              expression: t.eventAt,
              mode: OrderingMode.desc,
            ),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  /// 期間内の日記(古い順、カレンダー連携想定)
  Stream<List<DiaryEntity>> watchInRange({
    required int petId,
    required int fromMsec,
    required int toMsec,
  }) {
    return (db.select(db.diaries)
          ..where((Diaries t) =>
              t.petId.equals(petId) &
              t.deletedAt.isNull() &
              t.eventAt.isBetweenValues(fromMsec, toMsec))
          ..orderBy(<OrderClauseGenerator<Diaries>>[
            (Diaries t) => OrderingTerm(expression: t.eventAt),
          ]))
        .watch();
  }

  Future<DiaryEntity?> getById(int id) {
    return (db.select(db.diaries)
          ..where((Diaries t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 写真ありの日記のみ(写真ギャラリー画面用、新しい順)
  Stream<List<DiaryEntity>> watchWithPhotos(int petId, {int? limit}) {
    // photoPaths は JSON 配列文字列。NULL でなく、かつ "[]" でないものを返す。
    // 完全な「空配列除外」は Dart 側でフィルタ(SQL では難しい)。
    final base = db.select(db.diaries)
      ..where((Diaries t) =>
          t.petId.equals(petId) &
          t.deletedAt.isNull() &
          t.photoPaths.isNotNull())
      ..orderBy(<OrderClauseGenerator<Diaries>>[
        (Diaries t) => OrderingTerm(
              expression: t.eventAt,
              mode: OrderingMode.desc,
            ),
      ]);
    return base.watch().map((List<DiaryEntity> list) =>
        list.where((d) => (d.photoPaths ?? <String>[]).isNotEmpty).toList()
          ..sort((a, b) => b.eventAt.compareTo(a.eventAt))
          ..take(limit ?? list.length).toList());
  }

  /// 指定月の日記件数(無料プラン制限チェック用)
  /// rev5: freeMaxDiariesPerMonth = 10
  Future<int> countInMonth({
    required String groupId,
    required int year,
    required int month,
  }) async {
    final DateTime first = DateTime(year, month, 1);
    final DateTime nextMonth = DateTime(year, month + 1, 1);
    final int from = first.toUtc().millisecondsSinceEpoch;
    final int to = nextMonth.toUtc().millisecondsSinceEpoch;

    final result = await (db.selectOnly(db.diaries)
          ..addColumns(<Expression<int>>[db.diaries.id.count()])
          ..where(db.diaries.groupId.equals(groupId) &
              db.diaries.deletedAt.isNull() &
              db.diaries.createdAt.isBetweenValues(from, to)))
        .getSingle();
    return result.read(db.diaries.id.count()) ?? 0;
  }

  // ============================================================================
  // Write
  // ============================================================================

  Future<int> create({
    required String groupId,
    required int petId,
    String? title,
    required String body,
    List<String>? tags,
    List<String>? photoPaths,
    required int eventAtMsec,
    String? createdBy,
  }) async {
    if (body.trim().isEmpty) {
      throw ArgumentError('body cannot be empty');
    }
    final meta = buildCreateMetadata(groupId: groupId);

    final int newId = await db.into(db.diaries).insert(
          DiariesCompanion.insert(
            groupId: Value(groupId),
            petId: petId,
            title: Value(_emptyToNull(title)),
            body: body.trim(),
            tags: Value(tags == null || tags.isEmpty ? null : tags),
            photoPaths: Value(
                photoPaths == null || photoPaths.isEmpty ? null : photoPaths),
            eventAt: eventAtMsec,
            createdBy: Value(createdBy),
            syncStatus: Value(meta.initialSyncStatus),
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            lastModifiedAtClient: Value(meta.lastModifiedAtClient),
          ),
        );

    await enqueueSyncIfShared(
      groupId: groupId,
      operation: SyncOperation.insert,
      targetTable: 'diaries',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'petId': petId,
        'title': title,
        'eventAt': eventAtMsec,
      }),
    );
    return newId;
  }

  Future<bool> update({
    required int diaryId,
    String? title,
    bool clearTitle = false,
    String? body,
    List<String>? tags,
    bool clearTags = false,
    List<String>? photoPaths,
    bool clearPhotos = false,
    int? eventAtMsec,
  }) async {
    final DiaryEntity? existing = await getById(diaryId);
    if (existing == null) throw StateError('Diary not found: id=$diaryId');

    if (body != null && body.trim().isEmpty) {
      throw ArgumentError('body cannot be empty');
    }

    final meta = buildUpdateMetadata(groupId: existing.groupId);

    final companion = DiariesCompanion(
      title: clearTitle
          ? const Value(null)
          : (title == null ? const Value.absent() : Value(_emptyToNull(title))),
      body: body == null ? const Value.absent() : Value(body.trim()),
      tags: clearTags
          ? const Value(null)
          : (tags == null
              ? const Value.absent()
              : Value(tags.isEmpty ? null : tags)),
      photoPaths: clearPhotos
          ? const Value(null)
          : (photoPaths == null
              ? const Value.absent()
              : Value(photoPaths.isEmpty ? null : photoPaths)),
      eventAt: eventAtMsec == null ? const Value.absent() : Value(eventAtMsec),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    );

    final int affected = await (db.update(db.diaries)
          ..where((Diaries t) => t.id.equals(diaryId)))
        .write(companion);

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.update,
        targetTable: 'diaries',
        recordId: diaryId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  Future<bool> softDelete(int diaryId) async {
    final DiaryEntity? existing = await getById(diaryId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);
    final int affected = await (db.update(db.diaries)
          ..where((Diaries t) => t.id.equals(diaryId)))
        .write(DiariesCompanion(
      deletedAt: Value(meta.deletedAt),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'diaries',
        recordId: diaryId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  static String? _emptyToNull(String? s) {
    if (s == null) return null;
    final String trimmed = s.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
