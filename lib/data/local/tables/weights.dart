// ============================================================================
// petlo - Weights Table
// ============================================================================
//
// 体重記録。グラム単位で保存、表示時にkg/lb変換。
//
// rev3仕様: 整数gで保存、浮動小数誤差を防ぐ。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('WeightEntity')
class Weights extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// 体重 (グラム、整数で保存)
  /// 6.2kg → 6200g, 4.4kg → 4400g
  IntColumn get weightG => integer()();

  /// 測定時刻 (UTC msec)
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
