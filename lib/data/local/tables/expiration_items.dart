// ============================================================================
// petlo - Expiration Items Table
// ============================================================================
//
// 期限管理 (rev3: F-14)。
// プリセット6種 (フィラリア、ノミダニ、ワクチン等) + 自由追加。
// 通知タイミング: 当日 / 3日前 / 1週間前 (rev3: F-15、無料は当日のみ)。
//
// rev5.2: カレンダー画面で月表示時の予定ドット表示にも使われる。
// rev5.4: OSカレンダーへの.icsエクスポート対象 (Pro限定)。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('ExpirationItemEntity')
class ExpirationItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// プリセット種別 (rev3: ReminderKind)
  TextColumn get kind =>
      text().map(const AppEnumConverter(ReminderKind.values))();

  /// カスタムタイトル (kind=customの時に使用)
  TextColumn get customTitle => text().nullable()();

  /// 期限日 (UTC msec)
  IntColumn get dueAt => integer()();

  /// 通知タイミング (リスト、複数設定可)
  /// 例: [on_day, three_days, one_week]
  /// JSONで保存
  TextColumn get leadTimes => text().map(const StringListConverter())();

  /// 完了済みか (済んだら次回分を新しいレコードで作成)
  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  /// 完了日時 (UTC msec)
  IntColumn get completedAt => integer().nullable()();

  /// OSカレンダーに書き出した時のevent_id (rev5.2: 重複防止用、rev5.5)
  TextColumn get osCalendarEventId => text().nullable()();

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
