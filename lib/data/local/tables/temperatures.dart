// ============================================================================
// petlo - Temperatures Table
// ============================================================================
//
// 体温記録 (rev5新規)。摂氏で保存、表示時に華氏変換。
// 整数で扱うため、0.1℃単位 × 10倍で保存 (例: 38.5℃ → 385)。
//
// 犬の正常: 37.5-39.0℃
// 猫の正常: 38.0-39.2℃
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('TemperatureEntity')
class Temperatures extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// 体温 (0.1℃単位、整数 × 10倍で保存)
  /// 38.5℃ → 385
  IntColumn get tempCelsiusX10 => integer()();

  IntColumn get measuredAt => integer()();

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
