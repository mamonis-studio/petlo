// ============================================================================
// petlo - Streak Statuses Table
// ============================================================================
//
// 連続記録ストリーク (rev5: F-68)。
// ホーム画面右上に表示。
//
// rev5.4: Streak Freeze (Pro限定、月1回過去日記録でストリーク維持) サポート。
// rev5.5: 日付境界はユーザーローカル基準で判定 (UTCでなく)。
//
// 設計: ペットごとに1レコード (pet_idユニーク)。
//
// ============================================================================

import 'package:drift/drift.dart';

@DataClassName('StreakStatusEntity')
class StreakStatuses extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ペットID (1ペット1レコード)
  IntColumn get petId => integer().unique()();

  /// 現在の連続日数
  IntColumn get currentStreakDays => integer().withDefault(const Constant(0))();

  /// 最長連続日数 (歴代記録)
  IntColumn get longestStreakDays => integer().withDefault(const Constant(0))();

  /// 最後に記録があった日 (ユーザーローカル日付の YYYY-MM-DD 形式文字列)
  /// rev5.5: タイムゾーン依存判定のため、UTC msecではなく日付文字列で持つ
  TextColumn get lastRecordDate => text().nullable()();

  /// 今月Streak Freeze使用済みか (rev5.4)
  /// 形式: YYYY-MM (例: "2026-05")
  TextColumn get freezeUsedMonth => text().nullable()();

  IntColumn get updatedAt => integer()();
}
