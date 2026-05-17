// ============================================================================
// petlo - Pets Table
// ============================================================================
//
// ペットの基本情報。すべての記録はこのテーブルのidを参照する。
//
// rev5.5仕様:
//   - 持病、アレルギー、かかりつけ獣医、夜間救急の連絡先
//   - parted_at: お別れ日 (rev5.4: 今日以前のみバリデーション)
//   - parted_at_visible: 個人設定でメモリアル表示ON/OFF (SharedPreferencesで管理、
//                       テーブルには保存しない)
//   - sort_order: 並べ替えはローカル個人設定 (サーバー同期しない)
//   - groupId: 所属スコープ ('personal' or group_uuid)
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('PetEntity')
class Pets extends Table {
  /// ローカル主キー
  IntColumn get id => integer().autoIncrement()();

  /// サーバー側ID(共有グループに参加してる場合のみ)
  TextColumn get remoteId => text().nullable()();

  /// 所属スコープ: 'personal' or group_uuid
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  /// 名前 (例: "Taro", "ハナ")
  TextColumn get name => text().withLength(min: 1, max: 50)();

  /// 犬/猫
  TextColumn get type => text().map(const AppEnumConverter(PetType.values))();

  /// 犬種・猫種 (breeds_dogs.json / breeds_cats.json のkey)
  /// オンボーディングでは未入力 → 後から PetForm で詳細登録できるよう nullable。
  TextColumn get breed => text().withLength(max: 100).nullable()();

  /// 性別 (build 22: 任意項目化、未設定で登録可能)
  TextColumn get sex =>
      text().map(const AppEnumConverter(PetSex.values)).nullable()();

  /// 去勢/避妊済み
  BoolColumn get neutered => boolean().withDefault(const Constant(false))();

  /// 誕生日 (UTC msec, 日付のみ意味あり)
  IntColumn get birthday => integer().nullable()();

  /// 理想体重の下限 (グラム)
  IntColumn get idealWeightMinG => integer().nullable()();

  /// 理想体重の上限 (グラム)
  IntColumn get idealWeightMaxG => integer().nullable()();

  /// プロフィール写真の相対パス (アプリ専用フォルダ基準)
  /// rev3で確定: 絶対パスは保存しない (iOS sandbox UUID変更対策)
  TextColumn get photoPath => text().nullable()();

  /// 持病一覧 (JSON配列、rev5)
  TextColumn get chronicConditions =>
      text().map(const NullableStringListConverter()).nullable()();

  /// アレルギー一覧 (JSON配列、rev5)
  TextColumn get allergies =>
      text().map(const NullableStringListConverter()).nullable()();

  /// かかりつけ獣医
  TextColumn get primaryVetName => text().nullable()();
  TextColumn get primaryVetPhone => text().nullable()();
  TextColumn get primaryVetAddress => text().nullable()();

  /// 夜間救急連絡先 (rev5)
  TextColumn get emergencyVetName => text().nullable()();
  TextColumn get emergencyVetPhone => text().nullable()();
  TextColumn get emergencyVetAddress => text().nullable()();

  /// お別れ日 (UTC msec, rev4)
  /// rev5.4: 今日以前のみバリデーション(クライアント側)
  IntColumn get partedAt => integer().nullable()();

  /// 月命日通知 (rev4)
  TextColumn get memorialNotify => text()
      .map(const AppEnumConverter(MemorialNotifyFrequency.values))
      .withDefault(const Constant('off'))();

  /// 並び順 (ローカル個人設定、サーバー同期しない、rev5.5)
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// レコード作成者 (共有時のため)
  TextColumn get createdBy => text().nullable()();

  /// 同期状態
  TextColumn get syncStatus => text()
      .map(const AppEnumConverter(SyncStatus.values))
      .withDefault(const Constant('synced'))();

  /// 論理削除日時 (UTC msec)
  IntColumn get deletedAt => integer().nullable()();

  /// 作成日時 (UTC msec)
  /// 注: Dart側で挿入時に DateTime.now().millisecondsSinceEpoch を渡す。
  /// driftのcurrentDateAndTimeは秒単位なため、ms統一のためアプリ側で管理する。
  IntColumn get createdAt => integer()();

  /// 更新日時 (UTC msec) — rev5.3: サーバー受信時刻で上書きされる
  IntColumn get updatedAt => integer()();

  /// クライアント側最終更新時刻 (rev5.3 参考値、サーバーは信用しない)
  IntColumn get lastModifiedAtClient => integer().nullable()();

  // ===== Indexes =====
  // group_id + deleted_at で頻繁にフィルタするため複合インデックス
}
