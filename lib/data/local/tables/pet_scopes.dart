// ============================================================================
// petlo - Pet Scopes Table (multi-scope pet sharing)
// ============================================================================
//
// 1 ペット × N グループ の関連を表現する中間テーブル。
//
// build 43 (Phase G1) で導入。設計レポート §1 (multi_scope_pet_sharing_design.md)
// に基づく。本 build はスキーマ追加と backfill のみ。
//
// 既存 `pets.group_id` は **primary scope (物理本籍)** として残し、その値を
// そのまま `pet_scopes` の最初の 1 行として backfill する。これにより v6
// 直後のユーザー視点では「1 ペット = 1 scope」の挙動が完全に維持される。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';
import 'pets.dart';

@DataClassName('PetScopeEntity')
class PetScopes extends Table {
  /// ローカル主キー
  IntColumn get id => integer().autoIncrement()();

  /// 関連するペット (ローカル pets.id)。
  /// pets が物理削除されたら CASCADE で消す。
  /// pets は通常論理削除なので CASCADE 発火はアンインストール後の再 install のみ。
  IntColumn get petId =>
      integer().references(Pets, #id, onDelete: KeyAction.cascade)();

  /// scope の groupId。'personal' or <group_uuid>。
  /// `pets.group_id` と同じ意味体系。
  TextColumn get groupId => text()();

  /// この pet × group での権限 (グループ全体の `groups.my_permission` とは独立)。
  /// Decision Log #4: per-pet 権限はグループ権限を**上書き**する。
  TextColumn get permission =>
      text().map(const AppEnumConverter(MemberPermission.values))();

  /// primary scope フラグ。1 ペットあたり高々 1 行のみ true。
  /// `pets.group_id` が指している scope と一致する。
  /// child tables (meals 等) の `group_id` はこの primary scope に固定される
  /// (Decision Log #1 Hybrid モデル)。
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  /// 共有された日時 (UTC msec)
  IntColumn get sharedAt => integer()();

  /// 誰がこの scope に共有したか (server user_id)。
  /// 既存 pets の backfill 時は不明なので nullable。
  TextColumn get sharedByUserId => text().nullable()();

  /// 同期状態
  TextColumn get syncStatus => text()
      .map(const AppEnumConverter(SyncStatus.values))
      .withDefault(const Constant('synced'))();

  /// 論理削除日時 (UTC msec)。共有解除は deletedAt セットで表現する。
  IntColumn get deletedAt => integer().nullable()();

  /// 作成日時 (UTC msec)
  IntColumn get createdAt => integer()();

  /// 更新日時 (UTC msec)
  IntColumn get updatedAt => integer()();

  /// クライアント側最終更新時刻 (rev5.3 参考値、LWW 用)
  IntColumn get lastModifiedAtClient => integer().nullable()();

  /// 同じ (pet × group) の二重登録を禁止。
  /// SQLite なので UNIQUE INDEX を customConstraint で表現。
  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
        <Column<Object>>{petId, groupId},
      ];
}
