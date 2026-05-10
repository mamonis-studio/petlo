// ============================================================================
// petlo - Medication Reminders Table
// ============================================================================
//
// 薬リマインダー。時刻×N + 曜日選択でローカル通知をスケジュール。
// rev3: 無料1件、Pro無制限。
// rev5: Apple Watch / Wear OS にも通知伝播 (F-17)。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('MedicationReminderEntity')
class MedicationReminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// 薬の名前
  TextColumn get medicineName => text()();

  /// 量 (任意)
  TextColumn get dosage => text().nullable()();

  /// 通知時刻のリスト (HH:mm形式)
  /// 例: ["07:00", "21:00"]
  TextColumn get times => text().map(const TimeOfDayListConverter())();

  /// 通知曜日 (bitset)
  /// 例: 月水金 → {1, 3, 5}
  IntColumn get weekdaysBits =>
      integer().map(const WeekdaysBitsetConverter())();

  /// リマインダー有効
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 開始日 (任意、UTC msec)
  IntColumn get startDate => integer().nullable()();

  /// 終了日 (任意、UTC msec)
  IntColumn get endDate => integer().nullable()();

  TextColumn get notes => text().nullable()();

  TextColumn get createdBy => text().nullable()();
  TextColumn get syncStatus => text()
      .map(const AppEnumConverter(SyncStatus.values))
      .withDefault(const Constant('synced'))();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get lastModifiedAtClient => integer().nullable()();
}
