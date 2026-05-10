// ============================================================================
// petlo - Weekly Summaries Table
// ============================================================================
//
// 週次AIサマリー (rev5.1: F-20、Pro限定)。
// 毎週日曜深夜にCron Triggerで生成、ユーザーは月曜朝に閲覧。
//
// rev5.5仕様: pet_id NOT NULL
//
// ============================================================================

import 'package:drift/drift.dart';

@DataClassName('WeeklySummaryEntity')
class WeeklySummaries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();

  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  /// ペットID (rev5.5: NOT NULL)
  IntColumn get petId => integer()();

  /// 週開始日 (月曜日、UTC msec)
  IntColumn get weekStart => integer()();

  /// 週終了日 (日曜日、UTC msec)
  IntColumn get weekEnd => integer()();

  /// AI生成サマリー本文
  TextColumn get summaryText => text()();

  /// 生成日時 (UTC msec)
  IntColumn get generatedAt => integer()();

  /// 既読
  BoolColumn get seen => boolean().withDefault(const Constant(false))();

  IntColumn get createdAt => integer()();
}
