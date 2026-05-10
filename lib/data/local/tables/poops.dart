// ============================================================================
// petlo - Poops Table
// ============================================================================
//
// うんち記録。ブリストル5段階 + 5色 + 量。
// rev5.5: AI画像診断と連動可能(別テーブルai_image_diagnosesに結果保存)。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('PoopEntity')
class Poops extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  IntColumn get petId => integer()();

  /// ブリストル形状 (1-5)
  TextColumn get form =>
      text().map(const AppEnumConverter(PoopForm.values))();

  /// 色
  TextColumn get color =>
      text().map(const AppEnumConverter(PoopColor.values))();

  /// 量
  TextColumn get amount =>
      text().map(const AppEnumConverter(RecordAmount.values))();

  /// 排泄時刻 (UTC msec)
  IntColumn get pooedAt => integer()();

  TextColumn get notes => text().nullable()();
  TextColumn get photoPath => text().nullable()();

  /// AI画像診断のID (ai_image_diagnoses.id へのFK、任意)
  IntColumn get aiDiagnosisId => integer().nullable()();

  TextColumn get createdBy => text().nullable()();
  TextColumn get syncStatus => text()
      .map(const AppEnumConverter(SyncStatus.values))
      .withDefault(const Constant('synced'))();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get lastModifiedAtClient => integer().nullable()();
}
