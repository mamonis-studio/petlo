// ============================================================================
// petlo - BCS Checks Table
// ============================================================================
//
// Body Condition Score (体型スコア) のセルフチェック履歴。
// rev3: 5段階 (1=痩せすぎ, 3=理想, 5=肥満)
// 犬猫別の判定基準を持つ (UI側で表示分岐)。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('BcsCheckEntity')
class BcsChecks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// 5段階スコア
  TextColumn get score =>
      text().map(const AppEnumConverter(BcsScore.values))();

  /// チェック日時 (UTC msec)
  IntColumn get checkedAt => integer()();

  /// 関連写真 (横/上から撮ったもの)
  TextColumn get photoPaths =>
      text().map(const NullableStringListConverter()).nullable()();

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
