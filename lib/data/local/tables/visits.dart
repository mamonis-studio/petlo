// ============================================================================
// petlo - Visits Table
// ============================================================================
//
// 通院記録。診断、治療内容、費用を記録。
// rev4: 処方薬入力時に投薬リマインダー作成への導線あり。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('VisitEntity')
class Visits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// 通院日 (UTC msec)
  IntColumn get visitedAt => integer()();

  /// 病院名
  TextColumn get clinicName => text().nullable()();

  /// 担当獣医名
  TextColumn get vetName => text().nullable()();

  /// 主訴 (例: "皮膚のかゆみ")
  TextColumn get reason => text()();

  /// 診断結果 (例: "アレルギー性皮膚炎")
  TextColumn get diagnosis => text().nullable()();

  /// 治療内容
  TextColumn get treatment => text().nullable()();

  /// 費用 (円、整数)
  IntColumn get costJpy => integer().nullable()();

  /// 関連写真 (検査結果、レシート等)
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
