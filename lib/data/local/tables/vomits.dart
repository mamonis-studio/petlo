// ============================================================================
// petlo - Vomits Table
// ============================================================================
//
// 嘔吐記録 (rev5新規、rev5.5で色2階層化)。
//
// rev5.5仕様:
//   - メイン4色 + Other経由で詳細5色 (合計9種類のenum)
//   - 誤食疑いフラグ (suspectIngestion)
//   - 写真撮影可能 (緊急判断材料)
//   - colorOtherText: Other選択時の自由記述
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('VomitEntity')
class Vomits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// 色 (rev5.5: 2階層enum)
  TextColumn get color =>
      text().map(const AppEnumConverter(VomitColor.values))();

  /// "other" 選択時の自由記述
  TextColumn get colorOtherText => text().nullable()();

  TextColumn get amount =>
      text().map(const AppEnumConverter(RecordAmount.values))();

  /// 1回の事象内で複数回吐いた場合のカウント
  IntColumn get count => integer().withDefault(const Constant(1))();

  /// 食物が混ざっていたか
  BoolColumn get containsFood => boolean().withDefault(const Constant(false))();

  /// 誤食疑い (緊急度判定用)
  BoolColumn get suspectIngestion =>
      boolean().withDefault(const Constant(false))();

  IntColumn get vomitedAt => integer()();

  TextColumn get notes => text().nullable()();
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
