// ============================================================================
// petlo - Pees Table
// ============================================================================
//
// おしっこ記録。色 + 量 + 回数(1度に複数回 → countで表現)。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('PeeEntity')
class Pees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  TextColumn get color =>
      text().map(const AppEnumConverter(PeeColor.values))();

  TextColumn get amount =>
      text().map(const AppEnumConverter(RecordAmount.values))();

  /// 回数 (デフォルト1回、まとめ記録時に増やせる)
  IntColumn get count => integer().withDefault(const Constant(1))();

  IntColumn get peedAt => integer()();

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
