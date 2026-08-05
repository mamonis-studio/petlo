// ============================================================================
// petlo - Prevention Doses Table
// ============================================================================
//
// 予防コースの 1 回分 (build 72)。
// コース作成時にシーズン分をまとめて materialize する。
//
// なぜ導出せず実体として持つか:
//   1. 投与実績はユーザーの資産。コース設定 (開始月等) を後から変えても
//      実績が消えてはならない。
//   2. 「予定 10 日 / 実際 14 日」のズレを記録できる。
//   3. 通知 ID を dose 単位で安定採番できる (再スケジュール時に冪等)。
//
// pet_id はコース経由で辿れるが冗長に保持する。
//   → pets_repository.softDeletePet の petBoundTables cascade に載せるため。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('PreventionDoseEntity')
class PreventionDoses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  /// 所属コース
  IntColumn get courseId => integer()();

  /// 対象ペット (cascade 用の冗長列。course.petId と常に一致)
  IntColumn get petId => integer()();

  /// シーズン内の通し番号 (1 始まり)
  IntColumn get seq => integer()();

  /// 予定日 (UTC msec。その日の 00:00 ローカル基準)
  IntColumn get scheduledDate => integer()();

  /// 実際に投与した日時 (UTC msec)。null = 未投与
  IntColumn get administeredAt => integer().nullable()();

  /// ユーザーが明示的にスキップした場合 true
  /// (獣医指示で 1 回飛ばす等。未投与とは区別する)
  BoolColumn get skipped => boolean().withDefault(const Constant(false))();

  /// 投与記録時に medications へ INSERT した行の id。
  /// 投与を取り消した際に該当 medications 行を論理削除するために保持。
  IntColumn get medicationId => integer().nullable()();

  /// シーズン最終回か。通知文言を切り替えるために使う。
  BoolColumn get isFinal => boolean().withDefault(const Constant(false))();

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
