// ============================================================================
// petlo - Meals Table
// ============================================================================
//
// 食事記録。foodsマスタ参照 + 直近3銘柄ボタン用に最近使用順で取得できる。
//
// rev5仕様:
//   - foodsマスタは別テーブル (foods)、ここはfoodIdで参照
//   - amountG: 量(グラム)、量入力ない場合はnull
//   - appetite: 食いつき5段階
//   - eatenAt: 実際の食事時刻 (recorded_atと別、後から修正可能)
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('MealEntity')
class Meals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  /// ペットID (NOT NULL)
  IntColumn get petId => integer()();

  /// foodsマスタ参照 (任意、フリー入力もあり)
  IntColumn get foodId => integer().nullable()();

  /// フリー入力の銘柄名 (foodId未指定時)
  TextColumn get foodNameFreeText => text().nullable()();

  /// 量 (グラム、整数)
  IntColumn get amountG => integer().nullable()();

  /// 食いつき
  TextColumn get appetite =>
      text().map(const AppEnumConverter(MealAppetite.values))();

  /// 食事時刻 (UTC msec) — 編集可能
  IntColumn get eatenAt => integer()();

  /// メモ
  TextColumn get notes => text().nullable()();

  /// 写真の相対パス
  TextColumn get photoPath => text().nullable()();

  TextColumn get createdBy => text().nullable()();
  TextColumn get syncStatus => text()
      .map(const AppEnumConverter(SyncStatus.values))
      .withDefault(const Constant('synced'))();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get lastModifiedAtClient => integer().nullable()();
}
