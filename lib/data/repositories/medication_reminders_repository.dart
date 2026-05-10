// ============================================================================
// petlo - Medication Reminders Repository
// ============================================================================
//
// 投薬リマインダーのCRUD。
//
// rev3 F-13(投薬リマインダー)、F-17 (Apple Watch / Wear OS 通知伝播は将来)
// rev5: 無料1件、Pro無制限
//
// 注意:
//   - 通知のスケジュール自体は NotificationScheduler が担当 (Stage 4)
//   - このRepositoryは DB の CRUD のみに専念
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class MedicationRemindersRepository extends BaseRepository {
  MedicationRemindersRepository(super.db);

  // ==========================================================================
  // Read
  // ==========================================================================

  /// ペットの全リマインダー(updatedAt 新しい順)
  Stream<List<MedicationReminderEntity>> watchForPet(
    int petId, {
    int? limit,
  }) {
    final query = db.select(db.medicationReminders)
      ..where((MedicationReminders t) =>
          t.petId.equals(petId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<MedicationReminders>>[
        (MedicationReminders t) =>
            OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  /// 有効なリマインダーのみ(通知スケジュール対象)
  Stream<List<MedicationReminderEntity>> watchEnabledForPet(int petId) {
    final query = db.select(db.medicationReminders)
      ..where((MedicationReminders t) =>
          t.petId.equals(petId) &
          t.deletedAt.isNull() &
          t.enabled.equals(true))
      ..orderBy(<OrderClauseGenerator<MedicationReminders>>[
        (MedicationReminders t) =>
            OrderingTerm(expression: t.medicineName, mode: OrderingMode.asc),
      ]);
    return query.watch();
  }

  /// グループ全体の有効リマインダー(全ペット横断、ホーム/Plansタブで使う)
  Stream<List<MedicationReminderEntity>> watchEnabledForGroup(String groupId) {
    final query = db.select(db.medicationReminders)
      ..where((MedicationReminders t) =>
          t.groupId.equals(groupId) &
          t.deletedAt.isNull() &
          t.enabled.equals(true))
      ..orderBy(<OrderClauseGenerator<MedicationReminders>>[
        (MedicationReminders t) =>
            OrderingTerm(expression: t.medicineName, mode: OrderingMode.asc),
      ]);
    return query.watch();
  }

  /// 全 enabled リマインダー(起動時の通知再スケジュール用、Future)
  Future<List<MedicationReminderEntity>> getAllEnabled() {
    final query = db.select(db.medicationReminders)
      ..where((MedicationReminders t) =>
          t.deletedAt.isNull() & t.enabled.equals(true));
    return query.get();
  }

  /// 単一取得 (notification scheduler 用)
  Future<MedicationReminderEntity?> getById(int id) {
    return (db.select(db.medicationReminders)
          ..where((MedicationReminders t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// グループ内のリマインダー件数(無料制限の判定用)
  Future<int> countActiveForGroup(String groupId) async {
    final Expression<int> cnt = db.medicationReminders.id.count();
    final query = db.selectOnly(db.medicationReminders)
      ..addColumns(<Expression<Object>>[cnt])
      ..where(db.medicationReminders.groupId.equals(groupId) &
          db.medicationReminders.deletedAt.isNull());
    final res = await query.getSingle();
    return res.read(cnt) ?? 0;
  }

  // ==========================================================================
  // Create
  // ==========================================================================

  Future<int> create({
    required String groupId,
    required int petId,
    required String medicineName,
    required List<String> times, // ["07:00", "21:00"] etc.
    required Set<int> weekdays, // {1,3,5} = Mon/Wed/Fri、空={}=毎日
    String? dosage,
    String? notes,
    int? startDateMsec,
    int? endDateMsec,
    bool enabled = true,
  }) async {
    if (medicineName.trim().isEmpty) {
      throw ArgumentError('medicineName must not be empty');
    }
    if (times.isEmpty) {
      throw ArgumentError('times must not be empty');
    }
    for (final String t in times) {
      if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(t)) {
        throw ArgumentError('Invalid time format: $t (expected HH:mm)');
      }
    }
    for (final int wd in weekdays) {
      if (wd < 0 || wd > 6) {
        throw ArgumentError('weekday must be 0-6, got $wd');
      }
    }

    final meta = buildCreateMetadata(groupId: groupId);

    final int id = await db.into(db.medicationReminders).insert(
          MedicationRemindersCompanion.insert(
            groupId: Value(groupId),
            petId: petId,
            medicineName: medicineName.trim(),
            dosage: Value(dosage?.trim().isEmpty == true ? null : dosage?.trim()),
            times: times,
            weekdaysBits: weekdays,
            enabled: Value(enabled),
            startDate: Value(startDateMsec),
            endDate: Value(endDateMsec),
            notes: Value(notes?.trim().isEmpty == true ? null : notes?.trim()),
            syncStatus: Value(meta.initialSyncStatus),
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            lastModifiedAtClient: Value(meta.lastModifiedAtClient),
          ),
        );

    await enqueueSyncIfShared(
      groupId: groupId,
      operation: SyncOperation.insert,
      targetTable: 'medication_reminders',
      recordId: id,
      payloadJson: jsonEncode(<String, dynamic>{}),
    );

    return id;
  }

  // ==========================================================================
  // Update
  // ==========================================================================

  Future<bool> update({
    required int reminderId,
    String? medicineName,
    List<String>? times,
    Set<int>? weekdays,
    String? dosage,
    bool clearDosage = false,
    String? notes,
    bool clearNotes = false,
    int? startDateMsec,
    bool clearStartDate = false,
    int? endDateMsec,
    bool clearEndDate = false,
    bool? enabled,
  }) async {
    final MedicationReminderEntity? existing = await getById(reminderId);
    if (existing == null) return false;

    if (times != null) {
      if (times.isEmpty) {
        throw ArgumentError('times must not be empty');
      }
      for (final String t in times) {
        if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(t)) {
          throw ArgumentError('Invalid time format: $t');
        }
      }
    }
    if (weekdays != null) {
      for (final int wd in weekdays) {
        if (wd < 0 || wd > 6) {
          throw ArgumentError('weekday must be 0-6');
        }
      }
    }

    final meta = buildUpdateMetadata(groupId: existing.groupId);

    final companion = MedicationRemindersCompanion(
      medicineName: medicineName == null
          ? const Value.absent()
          : Value(medicineName.trim()),
      times: times == null ? const Value.absent() : Value(times),
      weekdaysBits:
          weekdays == null ? const Value.absent() : Value(weekdays),
      dosage: clearDosage
          ? const Value<String?>(null)
          : (dosage == null ? const Value.absent() : Value(dosage.trim())),
      notes: clearNotes
          ? const Value<String?>(null)
          : (notes == null ? const Value.absent() : Value(notes.trim())),
      startDate: clearStartDate
          ? const Value<int?>(null)
          : (startDateMsec == null
              ? const Value.absent()
              : Value(startDateMsec)),
      endDate: clearEndDate
          ? const Value<int?>(null)
          : (endDateMsec == null
              ? const Value.absent()
              : Value(endDateMsec)),
      enabled: enabled == null ? const Value.absent() : Value(enabled),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    );

    final int rows = await (db.update(db.medicationReminders)
          ..where((MedicationReminders t) => t.id.equals(reminderId)))
        .write(companion);

    if (rows > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.update,
        targetTable: 'medication_reminders',
        recordId: reminderId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return rows > 0;
  }

  /// 有効/無効のトグル(専用ショートカット)
  Future<bool> setEnabled(int reminderId, bool enabled) {
    return update(reminderId: reminderId, enabled: enabled);
  }

  // ==========================================================================
  // Delete
  // ==========================================================================

  Future<bool> softDelete(int reminderId) async {
    final MedicationReminderEntity? existing = await getById(reminderId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);

    final int rows = await (db.update(db.medicationReminders)
          ..where((MedicationReminders t) => t.id.equals(reminderId)))
        .write(
      MedicationRemindersCompanion(
        deletedAt: Value(meta.deletedAt),
        syncStatus: Value(meta.updatedSyncStatus),
        updatedAt: Value(meta.updatedAt),
        lastModifiedAtClient: Value(meta.lastModifiedAtClient),
      ),
    );

    if (rows > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'medication_reminders',
        recordId: reminderId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return rows > 0;
  }
}
