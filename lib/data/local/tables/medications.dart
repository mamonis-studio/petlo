// ============================================================================
// petlo - Medications Table
// ============================================================================
//
// 投薬履歴。実際に薬を与えた記録 (リマインダーとは別)。
// medicationReminderIdで関連リマインダーと紐付け可能。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('MedicationEntity')
class Medications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// 関連リマインダー (任意)
  IntColumn get reminderId => integer().nullable()();

  /// 薬の名前
  TextColumn get medicineName => text()();

  /// 投与量 (例: "1錠", "0.5ml")
  TextColumn get dosage => text().nullable()();

  /// 投与日時 (UTC msec)
  IntColumn get administeredAt => integer()();

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
