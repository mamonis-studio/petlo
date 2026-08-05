// ============================================================================
// petlo - Prevention Courses Table
// ============================================================================
//
// 予防コース (build 72)。
// フィラリア / ノミダニ予防を「年 × ペット × 種別」の 1 コースとして管理する。
//
// 設計方針:
//   - schedules (category=medication) は「毎日/毎週」しか表現できないため、
//     季節性 × 月次の予防薬は独立テーブルで扱う。
//   - コース設定 (開始月・終了月・投与日) を後から変更しても、投与実績
//     (prevention_doses.administered_at) は失われない。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('PreventionCourseEntity')
class PreventionCourses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// コース種別 (フィラリア / ノミダニ / オールインワン)
  TextColumn get kind =>
      text().map(const AppEnumConverter(PreventionKind.values))();

  /// 対象年 (西暦。例: 2026)
  IntColumn get year => integer()();

  /// 予防開始月 (1-12)
  IntColumn get startMonth => integer()();

  /// 予防終了月 (1-12)。
  /// endMonth < startMonth の場合は越年コースとして扱う (沖縄の通年予防等)。
  IntColumn get endMonth => integer()();

  /// 毎月の投与日 (1-31)。
  /// 該当月に存在しない日 (2月31日 等) は月末日に丸める。
  IntColumn get dayOfMonth => integer()();

  /// 通知時刻 "HH:mm" (24h)
  TextColumn get notifyTime => text().withDefault(const Constant('09:00'))();

  /// 薬剤名 (例: "ネクスガードスペクトラ")
  TextColumn get medicineName => text().nullable()();

  /// 用量 (例: "1錠", "1ピペット")
  TextColumn get dosage => text().nullable()();

  /// 剤型
  TextColumn get form => text()
      .map(const AppEnumConverter(PreventionForm.values))
      .withDefault(const Constant('chewable'))();

  /// 地域プリセット (期間の初期値算出に使用。表示にも使う)
  TextColumn get region => text()
      .map(const AppEnumConverter(PreventionRegion.values))
      .withDefault(const Constant('custom'))();

  /// シーズン前検査の実施日 (UTC msec)。null = 未実施
  IntColumn get testedAt => integer().nullable()();

  /// シーズン前検査のリマインドを行うか。
  /// kind=filaria のとき既定 true、flea_tick のとき既定 false。
  BoolColumn get testReminderEnabled =>
      boolean().withDefault(const Constant(false))();

  /// 通知全体の ON/OFF
  BoolColumn get notificationEnabled =>
      boolean().withDefault(const Constant(true))();

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
