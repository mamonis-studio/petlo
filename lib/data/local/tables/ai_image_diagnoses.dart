// ============================================================================
// petlo - AI Image Diagnoses Table
// ============================================================================
//
// AI画像診断結果 (rev5: F-19)。うんち写真からの色・形状観察。
//
// rev5.5仕様:
//   - pet_id NOT NULL (犬猫別プロンプト適用に必須)
//   - 画像はR2に24時間保存後自動削除 (GDPR配慮)
//   - アカウント削除時はR2即時削除 (rev5.4)
//   - poops.aiDiagnosisId からこのテーブルを参照可能
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('AiImageDiagnosisEntity')
class AiImageDiagnoses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();

  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  /// ペットID (rev5.5: NOT NULL)
  IntColumn get petId => integer()();

  /// 診断対象種別 (現在は'poop'のみ、将来他の種類追加可能)
  TextColumn get diagnosisType => text().withDefault(const Constant('poop'))();

  /// ローカル画像パス (相対パス)
  TextColumn get imagePath => text()();

  /// R2上の一時画像キー (24時間後に削除される)
  TextColumn get r2Key => text().nullable()();

  /// AIの返答全文
  TextColumn get aiResponse => text()();

  /// 診断日時 (UTC msec)
  IntColumn get diagnosedAt => integer()();

  /// フィードバック評価
  TextColumn get rating => text()
      .map(const AppEnumConverter(AiFeedback.values))
      .withDefault(const Constant('none'))();

  TextColumn get syncStatus => text()
      .map(const AppEnumConverter(SyncStatus.values))
      .withDefault(const Constant('synced'))();

  IntColumn get createdAt => integer()();
}
