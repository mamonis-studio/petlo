# Multi-Scope Pet Sharing — 設計レポート

| 項目 | 値 |
|---|---|
| 起票 build | 42 直後 (build 43 候補) |
| 目的 | 1 ペットを複数グループ (Personal 含む) で同時編集可能にする |
| ステータス | **Spec-first 提案・未着手**。承認後に Phase G1+ で実装入り |
| スコープ | クライアント (Flutter) + Backend (Cloudflare Workers + D1) 両方 |
| 対象バージョン | v1.0 リリースに**含めない**前提で設計。v1.1 / v1.2 へ段階導入 |

---

## エグゼクティブ・サマリ

現状の petlo は **「1 ペット = 1 group_id の排他帰属」** モデル。Personal → グループ の「共有」は実体的には `pets.group_id` の上書き、つまり **転送 (transfer)** であり、本物の「共有 (share)」ではない。

本提案では `pet_scopes` 中間テーブルを導入して **1 ペット = N グループ** に拡張する。child tables (meal/weight/etc 13 テーブル) は **「Owner scope に物理保存し、subscriber は read-through する」 hybrid モデル**を推奨。同期エンジンは partition key を `(group_id, pet_id)` のタプルに拡張、書き込み権限は per-(pet, group) で表現する。

詳細な決断ポイントは末尾 §「決断ポイント」に集約。総工数見積もりは **20〜25 営業日 (約 1 ヶ月)**、6 Phase 構成、Phase G6 (UI + l10n) のみ並列実行可能。Backend は別リポジトリ (`petlo-api`) のため別途調整が必要。

---

## 1. DB Schema 設計

### 1.1 中核となる新規テーブル `pet_scopes`

```
pet_scopes
─────────────────────────────────────────────────────────────
  id                  INTEGER PK AUTOINCREMENT
  pet_id              INTEGER NOT NULL  → pets.id (CASCADE)
  group_id            TEXT    NOT NULL  -- 'personal' or <uuid>
  permission          TEXT    NOT NULL  -- 'owner'|'editor'|'viewer'
                                         -- pet-scope ローカル権限
                                         -- groups.my_permission とは独立可能
  shared_at           INTEGER NOT NULL  -- UTC msec
  shared_by_user_id   TEXT    NULL      -- 誰がこの scope に共有したか
  is_primary          INTEGER NOT NULL DEFAULT 0  -- §1.5 参照
  sync_status         TEXT    NOT NULL  -- 'pending'|'synced'|'conflict'
  deleted_at          INTEGER NULL      -- 論理削除 (共有解除)
  created_at          INTEGER NOT NULL
  updated_at          INTEGER NOT NULL
  last_modified_at_client INTEGER NULL

  UNIQUE (pet_id, group_id)             -- 同じペットを同じグループに二重共有禁止
  INDEX  (group_id, deleted_at)         -- "このグループのペット一覧" を引く
  INDEX  (pet_id, deleted_at)           -- "このペットがどこにいるか" を引く
  INDEX  (pet_id, is_primary)           -- §1.5 primary lookup
```

**意図**:
- `pet_id × group_id` の N:M を表現する純粋な関連テーブル
- `permission` は **pet 単位で finer-grained** にする (グループ全体は editor だが、このペットだけは viewer、など)。これにより「妻のペットは閲覧だけ許可」のようなユースケースに対応
- `is_primary` は §1.5 参照
- `deleted_at` は「共有解除」を論理削除で表現 → sync で他端末にも届く

### 1.2 既存テーブルへの影響

| テーブル | 方針 | 理由 |
|---|---|---|
| `pets` | **`group_id` を「primary scope」として残す** (§1.5)。物理削除しない。`watchActivePetsInScope(groupId)` 系のクエリは `pet_scopes` 経由に書き換え | 既存ローカルデータの後方互換 + 1 ペットの "本籍" 概念は UI 表現で必要 (例: Owner マーク) |
| `meals` / `poops` / `pees` / `vomits` / `weights` / `temperatures` / `bcs_checks` / `diaries` / `visits` / `vaccinations` / `medications` / `medication_reminders` / `expiration_items` (計 13) | **`group_id` カラムを「primary scope に固定」する** (hybrid モデル、§1.4 参照)。subscriber グループはこのカラムを書き換えない | 13 テーブル × 各 sync 全面書き換えを避ける現実解。bandwidth も最適 |

### 1.3 制約・インデックス・cascade

- **`pets` 物理削除時**: `pet_scopes` も CASCADE で全行削除 (現状 pets は論理削除なので、CASCADE 発火は再インストール時のみ)
- **`pets` 論理削除時 (deleted_at セット)**: `pet_scopes` は不変。subscriber 側からも見えなくなる (read query で `pets.deleted_at IS NULL` を条件に入れる)
- **`groups` 物理削除時**: `pet_scopes.group_id` は FK ではなく TEXT。削除トリガーで `pet_scopes WHERE group_id=X SET deleted_at=now` を発火 (アプリ層 or trigger で実装)
- **共有解除 (`pet_scopes.deleted_at`)**: 該当 group の subscriber は次回 sync で「このペットは見えなくなった」を pull で受け取る (§2 参照)

### 1.4 child tables の扱い — Hybrid モデル推奨

**選択肢比較**:

| 方式 | 特徴 | 評価 |
|---|---|---|
| **(A) 全 child tables に `pet_scopes` と同じ N:M テーブルを** | 厳格、bandwidth 公平 | child × pet_scopes の組み合わせ爆発。**実装コスト×3** |
| **(B) child tables の `group_id` を捨て、pets と pet_scopes だけで scope を解決** | スキーマ純粋 | 全 sync 経路の partition key 再設計必須。pull が `JOIN pets ON pet_id` 必須で重い |
| **(C) Hybrid: child tables の `group_id` は primary scope に固定。subscriber は "Owner scope 経由で pull-through"** | 既存スキーマほぼ流用、bandwidth 公平 (各レコードは 1 回しか流れない) | API がやや複雑 ("見える pets を pet_scopes で解決 → 各 pet の primary scope の records を pull") |

**推奨: (C) Hybrid**。理由:
- 13 テーブルを丸ごと書き換えなくて済む
- 1 件の meal は **物理的に 1 行だけ**保存され、Owner scope に紐づく
- subscriber 側は「自分が見える pets」のリストを `pet_scopes` から引き、各 pet の primary group へ records を pull する
- bandwidth が複数 group 間で重複しない (同じ meal が "妻のグループ用" と "Owner のグループ用" で 2 回流れない)

### 1.5 「Primary scope」を残すか — 推奨: **残す**

| 比較 | Primary 残す案 | 完全フラット案 |
|---|---|---|
| `pets.group_id` の扱い | `primary scope` として残し、書き換え可 | カラム削除、`pet_scopes` のみで scope 表現 |
| Owner 概念 | `pets.group_id == 自グループ` で Owner 判定可 | `pet_scopes.permission == 'owner' AND is_primary == 1` 必要 |
| Migration コスト | 既存データそのまま | 全 pets 行に対し migration 必要 |
| sync engine | Hybrid モデル (§1.4 C) と相性◎ — primary scope を records の "本籍" にできる | child tables の group_id 廃止が必須、全 sync 書き換え |
| UX | 「このペットの本籍は妻のグループ」が表現可能 | 「N 個のグループに均等に存在」フラット |
| Pro 移行時の挙動 | Owner が Pro 解約 → primary scope の groups.status が pendingDeletion → カスケード | 全 scope を巡回して権限再評価が必要 |

**推奨**: Primary scope を残す。ただし `pets.group_id` は内部的に「物理保存の本籍」と再定義し、UI 表現としての "Owner" は `pet_scopes.permission` を見るように責務分離する。

### 1.6 Drift migration コード案 (擬似コード)

```dart
// migrations.dart の onUpgrade 内、v6 でテーブル追加
static const int currentVersion = 6;

if (from < 6) {
  await m.createTable(petScopes);
  await m.createIndex(Index(
    'idx_pet_scopes_group_deleted',
    'CREATE INDEX idx_pet_scopes_group_deleted '
    'ON pet_scopes (group_id, deleted_at)',
  ));
  await m.createIndex(Index(
    'idx_pet_scopes_pet_deleted',
    'CREATE INDEX idx_pet_scopes_pet_deleted '
    'ON pet_scopes (pet_id, deleted_at)',
  ));

  // backfill: 既存 pets を pet_scopes に 1:1 で入れる
  // pets.group_id がそのままどこか 1 group に属する状態を作る
  final pets = await db.select(db.pets).get();
  for (final p in pets) {
    await db.into(db.petScopes).insert(PetScopesCompanion.insert(
      petId: p.id,
      groupId: p.groupId,
      permission: MemberPermission.owner,  // 既存はみな自分が owner だった
      sharedAt: p.createdAt,
      sharedByUserId: const Value(null),    // 既存データは attribution 不明
      isPrimary: const Value(true),         // 既存の group_id を primary に
      syncStatus: SyncStatus.synced,
      createdAt: now(),
      updatedAt: now(),
    ));
  }
}
```

**注意点**:
- backfill は 1 トランザクションで囲む (大量行で OOM の懸念は v1.0 規模なら無視可能)
- migration 失敗時の rollback は drift が自動で扱うが、`pet_scopes` 空でアプリ起動するとペット 0 件に見える。**新スキーマで起動時に pet_scopes 空なら自動 backfill** をフォールバックに置く

---

## 2. Sync Engine リアーキテクチャ設計

### 2.1 現状 (build 42) の partition key

```
sync_queue
─────────────────────────────────
  group_id        ← partition key
  target_table    (例: 'pets', 'meals')
  record_id       (ローカル row id)
  operation       insert|update|delete
  ...

push: POST /sync/push {operations: [{ groupId, ... }, ...]}
pull: GET  /sync/pull?groupId=X&since=Y → 1 グループの差分
```

すべての row は「1 group に属する」前提。`SyncService._pushGroup(groupId)` も `_pullGroup(groupId)` も group 単位の一括処理。

### 2.2 新 partition key (推奨)

**変更内容**: `sync_queue.group_id` は維持しつつ、**意味を再定義** する。

- 既存: 「この row はこのグループ内のもの」
- 新規: 「この op をどのグループのチャネルで配信するか」 (channel id)

**追加カラム**:

```
sync_queue (追記カラム)
─────────────────────────────────
  fanout_group_ids  TEXT NULL  -- pet_scopes 経由で fanout 先がある場合の JSON list
                                -- 例: '["group-a-uuid", "group-b-uuid"]'
```

`pet_scopes` のレコード変更は **複数チャネルに同時 push** する必要があるため、`fanout_group_ids` で代表。または「pet_scopes 専用 op (`target_table=pet_scopes`)」として扱い、サーバ側 fanout に委ねる (=`pet_scopes` への変更は **常に 1 グループ宛で送り、サーバが他 subscriber に伝播**)。

**推奨**: 後者 (server-side fanout)。クライアントは「pet_scopes 行を 1 グループ宛に push」するだけ、サーバが「この pet の他 scope 全員に通知」を担う。

### 2.3 双方向同時編集の競合解決

#### 方式比較

| 方式 | 説明 | petlo 適性 |
|---|---|---|
| **Last-Write-Wins (LWW)** | `clientTimestamp` 比較で新しい方を採用 (現状) | **○** シンプル。petlo の編集頻度なら衝突は稀 |
| **Operational Transform (OT)** | テキスト編集の協調用、文字単位 op | × オーバーキル。petlo は record 単位編集 |
| **CRDT (Vector clocks)** | クロック衝突を解決 | × バンド幅 ✕ 複雑度。同期遅延が許容範囲なら不要 |
| **Field-level merge** | 同じ row でも別フィールドの編集はマージ可能 | △ 中規模 effort。重要 record (medication など) には有効 |

**推奨**: **LWW を主軸 + field-level merge を一部選択的に適用**。
- pets / records: LWW (既存と同じ)
- **`pet_scopes.permission` の変更**: server-side で再解決 (owner が下げた権限が editor の "上書き" で復活しないよう、owner の op を常に優先)

### 2.4 1 レコードが複数 group の sync 対象になる場合の bandwidth 最適化

**Hybrid モデル (§1.4 C) を採用すると、records は依然として primary scope の 1 経路でしか流れない。**

例: Pet X を Personal (primary) → Group A → Group B に共有
- Pet X の meal 1 件追加 → `sync_queue` には primary scope (`group_id='personal'`)... ではなく、推奨は **primary scope が shared なら shared、Personal だけなら local-only**
- ただし Personal が primary の場合、subscriber (A, B) に届かない。**Personal にいる pet を共有した瞬間に primary scope を group A に "promote" する**ルールにすると整合する
- すなわち「最初に共有したグループが primary になる」既定。Owner が引き続き編集可能

**通信量見積もり**:
- 単独保持: 1 record = 1 push
- 2 group 共有 (推奨モデル): 1 record = 1 push (primary), 2 group が pull
- bandwidth は変わらないが、**pull 側の API call が group 数だけ増える** (subscriber が自分の所属各 group に対し /sync/pull)
- 緩和: `/sync/pull?groupIds=A,B,C` で一括化 (要 API 改修)

### 2.5 エッジケース

| ケース | 想定挙動 |
|---|---|
| **権限変更直後のローカル変更** | 旧権限で書いた未送信 op が server で 403 を食らう → reject reason `forbidden` で既存ハンドリング (sync_queue から削除) で対応可 |
| **共有解除直後の subscriber 側残存データ** | サーバから "この pet_scope は deleted" を pull → `pet_scopes.deleted_at` セット → クライアント側 watch クエリで自動的に消える。物理データ (pets / records) は残置 (再共有時に再表示できる) |
| **subscriber 側の records の物理削除** | 自動はしない。**ユーザー操作の "ローカル掃除" メニュー (developer settings に追加検討)** で対応 |
| **primary scope (Owner) がグループから脱退** | "孤児 pet" 発生。**自動 promotion ルール**: 他に共有先があれば最古の共有先を primary に昇格、なければ Personal に戻す |
| **同時に同じ pet を別 group に共有** | server-side で `UNIQUE(pet_id, group_id)` 制約により後勝ち or 既存返却 (冪等) |
| **subscriber が editor から viewer に降格された直後の編集** | クライアントローカル変更は許可 → push 時 403 → 該当 op を捨てる + ユーザー通知 |

---

## 3. Backend (petlo-api) API 設計

> **2026-05-26 訂正 (改訂 2)**: Phase G3-A〜G3-D 完了に伴い、本セクションを実装結果に整合させた。
> 実装は**仕様レポート §1 の中間テーブル設計通り**で、`pet_scopes` テーブルをサーバ側に新規 CREATE し、既存 `shared_pets` には DDL 変更を加えない構成 (migration `0004_pet_scopes.sql`)。
>
> サーバ側における 2 テーブルの役割分担:
> - **`shared_pets`** (pre-G3 から存在): `client_pet_id` ↔ `pet_server_id` のマッピング保持。DDL 変更ゼロ
> - **`pet_scopes`** (G3-A 新設): 仕様 §1 通りの中間テーブル。scope / permission / primary 識別の source of truth
>
> 旧 spec 草案からの実装差分:
> - **pet 識別**: server 側は `client_pet_id` (= Flutter の pet ローカル int PK) を保持し、既存 `shared_pets` 経由で `pet_server_id` に解決する非対称 ID マッピングを採用 (`pet_scopes` 側は `pet_id = pet_server_id` のみ参照)
> - **クエリ設計**: 主スコープ (Owner 視点) と subscriber スコープで CTE 構造を**非対称**にする (`deleted_at` フィルタの位置を変える)
> - **認可**: AND 条件案 → 「`pet_scopes.permission` が `group_members.permission` を上書き」方式に確定

### 3.1 既存エンドポイントの変更

#### `/sync/pull` レスポンス形式拡張

```jsonc
// 旧 (build 42)
{
  "pets": [{ "clientPetId": 1, "payload": {...}, "deletedAt": null }],
  "records": [{ "clientRecordId": 5, "tableName": "meals", "payload": {...} }],
  "nextSince": 1234567890
}

// 新 (build 44+ / G3-B 実装済)
{
  "pets": [...],          // 互換維持。primary scope の pets を返す
  "records": [...],       // 互換維持。primary scope の records を返す
  "petScopes": [          // 新規: このグループに共有された pet_scopes イベント
    {
      "clientScopeId": 12,            // Flutter 側 pet_scopes.id (ローカル int PK)
      "clientPetId": 42,              // Flutter 側 pets.id (ローカル int PK)
      "petServerId": "uuid",          // サーバ pets.id (TEXT UUID)
      "groupId": "<このリクエストのグループ>",
      "permission": "editor",
      "sharedAt": 1700000000000,
      "sharedByUserId": "user-uuid",
      "isPrimary": false,
      "deletedAt": null,
      "payload": {...}                // pet_scopes 行の column dump (snake_case)
    }
  ],
  "nextSince": 1234567890
}
```

#### `/sync/push` op 形式拡張

新規 entity type を追加 (G3-B 実装済、build 44 クライアントが送出する形式):
```jsonc
{
  "opId": "uuid-v4",
  "type": "update" | "delete",        // 現状 create は使わず update に統一
  "entityType": "pet_scope",
  "groupId": "<chan = scope の group_id>",
  "clientEntityId": 12,               // Flutter 側 pet_scopes.id (ローカル int PK)
  "petClientId": 42,                  // Flutter 側 pets.id (ローカル int PK)
  "payload": {                        // create/update のみ。snake_case
    "id": 12,
    "pet_id": 42,
    "group_id": "<chan>",
    "permission": "editor",           // lowercase enum name
    "is_primary": 0,                  // integer 0/1
    "shared_at": 1748168400000,
    "shared_by_user_id": "user-uuid",
    "sync_status": "pending",
    "deleted_at": null,
    "created_at": 1748168400000,
    "updated_at": 1748168400500,
    "last_modified_at_client": 1748168400500
  },
  "clientTimestamp": 1748168400500
}
```

**サーバ側 fanout**: `pet_scope` op を受け取ったら、該当 pet の他 subscriber 全員に同イベントを配信 (`fanout queue`)。G3-B で実装済。

#### client int → server uuid 解決ロジック

クライアントは Flutter ローカルの `int` PK (drift autoIncrement) で pet を識別する。サーバは UUID。両者をつなぐのは **pre-G3 から既存の `shared_pets` テーブル** (G3 で DDL 変更なし、本来の用途で引き続き使用):

```
shared_pets  (pre-G3 から存在、G3-A で DDL 変更なし)
─────────────────────────────────────
  id              TEXT PK            -- server-generated UUID
  pet_server_id   TEXT NOT NULL      -- pets(id), サーバ UUID
  client_pet_id   INTEGER NOT NULL   -- ★ Flutter 側の pet ローカル PK
  client_user_id  TEXT NOT NULL      -- アップロードしたユーザー (誰の client_pet_id か)
  group_id        TEXT NOT NULL      -- アップロード時の所属 group (rev5.3 時代の意味)
  created_at, updated_at, ...
  UNIQUE (client_user_id, client_pet_id, group_id)   -- ユーザー毎に client_pet_id がユニーク
```

push 受信時の解決手順 (G3-B 実装):
1. op の `petClientId` + 認証ユーザー ID で `shared_pets WHERE client_user_id=? AND client_pet_id=?` を検索
2. 既存があれば `pet_server_id` を取得
3. なければ「未知の pet → reject `pet_not_found`」(既存ハンドラ通り `_bumpAttempts` で retry 待機)

> **重要**: scope / permission の semantics は `shared_pets` ではなく **新設の `pet_scopes` テーブル** (§3.4) が持つ。`shared_pets` は引き続き client_pet_id ↔ pet_server_id の橋渡しに専念する役割分担。

### 3.2 新規エンドポイント (G3-D 実装済)

| Method | Path | 用途 | 備考 |
|---|---|---|---|
| `POST` | `/pets/{petServerId}/shares` | ペットを別グループに共有 (新 pet_scopes 行作成) | body に target group_id + permission |
| `DELETE` | `/pets/{petServerId}/shares/{groupId}` | 共有解除 (pet_scopes.deleted_at セット) | primary scope の削除は 409 |
| `PATCH` | `/pets/{petServerId}/shares/{groupId}` | per-pet 権限変更 | body: `{"permission":"viewer"}` |
| `GET` | `/pets/{petServerId}/shares` | 共有状況一覧 (UI 表示用) | 認証ユーザーが scope に含まれる場合のみ 200 |

`/sync/push` 経由の `pet_scope` op と REST endpoint は最終的に**同じ pet_scopes 行**を作成する。UI 側は「即時応答が欲しいフロー」(共有先選択モーダル等) で REST を使う。

### 3.3 認可ロジック (G3-D 実装済)

**確定**: per-(pet, group) の細粒度権限を `pet_scopes.permission` で表現し、`group_members.permission` を**上書き**する (Decision Log #4)。

評価順序:
1. ユーザーが対象 group のメンバーか? (`group_members` に行がある)
2. yes なら `pet_scopes WHERE pet_id=? AND group_id=? AND deleted_at IS NULL` を引く
3. pet_scopes 行があれば `pet_scopes.permission` を採用 (上書き)
4. pet_scopes 行がなければ → そもそも pet がこの group から見えない → 403 / 404

「Pro チェック」は **自然な gate** で実現: 無料ユーザーは group 作成自体ができない (既存 `/groups POST` で Pro チェック) ため、`/pets/{id}/shares` を叩こうにも target group がそもそも存在しない (= 自然に共有不可)。専用 Pro check を追加せず、既存ゲートを再利用する。Decision Log #5 の "1 グループまで無料" は **クライアント側 UI で表示制御**するのみ。

### 3.4 D1 schema (G3-A 実装済)

**仕様レポート §1 の中間テーブル設計通り、新規 `pet_scopes` テーブルを CREATE** した (migration `0004_pet_scopes.sql`)。既存 `shared_pets` テーブルには**DDL 変更を加えていない** (client_pet_id ↔ pet_server_id マッピングの本来の用途で引き続き使用)。

```sql
-- migrations/0004_pet_scopes.sql (G3-A)
CREATE TABLE IF NOT EXISTS pet_scopes (
  id              TEXT PRIMARY KEY,        -- server-generated UUID
  pet_id          TEXT NOT NULL,           -- = pets.id (server UUID)
  group_id        TEXT NOT NULL,           -- = groups.id
  permission      TEXT NOT NULL CHECK (permission IN ('owner','editor','viewer')),
  is_primary      INTEGER NOT NULL DEFAULT 0,
  shared_at       INTEGER NOT NULL,
  shared_by_user_id TEXT,                  -- = users.id (誰が共有したか)
  deleted_at      INTEGER,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  UNIQUE (pet_id, group_id),               -- 同 (pet, group) の二重共有禁止
  FOREIGN KEY (pet_id)   REFERENCES pets(id),
  FOREIGN KEY (group_id) REFERENCES groups(id)
);

CREATE INDEX idx_pet_scopes_group   ON pet_scopes (group_id, deleted_at);
CREATE INDEX idx_pet_scopes_pet     ON pet_scopes (pet_id, deleted_at);
CREATE INDEX idx_pet_scopes_primary ON pet_scopes (pet_id, is_primary);
```

**backfill** (同 migration 内):
既存 `shared_pets` 行 (rev5.3 時代の「1 ペット = 1 group」運用の名残) を 1:1 で `pet_scopes` へ流し込む:
```sql
INSERT INTO pet_scopes
  (id, pet_id, group_id, permission, is_primary, shared_at,
   shared_by_user_id, created_at, updated_at)
SELECT
  hex(randomblob(16)),   -- 新 UUID
  sp.pet_server_id,
  sp.group_id,
  'owner',               -- 既存共有はみな Owner だった
  1,                     -- 全て primary 扱い (multi-scope 化以前)
  sp.created_at,         -- shared_at = 元の作成時刻
  sp.client_user_id,     -- 共有者 = upload した本人
  sp.created_at,
  sp.updated_at
FROM shared_pets sp;
```
backfill 後、Owner-only / single-scope の旧来挙動が `pet_scopes` 1 行ずつで表現される (= クライアント側 G1 backfill と完全に対称)。

#### 主スコープ / subscriber スコープの CTE 非対称設計

`/sync/pull` の records 抽出 SQL は **主スコープ (Owner) と subscriber で構造が違う**。これは spec 段階の「全 group 同じ CTE」想定から G3-C で意図的に乖離した部分:

```sql
-- (G3-C 実装) 主スコープ向け records 取得
WITH visible_pets AS (
  SELECT id FROM pets
  WHERE group_id = ?              -- 主スコープのペット
  -- ★ deleted_at フィルタなし。Owner には削除済みも見せて undo を許す
)
SELECT * FROM meals
WHERE pet_id IN (SELECT id FROM visible_pets)
  AND updated_at > ?
  AND deleted_at IS NULL;         -- record 自体の deleted は除外

-- (G3-C 実装) subscriber スコープ向け records 取得 (非対称)
WITH visible_pets AS (
  SELECT pet_id AS id FROM pet_scopes
  WHERE group_id = ?
    AND deleted_at IS NULL         -- ★ subscriber は削除済み scope を見ない
)
SELECT * FROM meals
WHERE pet_id IN (SELECT id FROM visible_pets)
  AND updated_at > ?
  AND deleted_at IS NULL;
```

**乖離の意図**: Owner は「うっかり削除した pet を発見して復活させる」UX を後で実装可能にしておくため、deleted_at フィルタを CTE から外す。subscriber は「Owner が共有解除した」という決定を即座に反映するため、deleted scope を厳密に除外する。Decision Log にも追記 (§Decision Log #8)。

### 3.5 後方互換性

**確定**: `/v1` ルートを別途切らず、既存パスを **拡張する**形で対応 (G3 全体方針)。理由:
- 現状 production user 0、TestFlight テスター ~10 名のみ
- 旧形式の op (build 42 以前) は `entityType` が `pet`/`record` のみで、新しい backend でも従来通り処理される (後方互換性が自動的に保たれる)
- `/v2` 並走の実装コストを払う割に得るものがない

**version gating の取扱**: クライアントの強制アップデート機構は **v1.0 段階では入れず、v1.1 公開リリース時に再検討** (Phase G3-F として spec 段階に書いた予定を v1.1 に送り)。理由: TestFlight 内では運用 (Slack で「アップデートしてね」と告知) で吸収可能。

---

## 4. UI 改修箇所の全洗い出し

### 4.1 共有先選択 UI (新設)

現在の `pet_share_picker.dart` は 「Personal → 1 グループへの転送」 専用。これを**「複数共有先選択 + per-pet 権限指定」** UI に進化。

```
┌─ Share "Taro" ──────────────────────┐
│                                      │
│  Currently shared with:              │
│   ✓ Personal              [Owner ▼] │  -- primary marker
│   ✓ お父さん家族         [Editor ▼] │
│   □ ご近所ペットの会     [   −    ] │  -- 未共有
│   □ 動物病院グループ     [   −    ] │
│                                      │
│  [Done]                              │
└─────────────────────────────────────┘
```

- チェック切替 = 共有 / 解除
- ドロップダウン = pet-scope 単位の permission
- "Primary" バッジ + transfer 動作 (タップで切替)

### 4.2 各画面で「scope を意識した表示」がどう変わるか

| 画面 | 現状 | 新仕様 |
|---|---|---|
| **Home** | currentGroupId の pets を表示 | currentGroupId に**共有された** pets を `pet_scopes` 経由で表示 |
| **みまもる (health)** | pet 選択 → そのペットの records | 同左 (records は primary 経由で pull 済み) |
| **よてい (plans)** | pet × group の schedules | 同左、ただし pet が見える根拠は `pet_scopes` |
| **きろく (life)** | 同上 | 同上 |
| **AI 相談** | pet を選んで AI 文脈生成 | 同上、ただし `viewer` 権限なら send 不可表示 |

### 4.3 レコード作成時の scope 選択

**選択肢**:
- (A) 自動 (現在の currentGroupId 経由) — UX シンプル
- (B) 明示選択 (毎回モーダル) — UX 重い

**推奨**: (A)。記録は「いま見ているグループ」に紐づく既存挙動を維持。共有された pet の record も "見ているグループ" 経由で記録 → 内部的には primary scope に保存 (Hybrid §1.4 C)。

### 4.4 Switch group モーダル (既知バグも同時修正)

- `group_switcher_modal.dart:203` の `'1 pet · only on this device'` ハードコードを **`pet_scopes` 経由の実数カウント**に置換
- `:212` の `'editor · last active'` も同様にメンバー数を実数化
- l10n キー追加: `group_switcher_pet_count(count)`, `group_switcher_member_count(count)`, `group_switcher_last_active(timestamp)`

### 4.5 ARB / l10n 影響

**現在の ARB 名前空間 (`pet_form_scope_*`, `pet_share_picker_*`) の「移動 (move)」表現を「共有 (share)」に再定義**:

| 既存キー | 旧意味 | 新意味 |
|---|---|---|
| `pet_form_scope_move_to_group_title` | 「{label} へ共有」 (実体は転送) | そのまま「{label} へ共有」(実体も共有に) |
| `pet_form_scope_move_to_personal_title` | 「Personal へ戻す」 | 「Personal から共有解除」or 「Personal を選択」 |
| `pet_share_picker_confirm_body` | 「{petName} をこのグループに共有しますか? 記録もまとめて移動」 | 「移動」を削除、「共有」のみに修正 |

加えて **新規追加** が必要なキー (3 言語):

| 新規キー | ja / en / zh |
|---|---|
| `pet_share_picker_currently_shared_with` | 共有中のグループ / Currently shared with / 当前共享至 |
| `pet_share_picker_make_primary` | プライマリに設定 / Make primary / 设为主要 |
| `pet_share_picker_permission_owner/editor/viewer` | (既存 MemberPermission ラベルがあれば再利用) |
| `pet_share_picker_unshare_confirm` | このグループから共有を解除しますか? / Stop sharing with this group? / 停止与该群组共享? |
| `group_switcher_pet_count` | {count} 匹のペット / {count} pets / {count} 只宠物 |
| `group_switcher_member_count` | {count} 人のメンバー / {count} members / {count} 位成员 |

### 4.6 Pro 機能境界線の見直し

**現状**: Pro = グループ作成 + AI 相談 + (将来) クラウドバックアップ

**新提案 (案 A — 推奨)**:
| 機能 | 無料 | Pro |
|---|---|---|
| グループ作成 (オーナー) | × | ✓ (現状維持) |
| グループ参加 | ✓ | ✓ |
| **1 ペットを複数グループに共有** | **× (1 グループまで)** | **✓ (制限なし、推奨上限 3)** |

理由: 「1 ペットを複数グループ」は明確に Pro 訴求できる機能。無料は「1 ペット = 1 group_id」の現状互換を維持し、Pro でアンロック。

**新提案 (案 B)**: 共有数 N 制限なく無料開放。Pro 訴求はクラウドバックアップ + AI で十分。
- 利点: UX 摩擦無し、複数共有のネットワーク効果 (家族が petlo を使い始める起点)
- 欠点: Pro 訴求が弱まる

**推奨: 案 A**。ただし境界線は事業判断要素なので最終決定は別途。

---

## 5. Migration Strategy

### 5.1 既存 build 42 ローカルデータの変換手順

1. drift schema v5 → v6 アップグレード時に `pet_scopes` テーブル作成
2. 既存 pets を全件 scan、各 pet について 1 つだけ `pet_scopes (pet_id, group_id=pets.group_id, permission='owner', is_primary=1)` を挿入
3. 既存の `pets.group_id` は維持 (primary scope を示す)
4. 既存の `child_tables.group_id` は維持 (現状動作と同じ)

**ロジック上、ユーザーは変化を感じない** (1 ペット = 1 scope のままの状態が `pet_scopes` 1 行で表現される)

### 5.2 Backend D1 既存データ変換

- D1 migration script: 全 pets を scan、`pet_scopes` に backfill
- backfill は trace 化、エラーは個別記録 (1 ペット失敗で全体停止しない)
- 完了確認: `SELECT COUNT(*) FROM pets WHERE NOT EXISTS (SELECT 1 FROM pet_scopes WHERE pet_server_id = pets.id)` = 0 を assertion

### 5.3 Test 環境でのリハーサル手順

1. local Wrangler で D1 を一旦 v1.0 schema に戻す
2. seed data (テスト用 pets + groups) を投入
3. v2 migration スクリプトを流す
4. assertion クエリで全件 backfill 確認
5. クライアント側 (Flutter) も同様に v5 → v6 で起動 → pet 表示が変わらないことを目視

### 5.4 Rollback 戦略

- DB schema rollback はサポートしない (drift も sqlite も downgrade 非対応)
- 代替: **`pet_scopes` テーブルだけ無視する旧ロジックパス**を残しておく feature flag を `app_constants.dart` に置く (`bool enableMultiScope = true;`)
- 致命的 bug 発覚時はサーバ側で feature flag を false に倒し、旧経路 (`pets.group_id` 直読み) に強制 fallback

### 5.5 既存 TestFlight ユーザー (作者 + 家族テスター) のデータ取り扱い

- TestFlight build 上限 ~10 ユーザーと仮定
- migration バグで data loss するリスクが最大
- **build 43 アップロード前**にローカル sqlite を全員 export → S3 にバックアップ (developer settings に「DB エクスポート」メニューを Phase G1 で追加)
- migration 後の検証は **作者本人が dogfood で 1 週間** → 家族テスターへ展開

---

## 6. Phase 段階分け + 見積もり + 依存関係

### Phase G1: ローカル DB 拡張 + backfill (4 日)
- [G1-1] `pet_scopes` drift table 追加, migrations v5→v6 backfill (1.5 日)
- [G1-2] `pet_scopes_repository.dart` 新設 + read/watch メソッド (1.5 日)
- [G1-3] developer_settings に「DB エクスポート」メニュー追加 (1 日、テスター用安全網)
- **完了基準**: 起動して既存 pets が pet_scopes に backfill されていること。既存画面の動作が変化していないこと

### Phase G2: クライアント read 経路を pet_scopes 経由化 (3 日)
- [G2-1] `watchActivePetsInScope(groupId)` を `JOIN pet_scopes ON ...` に書き換え (1 日)
- [G2-2] `currentGroupPetsProvider` + 派生 providers 再評価ロジック (1 日)
- [G2-3] 既存テスト全件再パス確認 (1 日)
- **完了基準**: pet が pet_scopes 経由で表示される。read 経路の動作が build 42 と等価
- **並行可**: G3 と並行可能

> **2026-05-26 訂正**: Phase G1〜G3 完了に伴い実績ベースで全面更新。当初の G3 (Flutter sync 拡張) / G4 (Backend) を ✅ 完了扱いに、G3-E (schedules) / G3-F (version gating) を v1.1 へ移送、UI 改修 (旧 G6) を **Phase G4 として次フェーズに昇格**。

### ✅ Phase G1: ローカル DB 拡張 + backfill (build 43, 完了)
- [G1-1] `pet_scopes` drift table 追加, migrations v5→v6 backfill ✅
- [G1-2] `pet_scopes_repository.dart` 新設 + read/watch メソッド ✅
- [G1-3] developer_settings に「DB エクスポート」メニュー追加 (テスター用安全網) ⏸ 据え置き (build 43 では未着手、必要なら build 47+ で追加)
- **完了基準**: 起動して既存 pets が pet_scopes に backfill されていること。既存画面の動作が変化していないこと → ✅

### ✅ Phase G2: クライアント sync engine 拡張 + read 経路 multi-scope 化 (build 44, 完了)
当初の G2 (read 経路書換) と G3 (sync engine 拡張) を **build 44 で同時に完了**した。
- [G2-1] `watchActivePetsInScope(groupId)` を `pet_scopes` subquery JOIN に書き換え ✅
- [G2-2] `hasPetWithName` も pet_scopes 経由で multi-scope 対応 ✅
- [G2-3] `medication_reminders_repository.watchEnabledForGroup` を Hybrid 化 ✅
- [G2-4] `createPet` / `movePetToGroup` が primary `pet_scopes` 行を同期維持 ✅
- [G2-5] `sync_queue` の `entityType='pet_scope'` op 送出 ✅
- [G2-6] pull `petScopes` フィールド受信 + `_applyPetScopeEvent` ✅
- [G2-7] LWW 競合解決 (`_isPayloadFresher`) ✅
- **完了基準**: pet が pet_scopes 経由で表示され、subscriber view が動く → ✅ (15/15 tests pass)

### ✅ Phase G3-A〜G3-D: Backend API 改修 (petlo-api セッション, 完了)
別リポジトリ (`petlo-api`) で並走実装。Worker Version ID は本リポジトリでは追跡せず、petlo-api 側の commit log を参照する (本 doc では実装事実のみ記録)。
- [G3-A] D1 schema: 仕様 §1 通り `pet_scopes` テーブルを新規 CREATE (`migrations/0004_pet_scopes.sql`) + インデックス 3 本 (`idx_pet_scopes_group` / `_pet` / `_primary`) + `UNIQUE(pet_id, group_id)` + 既存 `shared_pets` を 1:1 で primary scope として backfill。既存 `shared_pets` には DDL 変更ゼロ ✅
- [G3-B] `/sync/push` `pet_scope` op 受信 + client int → server uuid 解決 (既存 `shared_pets` 経由) + server-side fanout ✅
- [G3-C] `/sync/pull` `petScopes` フィールド emit + **主スコープ/subscriber 非対称 CTE 設計** (§3.4 参照) ✅
- [G3-D] 新規 REST endpoint 4 本 (`POST/DELETE/PATCH/GET /pets/{petServerId}/shares`) + 認可ロジック (`pet_scopes.permission` が `group_members.permission` を上書き) ✅
- **完了基準**: backend test で multi-scope shared pet が複数 group の `/sync/pull` で見える → ✅

### ⏸ Phase G3-E: schedules の Hybrid 対応 → **v1.1 送り**
- 当初: schedules.watchForGroup を `pet_id IN (SELECT pet_id FROM pet_scopes …)` 相当へ
- **送り理由**: backend D1 に `schedules` テーブルが現在存在せず、新規設計が必要。client 側の `relatedPetIds` が JSON list である件と合わせて、3〜5 日の独立タスクになる
- **再評価タイミング**: schedules 機能の backend 化を進める時 (= cloud sync 本実装フェーズ)。L1 (クラウドバックアップ) とまとめて扱う候補

### ⏸ Phase G3-F: client version gating → **v1.1 送り**
- 当初: `/v1` 廃止 + 強制アップデートダイアログ
- **送り理由**: backend には `/v1` 専用ルートが存在せず、既存パスの拡張で後方互換が保たれている (旧形式 op も問題なく処理される)。TestFlight ~10 名は Slack 等の運用告知で吸収できる
- **再評価タイミング**: v1.1 公開リリース時 (App Store 配信開始 = 古いクライアントが残るリスクが顕在化する瞬間)

### 🔜 Phase G4: UI 改修 (multi-scope 表面化) — 次フェーズ
旧 spec の G6 に相当。Phase G1〜G3 で **データ層・同期層は揃った**ため、ユーザー体験として multi-scope を表に出すフェーズ。
- [G4-1] `pet_share_picker.dart` を multi-select + per-pet permission ドロップダウン UI に改修
  - 「現在の共有先」「未共有グループ」「primary バッジ」「Owner/Editor/Viewer 選択」表示
  - `GET /pets/{petServerId}/shares` で初期表示、トグル変更で REST endpoint 即時呼び出し
- [G4-2] `group_switcher_modal.dart:203` のハードコード `'1 pet · only on this device'` バグを修正
  - 各行で `petsInScopeProvider(groupId)` を `ConsumerWidget` 化して実数表示
  - メンバー数 (`group_members` 件数) も同様に実数化
- [G4-3] ARB / l10n 改修
  - 既存 `pet_form_scope_move_*` / `pet_share_picker_move_*` 系の「移動 (move)」表現を「共有 (share)」概念に統一
  - 新規キー (3 言語): 「共有中のグループ」「プライマリに設定」「共有を解除」等
  - 詳細は §4.5 参照
- [G4-4] Phase G4 の UI 変更を前提に、`movePetToGroup` の callers を **`PetScopesRepository.addPetScope` / `removePetScope`** に置き換える (旧 movePetToGroup は backward compat のため残存)
- **完了基準**: UI から複数共有・共有解除・per-pet 権限変更が完結する。Switch group モーダルが実数表示する
- **見積もり**: 4-5 日 (G4-1 = 1.5 日, G4-2 = 1 日, G4-3 = 1.5 日, G4-4 = 1 日)

### 🔜 Phase G5: 結合テスト + 競合解決検証 (G4 完了後)
- [G5-1] 2 端末 (シミュレータ + 実機) で同時編集テスト (1 日)
- [G5-2] 権限変更直後の race condition 検証 (1 日)
- [G5-3] グループ脱退時の orphan handling 検証 (1 日)
- **完了基準**: 競合シナリオ 5 種 (権限降格 / 同時編集 / 脱退 / 共有解除 / primary 変更) が定義通り動作

### 🔜 Phase G6: Pro 境界 UI + ロールアウト (G5 完了後)
- [G6-1] Pro 機能境界の UI 反映 (無料ユーザーは 2 つ目以降のグループ共有時にアップセル) (1 日)
  - server 側は既に「無料 = group 作成不可」で自然 gate されているため、UI 表示制御のみ
- [G6-2] TestFlight 配信、テスター運用 (1 日)
- **完了基準**: Pro 課金状態で multi-scope が解除される。無料で 2 つ目共有時にアップセル UI が出る

### 残り見積もり (build 44 以降): **8〜10 営業日**
- G4 (UI 改修): 4-5 日
- G5 (結合テスト): 3 日
- G6 (Pro 境界 + ロールアウト): 2 日

### 完了済 / 残作業の依存関係グラフ

```
✅ G1 → ✅ G2 ──┐
                ├─ 🔜 G5 → 🔜 G6
✅ G3-A〜D ─────┤    🔜 G4 (G5 と部分並行可)
⏸ G3-E (v1.1)
⏸ G3-F (v1.1)
```

---

## 7. リスク分析

| リスク | 緩和策 |
|---|---|
| **データ整合性 (migration 失敗で pets が表示されない)** | (1) developer settings で DB エクスポート機能 (G1-3) (2) v6 起動時に pet_scopes 空なら backfill 再実行 (3) feature flag で旧経路 fallback (5.4) |
| **同期性能 (subscriber 端末で N グループ × pull 増加)** | (1) `/sync/pull?groupIds=A,B,C` で複数グループ一括 pull (将来) (2) フォアグラウンド polling 2 min は維持、増えるのは pull の per-batch 件数のみ |
| **UX 複雑化 (「共有」と「移動」の混同)** | (1) ARB 名前空間統一 (4.5) (2) `pet_share_picker` を multi-select UI に進化させ「共有先一覧」を常時可視化 |
| **競合解決の見落としケース** | G5 で 5 シナリオを意図的にテスト。CI に並行編集の widget test を追加 |
| **Backend fanout のスループット** | Cloudflare Workers の D1 sub-request 6 件制限を超えないよう、`pet_scopes` の subscriber list は事前 cache (1 リクエスト = 1 fanout 完結) |
| **TestFlight テスター環境破壊** | dogfood 期間 1 週間、エクスポートデータからの復元手順を事前確立 |
| **Test カバレッジ手薄になりがちな箇所** | `pet_scopes` の sync edge cases (権限変更 + 削除のレース、primary 変更時の records 帰属) を unit test で coverage 必須 |

---

## 8. やらないこと (Out-of-Scope)

### v1.0 では実装しない
- multi-scope 全体 (本ドキュメントの内容そのものを v1.0 ではやらない)
- 共有解除時の subscriber 側 records 物理削除 (孤児として残置、容量影響は軽微)

### v1.1 候補 (今回の multi-scope と独立)
- L1: クラウドバックアップ本実装 (`backup_settings_screen.dart` の disclaimer 通り)
- L2: Sign in with Apple
- L3: Push 通知 + background fetch
- L4: 課金検証の Android 対応

### v1.1 へ送った multi-scope 関連項目 (2026-05-26 追記)
- **G3-E** schedules の Hybrid 化 — backend に `schedules` テーブル無し、新規設計必要。L1 (クラウドバックアップ本実装) とセットで再評価
- **G3-F** クライアント version gating (`/v1` 廃止 + 強制アップデート) — TestFlight 段階では運用告知で吸収可能、App Store 公開時に再評価

### v1.2 以降 (multi-scope の発展)
- `/sync/pull?groupIds=A,B,C` 一括 pull API
- 共有招待のリアルタイム通知 (Push)
- 共有相手リストの "lifetime activity" 集計 (誰が最終編集したか UI)

### 永続的にやらない
- CRDT / OT 風の field-level real-time co-editing (petlo の編集頻度では過剰)
- 共有 pet の history (revision) 保存 (record の作成者 `createdBy` で足る)

---

## 決断ポイント

実装着手前に承認が必要な判断 (順序は判断重要度 desc):

| # | 決断 | 推奨 | 代替案 |
|---|---|---|---|
| 1 | child tables を完全 fork するか、primary scope に固定するか (§1.4) | **Hybrid: primary 固定 + subscriber pull-through** | 完全 fork (記録ごとに per-group コピー) |
| 2 | `pets.group_id` を残すか廃止するか (§1.5) | **残す (primary scope = 物理本籍として再定義)** | 廃止 (`pet_scopes` のみで scope 表現) |
| 3 | 競合解決アルゴリズム (§2.3) | **LWW 主軸 + pet_scopes.permission のみ server-side rule** | field-level merge を records にも適用 |
| 4 | per-pet 権限 (`pet_scopes.permission`) はグループ権限を上書きか継承か (§3.3) | **上書き (per-pet が優先)** | AND 条件 (両方を満たす必要) |
| 5 | Pro 機能境界 (§4.6) | **案 A: 1 ペットを複数共有するのは Pro 限定** | 案 B: 完全無料、Pro 訴求は他機能 |
| 6 | バックエンド `/v1` 廃止 vs `/v2` 並走 (§3.5) | **`/v1` 廃止 + 強制アップデート** (TestFlight 内テスター数 ~10) | `/v2` 並走 (実装コスト微増だが rollback 安全) |
| 7 | 共有解除時の subscriber records 物理削除 | **やらない (orphan として残置)** | "孤児掃除" メニューを developer settings に追加 |

---

## 全体見積もり所感

ユーザー spec で「1 ヶ月+ が妥当か」とあったが、調査の結果:

- **20〜25 営業日 (約 1 ヶ月)** が現実的な見積もり
- Phase G3 / G4 は別実装者 (Flutter / Backend) が並走できれば **18 営業日**まで圧縮可能
- ただし、**「multi-scope だけ」では UX 完結しないため、関連する Pro 課金 UI、共有招待フロー、l10n まで含めると更に +5 日**
- **トータル: 1 ヶ月 ~ 1.5 ヶ月**

petlo の現状コードは pet × group の N:M 化を想定して書かれていない (`watchActivePetsInScope` の where 条件、`sync_queue` の partition key、`movePetToGroup` の atomicity 保証など)。リファクタ範囲は中程度だが、**migration とテストに最も時間を要する** と判断。

承認後、Phase G1 から着手可能。

---

## Decision Log

仕様承認時に確定した 7 決断 (§「決断ポイント」の最終結論)。各項目は確定日 + 採用案 + 根拠1行で記録する。Phase G* 実装時はこの Decision Log を起点に着手する。

| # | 確定日 | 決断 | 採用案 | 根拠 |
|---|---|---|---|---|
| 1 | 2026-05-25 | child tables を完全 fork するか primary 固定か | **Hybrid: primary 固定 + subscriber pull-through** | 13 テーブル × 全 sync 経路の書き換えを回避しつつ、bandwidth は records 1 行 = 1 push の現行効率を維持できる |
| 2 | 2026-05-25 | `pets.group_id` を残すか廃止するか | **残す (primary scope = 物理本籍として再定義)** | 既存ローカルデータの後方互換を担保、Owner / primary バッジ等の UI 表現が `pets.group_id == pet_scopes.group_id` の単純比較で済む |
| 3 | 2026-05-25 | 双方向同時編集の競合解決アルゴリズム | **LWW 主軸 + `pet_scopes.permission` のみ server-side rule** | petlo の record 編集頻度は低く LWW で十分。permission の race だけ owner-優先 server rule で昇格/降格レースを潰す |
| 4 | 2026-05-25 | per-pet 権限はグループ権限を上書きか継承か | **上書き (per-pet が優先)** | 「妻のグループでは Editor だがこのペットだけ Viewer」のような細粒度 UX を素直に表現でき、認可ロジックも 1 段で済む |
| 5 | 2026-05-25 | 複数共有の Pro 機能境界線 | **複数共有は Pro 限定** | 既存「グループ機能 = Pro」の自然な拡張。3 グループ × 5 人の上限内で複数共有可、無料は「最初に共有した 1 グループ」までという段階アップセル UX |
| 6 | 2026-05-25 | Backend `/v1` 廃止 vs `/v2` 並走 | **`/v1` 廃止 + 強制アップデート** | TestFlight 内部テスター ~10 名のみで production user 0。並走を維持する実装コストの方が高い |
| 7 | 2026-05-25 | 共有解除時の subscriber 側 records 物理削除 | **やらない (orphan として残置)** | 容量影響は軽微。再共有時にローカル row 再利用できる利点が削除の煩雑さを上回る。掃除メニューは developer settings 案件で別途検討 |
| 8 | 2026-05-26 | サーバ side `/sync/pull` records 抽出 CTE は主スコープ / subscriber で対称か非対称か | **非対称: 主スコープは `deleted_at` フィルタ無し、subscriber は `deleted_at IS NULL` を必須** | Owner は「うっかり削除を後で復元する UX」を将来実装可能にするため deleted も含めて見せる。subscriber は Owner の共有解除を即座に反映するため厳密フィルタ。G3-C 実装時に確定 (spec 段階の "全 group 同じ CTE" 想定から意図的に乖離) |
| 9 | 2026-05-26 | Pro チェックを multi-scope 専用に追加するか、既存の「group 作成 = Pro」ゲートで足りるか | **既存ゲート (= natural gate) で十分** | 無料ユーザーは group 自体を作れないので、`/pets/{id}/shares` を叩こうにも target group が存在しない。専用 check を増やさず実装シンプル化。クライアント側 UI で「2 つ目以降の共有時にアップセル」を表示するのみ。G3-D 実装時に確定 |

### G1〜G3 実装結果サマリ (2026-05-26 追記)

| Phase | 完了 build / セッション | 主要成果物 | 備考 |
|---|---|---|---|
| G1 | build 43 (Flutter) | drift `pet_scopes` テーブル + migration v5→v6 + backfill + `PetScopesRepository` + 13 tests | 既存ユーザー視点で挙動変化なし |
| G2 | build 44 (Flutter) | read 経路 multi-scope JOIN 化 + sync engine 'pet_scope' op + LWW + 15 new tests | UI 表面化はまだ |
| G3-A | petlo-api セッション (Worker `e28cee6b...`) | D1 `pet_scopes` テーブル新規 CREATE (仕様 §1 通り) + インデックス 3 本 + UNIQUE + 既存 `shared_pets` から 1:1 primary scope backfill。`shared_pets` 自体は DDL 変更なし | `migrations/0004_pet_scopes.sql` |
| G3-B | petlo-api セッション | `/sync/push` `pet_scope` 受信 + client int → server uuid 解決 + fanout | 同上 |
| G3-C | petlo-api セッション | `/sync/pull` `petScopes` emit + **非対称 CTE 設計** (Decision Log #8) | 同上 |
| G3-D | petlo-api セッション | 新規 REST 4 本 (`POST/DELETE/PATCH/GET /pets/{id}/shares`) + 認可 (Decision Log #4 を確定実装) | 同上 |
| G3-E | **v1.1 送り** | schedules の Hybrid 化 | backend に schedules テーブル無し、新規設計必要 |
| G3-F | **v1.1 送り** | クライアント version gating | TestFlight 段階は運用吸収可、App Store 公開時に再評価 |
| G4 | **次フェーズ** | UI 改修 (PetSharePicker multi-select / Switch group バグ修正 / ARB 移動→共有 / GET shares 経由の scope 一覧) | 見積もり 4-5 日 |
