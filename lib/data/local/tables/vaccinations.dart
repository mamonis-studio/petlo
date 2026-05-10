// ============================================================================
// petlo - Vaccinations Table
// ============================================================================
//
// ワクチン記録。次回予定日も同時に保持して、リマインダー化できる。
// 種類: 混合ワクチン、狂犬病、レプトスピラ、その他カスタム
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('VaccinationEntity')
class Vaccinations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// ワクチン種別 (例: "混合ワクチン", "狂犬病", "レプトスピラ", カスタム)
  TextColumn get kind => text()();

  /// 接種日 (UTC msec)
  IntColumn get administeredAt => integer()();

  /// 次回予定日 (UTC msec)
  IntColumn get nextDueAt => integer().nullable()();

  /// 病院名
  TextColumn get clinicName => text().nullable()();

  /// 証明書写真
  TextColumn get photoPath => text().nullable()();

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
