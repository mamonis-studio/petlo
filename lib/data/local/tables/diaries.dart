// ============================================================================
// petlo - Diaries Table
// ============================================================================
//
// 日記。写真+メモ+タグの自由記述。
// 健康記録ではない、日常の出来事を残すためのもの。
//
// rev3仕様: 写真は複数枚OK (photoPathsをJSON配列で保存)
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('DiaryEntity')
class Diaries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// タイトル (任意)
  TextColumn get title => text().nullable()();

  /// 本文
  TextColumn get body => text()();

  /// タグ一覧 (例: ["散歩", "公園", "おもちゃ"])
  TextColumn get tags =>
      text().map(const NullableStringListConverter()).nullable()();

  /// 写真の相対パス一覧 (複数枚OK)
  TextColumn get photoPaths =>
      text().map(const NullableStringListConverter()).nullable()();

  /// 出来事の日時
  IntColumn get eventAt => integer()();

  TextColumn get createdBy => text().nullable()();
  TextColumn get syncStatus => text()
      .map(const AppEnumConverter(SyncStatus.values))
      .withDefault(const Constant('synced'))();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get lastModifiedAtClient => integer().nullable()();
}
