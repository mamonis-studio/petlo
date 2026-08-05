# petlo — 予防コース (フィラリア / ノミダニ) 実装仕様 **v2**

**対象ビルド**: build 73 / schemaVersion v10（**据え置き**）
**改訂日**: 2026-07-29
**前版**: `petlo_prevention.md` (v1)

---

## 0. この文書の位置づけ — 最初に読むこと

> ### これは新規実装の依頼ではない。**build 72 で実装済みのコードへのパッチ指示**である。
>
> v1 仕様に基づく Phase 1〜5 は **すでに実装・検証済み**（`flutter analyze` クリーン、
> ユニットテスト 440 件パス、L10n 3 言語 77 キー一致）。
>
> **既存の実装を作り直さないこと。** 本書 §0.2 に列挙した箇所**のみ**を変更する。
> それ以外の章は「現行実装の記述（＝変更不要）」として読むこと。

### 0.1 実装済みの状態（build 72）

| 区分 | 状態 |
|:---|:---|
| DB (`prevention_courses` / `prevention_doses`) | 実装済み |
| migration v9 → v10 | 実装済み |
| repository 2 本（materialize / 再 materialize / 投与記録 / 取消） | 実装済み |
| UI（一覧 / 詳細 / フォーム / 月グリッド / dose シート） | 実装済み |
| 通知（dose / course、バジェット分割） | 実装済み ← **v2 で方式変更** |
| L10n 3 言語 77 キー | 実装済み ← **v2 で 2 キー追加** |
| 課金ゲート | 実装済み |
| 免責文 4 箇所 | 実装済み |
| pet 削除 cascade | 実装済み |

### 0.2 v2 での変更点（**ここだけやる**）

| # | 章 | 内容 | 種別 |
|---:|:---|:---|:---|
| P1 | §5.4 | 通知バジェットを**優先度ラダー方式**に変更。検査リマインドに 4 slot 予約、dose の「1 コース 2 回」固定キャップを廃止し貪欲充填へ | 方式変更 |
| P2 | §6 | v1 の前提が誤りだったため全面改訂。AI コンテキストは `medications` 経由をやめ `prevention_doses` を直接読む | 誤り訂正 + 機能追加 |
| P3 | §6.3 | `medications` への INSERT / 論理削除が `BaseRepository` を経由しているかを検証し、外れていれば修正 | 不具合確認 |
| P4 | §8.4 | 年（`year`）を**編集画面でのみ**変更可能にする。投与実績がある場合はロック | 機能追加 |
| P5 | §10.4 | ARB に 2 キー追加（3 言語） | 追加 |
| P6 | §7 | 追撃通知の Pro 限定を**確定事項として明文化**（判断根拠を記録） | 決定の固定 |

### 0.3 v2 で「変更しない」と決めたこと

意図せぬ善意の改変を防ぐため明記する。

- **§9 の免責文言と禁止事項は一切緩めない。** 分かりやすさのために断定形へ寄せることを禁じる
- **追撃通知（dose slot 1）は Pro 限定のまま。** §7.2 に根拠を記載
- **schemaVersion は 10 のまま。** v2 に DB 変更は含まれない
- **`expiration_items` は引き続き放置。** DROP しない
- v1 §12 のフェーズ分割・§14 のチェックリストはそのまま有効

### 0.4 build 72 で仕様外に追加され、v2 で正式採用するもの

実装時に Claude Code が追加した以下 2 ファイルは判断として正しい。**正式にファイル一覧へ組み入れる**（§8.1 に反映済み）。

| ファイル | 採用理由 |
|:---|:---|
| `core/prevention/prevention_notification_labels.dart` | ラベル解決が UI と通知の両方から必要。重複回避 |
| `widgets/prevention/prevention_disclaimer.dart` | §9.1 が 4 箇所への配置を要求。共通化しないと法務文言が 4 重複し、改訂時に取りこぼす |

また、**L10n を Phase 2/3 より先に実施した順序変更は正しい**。UI が L10n に依存する以上、今後もこの順序を標準とする（§12 に反映済み）。

---

## 1. 機能概要

犬猫のフィラリア予防・ノミダニ予防を「**年単位のコース**」として管理する。

```
フィラリア予防 2026
━━━━━━━━━━━━━━━━━━━━━━━━━
シーズン前検査   ✓ 4/28 実施済み
薬剤             ネクスガードスペクトラ

 5月 ✓   6月 ✓   7月 ✓   8月 ●
 9月 ○  10月 ○  11月 ○  12月 ○ ←最終回

進捗 3/8 回      次回 8月10日
```

- ✓ = 投与済み / ● = 今月分（未投与） / ○ = 未来
- 月マスをタップ → 投与記録 → `medications` テーブルにも 1 行 INSERT（§6 参照）

### 設計の芯

1. **シーズンという単位**を第一級の概念にする（月次繰り返しではなく年次コース）
2. **投与実績は独立レコード**として持つ。コース設定を変更しても実績は不滅
3. **最終回を特別扱いする**。予防中断の最頻出パターンが「12 月の最後 1 回の飛ばし」

---

## 2. データモデル（**v2 変更なし / 実装済み**）

v1 §2 と同一。`database_enums.dart` の新規 enum 4 つ、`prevention_courses` /
`prevention_doses` の 2 テーブル、`app_database.dart` の 4 箇所への登録、
migration v9 → v10（`createTable` 2 本のみ、backfill なし）はすべて実装済み。

**非破壊制約は v2 でも維持される:**

| 項目 | 内容 |
|:---|:---|
| 既存テーブルのカラム追加・変更・削除 | **ゼロ** |
| 既存 enum への値追加 | **ゼロ** |
| migration の backfill | **なし** |
| schemaVersion | **10 のまま**（v2 に DB 変更なし） |

---

## 3. 地域プリセット（**v2 変更なし / 実装済み**）

`core/prevention/prevention_region_presets.dart` は v1 §3 のまま。

> リマインド: プリセットは**一般的な目安**であり医学的指示ではない。
> UI では必ず `prevention_disclaimer_period` を併記する（§9）。

---

## 4. dose の materialize ロジック（**v2 変更なし / 実装済み**）

v1 §4 のまま。特に **§4.3 の再 materialize ルール（c）**——

> 新集合に無いが投与済み or スキップ済みの dose は**削除しない**。
> `seq` を末尾に退避し、UI では「コース外の記録」として別枠表示する。

——は本機能の生命線であり、v2 でも一切変更しない。§8.4 で追加する
「年の変更」もこのルールと衝突しないよう設計されている。

---

## 5. 通知設計

### 5.1 通知 ID レンジ（**v2 変更なし / 実装済み**）

| 用途 | ベース |
|:---|---:|
| ワクチン | 1,000,000 |
| 投薬リマインダー (legacy) | 10,000,000 |
| schedule | 100,000,000 |
| prevention dose | 400,000,000 |
| prevention course | 500,000,000 |

```dart
  static int idForPreventionDose(int doseId, int slot) {
    return 400000000 + doseId * 4 + slot;
  }

  static int idForPreventionCourse(int courseId, int slot) {
    return 500000000 + courseId * 4 + slot;
  }
```

### 5.2 dose 単位の通知（**v2 変更なし**）

| slot | 発火 | 条件 | 文言キー |
|---:|:---|:---|:---|
| 0 | 予定日 `notifyTime` | 常時 | `prevention_notify_due_*` |
| 1 | 予定日翌日 `notifyTime` | **Pro のみ** | `prevention_notify_followup_*` |
| 2 | 予定日 3 日前 `notifyTime` | `isFinal` かつ Pro | `prevention_notify_final_*` |

投与記録した瞬間に該当 dose の slot 0-2 を `cancel`。取り消したら再スケジュール。

### 5.3 course 単位の通知（**v2 変更なし**）

| slot | 発火 | 条件 | 文言キー |
|---:|:---|:---|:---|
| 0 | シーズン開始 30 日前 09:00 | `kind != flea_tick` かつ `testReminderEnabled` かつ `testedAt == null` | `prevention_notify_test_*` |
| 1 | シーズン開始 7 日前 09:00 | 同上 | `prevention_notify_test_again_*` |
| 2 | シーズン終了 + 90 日後 09:00 | Pro のみ | `prevention_notify_next_season_*` |

---

### 5.4 ★**P1: スロット配分を優先度ラダー方式に変更**★

#### 変更の背景

build 72 の実装では、course slot を `_kPreventionSlotBudget` に含めた上で
`scheduledDate` 昇順の先着で 12 slot を埋めている。この方式には穴が 2 つある。

**穴 (a) — 検査リマインドが押し出される**

月次の dose 通知が先に枠を食い尽くすと、course slot 0/1（シーズン前検査）が
入らないケースが出る。§7 で「検査リマインドは安全に直結するため無料でも通知する」
と定めた通り、**これは優先度が最上位**であり、通常の投薬通知に負けてはならない。

**穴 (b) — アプリを開かないユーザーが 2 か月で通知を失う**

v1 が指定した「1 コースあたり直近 2 回分だけ積み、投与記録とアプリ起動で再構築」
は、記録も起動もしないユーザーに対して機能しない。2 回分が発火し切った時点で
以降が無通知になる。**月次リマインダーを最も必要とするのはまさにその層**であり、
仕様として不適切だった。

#### 新方式 — 優先度ラダー

`_kPreventionSlotBudget = 12` は維持。ただし配分を先着から**優先度順の貪欲充填**に
変更する。上位ティアから順に、バジェットを使い切るまで積む。

```
Tier 1 [予約枠 最大 4]  course slot 0/1  検査リマインド
                         対象: testedAt == null かつ testReminderEnabled のコース
                         シーズン開始日の昇順
                         ※ 4 slot を予約する。Tier 2 以降がこの枠を奪ってはならない
                         ※ 使い切らなかった分は下位ティアへ流す

Tier 2                   dose slot 0      当日通知
                         全コース横断、scheduledDate 昇順
                         未投与かつ未スキップの dose のみ
                         ★ 「1 コース 2 回まで」の固定キャップは廃止
                         ★ 残バジェットを使い切るまで積む

Tier 3                   dose slot 2      最終回 3 日前（Pro / isFinal のみ）

Tier 4                   dose slot 1      翌日の追撃（Pro）

Tier 5                   course slot 2    翌シーズン案内（Pro）
```

#### 実装上の注意

- Tier 1 の「予約」は、**Tier 2 以降を積む前に Tier 1 の所要数を確定させ、
  `min(所要数, 4)` を残バジェットから先に差し引く**ことで実現する。
  Tier 1 が 1 slot しか使わないなら、残り 11 が Tier 2 以降に回る
- Tier 2 は**コース単位の上限を持たない**。1 コースでシーズン 8 回分すべてを
  積み切ってよい
- 過去日（`scheduledDate < now`）の dose は積まない
- 再構築のトリガーは v1 のまま:
  アプリ起動時 / 投与記録・取消時 / コース作成・更新・削除時

#### 配分の検算

| 想定 | Tier 1 | Tier 2 | 計 | 評価 |
|:---|---:|---:|---:|:---|
| 無料・1 コース（フィラリア・未検査） | 2 | 8 | 10 | **シーズン全 8 回を予約可**。開かなくても切れない |
| 無料・1 コース（検査済み） | 0 | 8 | 8 | 同上 |
| Pro・2 ペット × 2 種 = 4 コース | 4 | 8 | 12 | 各コース約 2 回分。Pro 層はアプリを開くため許容 |

無料ユーザーは追撃通知（slot 1）を持たないため 1 dose = 1 slot で済み、
結果としてシーズン丸ごとをカバーできる。**この非対称性は意図的な設計**である。

#### 既存定数

```dart
/// build 72: グローバル 50 slot を schedule 系 / 予防系に分割。
const int _kScheduleSlotBudget = 38;
const int _kPreventionSlotBudget = 12;

/// build 73 (v2): 予防バジェット内で検査リマインドに予約する上限。
const int _kPreventionTestReminderReserve = 4;
```

`_kScheduleSlotBudget` を 50 → 38 に下げた変更は build 72 で実施済み。
**実機での回帰確認（§13 #2/#3/#4）が未実施のため、v2 でも最優先項目のまま。**

---

## 6. ★**P2 / P3: `medications` との連携 — v1 の前提が誤っていたため全面改訂**★

### 6.1 v1 の誤りと訂正

v1 §6 は「投与記録を `medications` に INSERT すれば、**既存の投薬履歴 UI・AI
コンテキストに自動で載る**」と記述していた。**これは事実誤認である。**

コードベースを再確認した結果:

| 検証 | 結果 |
|:---|:---|
| `MedicationsRepository` | **存在しない** |
| `db.medications` の参照（読み書きとも） | **lib/ 全体でゼロ** |
| `MedicationEntity` / `MedicationsCompanion` の参照 | テーブル定義ファイル自身のみ |
| 投薬履歴を表示する画面 | **存在しない** |
| `pet_context_builder.dart` が medications を取得しているか | **していない** |

とりわけ `pet_context_builder.dart` の冒頭コメントは

```
//   - 直近7日の Meal/Poop/Pee/Vomit/Weight/Visit/Vaccination/Diary/Medication を集めて
```

と `Medication` を列挙しているが、実装が取得しているのは
meals / poops / pees / vomits / diaries / visits / vaccinations / 最新体重 /
最新体温 の 9 種のみである。**コメントが実装と乖離している。**
v1 はこのコメントを根拠に誤った前提を置いた。

### 6.2 対応方針

**`medications` への INSERT は維持する。** 将来の投薬履歴 UI が実装された時点で
過去数年分の予防記録がそのまま載るため、データ蓄積の観点で価値がある。

**ただし AI コンテキストは `medications` を経由しない。**
`prevention_doses` を直接読む。予防機能は自前のリポジトリを持つため、
`medications` にリポジトリが生える日を待つ必要がない。

#### 実装 — `pet_context_builder.dart`

他のリポジトリ取得と同じ形で、現在進行中のコースの要約を追加する。
（既存の取得ブロックは 50〜75 行目付近。その末尾に追記する）

収集する内容:

| 項目 | 内容 |
|:---|:---|
| コース種別 | フィラリア / ノミダニ / オールインワン |
| 対象年 | 2026 |
| 進捗 | 投与済み回数 / 総回数 |
| 次回予定日 | 未投与のうち最も近い `scheduledDate` |
| 未投与の有無 | `scheduledDate < now` かつ未投与・未スキップの dose が存在するか |
| 検査状況 | `testedAt` の有無 |

対象は「今日が属するシーズンのコース」のみ。過去年のコースは含めない
（AI のコンテキスト長を無駄に消費するため）。

`core/ai/ai_pet_context.dart` に対応するフィールドを追加する。
**プロンプト側で医学的助言を促す表現を使わないこと。** 事実の列挙に留め、
判断は §9 の免責方針に従って獣医師へ委ねる。

#### 併せて修正

`pet_context_builder.dart` 11 行目のコメントを実装に合わせて修正する。
`Medication` を削除し、予防を追記する。**嘘のコメントを残さない。**

### 6.3 ★**P3: `BaseRepository` 経由かどうかの検証（必須）**★

`MedicationsRepository` が存在しない以上、build 72 の INSERT は drift の
直接操作になっているはずである。以下を確認し、外れていれば修正すること。

| # | 確認項目 |
|---:|:---|
| 1 | INSERT 時、`buildCreateMetadata(groupId:)` 経由で `createdAt` / `updatedAt` / `lastModifiedAtClient` / `syncStatus` を設定しているか |
| 2 | 共有スコープで `enqueueSyncIfShared(targetTable: 'medications', operation: SyncOperation.insert, ...)` を呼んでいるか |
| 3 | 投与取消時の論理削除が `buildDeleteMetadata(groupId:)` 経由か |
| 4 | 取消時に `enqueueSyncIfShared(..., operation: SyncOperation.delete, ...)` を呼んでいるか |
| 5 | `medications.reminderId` に **`null` 以外を入れていない**か（当該カラムは `schedules` 系の参照であり、予防 dose の id を入れてはならない） |
| 6 | `groupId` がコースの `groupId` を引き継いでいるか（`'personal'` 決め打ちになっていないか） |

> **なぜ重要か:** `medications` には現在読み手が存在しない。したがって
> ここが壊れていても**誰も痛みを感じない**。共有スコープの同期漏れは、
> 投薬履歴 UI が実装される数年後まで発覚しない種類の欠陥である。
> 読み手がいない今のうちに正しくしておく。

### 6.4 投与記録・取消の処理（v1 から変更なし）

```
投与記録 (単一トランザクション):
  1. medications へ INSERT
       petId          = course.petId
       groupId        = course.groupId          ← §6.3 #6
       reminderId     = null                    ← §6.3 #5
       medicineName   = course.medicineName ?? (kind のローカライズ名)
       dosage         = course.dosage
       administeredAt = ユーザー指定日時
       notes          = dose.notes
       + buildCreateMetadata()                  ← §6.3 #1
  2. 1 で得た id を dose.medicationId に UPDATE
  3. dose.administeredAt を UPDATE
  4. enqueueSyncIfShared を medications / prevention_doses それぞれで呼ぶ
  5. 該当 dose の通知 slot 0-2 を cancel
  6. 予防通知を再構築（§5.4 のラダーで再配分）

投与取り消し (単一トランザクション):
  1. dose.medicationId が非 null なら該当 medications 行を論理削除
       + buildDeleteMetadata()                  ← §6.3 #3
  2. dose.administeredAt = null, dose.medicationId = null
  3. 通知を再構築
```

---

## 7. 課金ゲート

### 7.1 上限と機能割り当て（**v2 変更なし / 実装済み**）

```dart
  // ===== 予防コース (build 72) =====
  static const int freeMaxPreventionCourses = 1;
  static const int freePreventionHistoryYears = 1;
```

| 機能 | 無料 | Pro |
|:---|:---|:---|
| 予防コース作成 | **1 件まで** | 無制限 |
| 当日通知 (dose slot 0) | ○ | ○ |
| 翌日の追撃通知 (slot 1) | × | ○ |
| 最終回の 3 日前通知 (slot 2) | × | ○ |
| シーズン前検査リマインド (course slot 0/1) | ○ | ○ |
| 翌シーズン案内 (course slot 2) | × | ○ |
| 過去年の履歴閲覧 | 当年のみ | 全期間 |
| CSV / PDF 書き出し | × | ○ |
| 家族共有 | × | ○ |

無料枠の判定は `created_at` 昇順で先着 1 件。`year` 基準にすると
「年を変えれば何個でも作れる」抜け道が生まれるため。

### 7.2 ★**P6: 追撃通知を Pro 限定に据え置く決定（根拠の記録）**★

「翌日の追撃通知（dose slot 1）を無料開放すべきではないか」は検討の上、
**現状維持（Pro 限定）で確定**した。今後この判断を覆さないこと。

根拠:

無料開放すると 1 dose あたりのスロット消費が 1 → 2 に倍増し、
§5.4 Tier 2 で無料ユーザーが予約できる回数が **8 回（シーズン全体）から
4 回（約 4 か月）へ半減**する。

- 得られるもの: 翌日に念押しが 1 回入る
- 失うもの: シーズン後半 4 か月分の通知が、アプリを開かない限り届かなくなる

**後者の損失のほうが大きい。** 予防薬の飲み忘れは終盤（11〜12 月）に集中する
という前提に立てば、通知が切れる区間を作ることは設計として容認できない。

---

## 8. UI 仕様

### 8.1 画面構成（**§0.4 の 2 ファイルを正式に組み入れ**）

```
健康タブ
  └ [予防] セクション
       ├ 進行中コースのサマリーカード
       └ 「予防を管理」→ PreventionCourseListScreen
                            ├ コース一覧（年でグルーピング）
                            ├ [+] → PreventionCourseFormScreen
                            └ タップ → PreventionCourseDetailScreen
```

```
lib/presentation/screens/prevention/prevention_course_list_screen.dart
lib/presentation/screens/prevention/prevention_course_detail_screen.dart
lib/presentation/screens/prevention/prevention_course_form_screen.dart
lib/presentation/screens/prevention/prevention_course_form_controller.dart
lib/presentation/screens/prevention/prevention_course_form_state.dart
lib/presentation/widgets/prevention/prevention_month_grid.dart
lib/presentation/widgets/prevention/prevention_dose_sheet.dart
lib/presentation/widgets/prevention/prevention_progress_bar.dart
lib/presentation/widgets/prevention/prevention_disclaimer.dart          ★v2 で正式採用
lib/presentation/providers/prevention_providers.dart
lib/data/repositories/prevention_courses_repository.dart
lib/data/repositories/prevention_doses_repository.dart
lib/core/prevention/prevention_region_presets.dart
lib/core/prevention/prevention_notification_labels.dart                 ★v2 で正式採用
lib/core/prevention/prevention_notification_scheduler.dart
```

### 8.2 月グリッドの表示規則（**v2 変更なし / 実装済み**）

状態表示は色だけに依存させない（色覚配慮）。記号を併記する。

| 状態 | 表示 |
|:---|:---|
| 投与済み | `✓` + 塗りつぶし |
| 今日が予定日 | `●` + 太枠 |
| 予定日超過・未投与 | `!` + 太枠 |
| 未来 | `○` + 細枠 |
| スキップ | `–` + グレー |

最終回のマスには `prevention_final_badge` を付与。絵文字は使わない。

### 8.3 コース作成フローの順序（**v2 変更なし / 実装済み**）

```
1. ペット選択
2. 種別選択
3. 地域選択 → 開始月・終了月が自動入力
       ↓ 直下に prevention_disclaimer_period を常設表示
4. 投与日と通知時刻
5. 薬剤名・用量・剤型（任意）
6. [フィラリア/オールインワンのみ] シーズン前検査
       ↓ prevention_disclaimer_test を常設表示
7. 確認 → 保存 → materialize → 通知スケジュール
```

**作成フローにステップを追加しないこと。** 対象年（`year`）は build 72 の
実装どおり自動解決する（シーズンが年内に終了済みなら翌年を既定値とする）。

### 8.4 ★**P4: 年（`year`）を編集画面でのみ変更可能にする**★

#### 背景

build 72 は作成時に `year` を自動解決する。判断としては正しい——作成フローに
年の選択ステップを足すのは、少数のユースケースのために全ユーザーの摩擦を
増やすことになる。

しかし現状では「**去年の分を後から記録したい**」が完全に塞がっている。
petlo の価値の中核はデータ蓄積であり、過去シーズンの遡り入力は太いユースケースである。

#### 仕様

`PreventionCourseFormScreen` の**編集モードでのみ**、年のフィールドを表示する。
新規作成モードでは表示しない（§8.3 の順序は不変）。

| 条件 | 挙動 |
|:---|:---|
| 投与済み・スキップ済みの dose が **0 件** | 年を変更可能。ステッパーで ±1 年、範囲は現在年 −5 〜 +1 |
| 投与済み・スキップ済みの dose が **1 件以上** | 年フィールドを**ロック**（非活性表示）し、`prevention_year_locked_hint` を併記 |

#### ロックする理由

年を変更すると全 dose の `scheduledDate` が移動する。ここで §4.3 のルール（c）
「投与済み dose は削除しない」が働くと、実績のある dose が軒並み
「コース外の記録」に退避され、ユーザーから見て**記録が消えたように見える**。

実績があるコースの年を変えたいケースは実質「入力ミスの訂正」に限られ、
その場合はコースを作り直したほうが安全かつ意図が明確である。
**曖昧な状態を作らないことを優先する。**

#### 想定される主要フロー

```
「去年の分を入れたい」
  → 新規作成（year は自動で 2026 になる）
  → 保存直後に編集を開く（投与実績 0 件 なのでロックされていない）
  → year を 2025 に変更 → 再 materialize
  → 月グリッドから過去分を記録していく
```

年の変更時は §4.3 の再 materialize を通す。実績 0 件が保証されているため、
ケース（c）は発生せず、全 dose が単純に UPDATE される。

#### 過去年コースと通知

`year` が過去のコースに対しては**通知を一切スケジュールしない**
（`scheduledDate < now` は積まない、という §5.4 の既存ルールで自動的に満たされる）。
遡り入力が通知バジェットを消費しないことを確認すること。

---

## 9. 医療免責（**v2 変更なし / 実装済み。緩和禁止**）

petlo は記録・リマインダーアプリであり、獣医療の指示を行うものではない。

### 9.1 表示箇所

| 箇所 | キー |
|:---|:---|
| コース作成画面・地域選択の直下（常設、折りたたみ不可） | `prevention_disclaimer_period` |
| コース作成画面・検査セクションの直下（常設） | `prevention_disclaimer_test` |
| コース詳細画面の最下部（常設） | `prevention_disclaimer_period` |
| 設定 > このアプリについて の医療免責セクション | `prevention_disclaimer_general` |

いずれも `prevention_disclaimer.dart`（§0.4）を用いて共通化する。

### 9.2 禁止事項（**厳守**）

- 通知本文に医学的な断定を入れない（「今日飲ませないと危険です」は **NG**）
- 「必須」「しなければなりません」という語を使わない
- 地域プリセットを「推奨期間」と呼ばない。**必ず「目安」**
- 検査を UI 上で強制フローにしない。スキップ可能にした上で注意喚起に留める
- **§6.2 で追加する AI コンテキストのプロンプトにも同じ制約を適用する。**
  AI に投薬判断を語らせない

> 分かりやすさを求めて断定形へ寄せたくなる場面が必ず来る。そのほうが親切に見える。
> しかしそれは獣医の役割を騙ることであり、外したときにユーザーが払う代償が大きすぎる。
> **ここでの親切は「目安です、獣医に確認を」と言い続けることである。**

### 9.3 文言（日本語）

```
prevention_disclaimer_period:
予防期間はお住まいの地域や気候、その年の気温によって変わります。表示は一般的な
目安です。実際の開始・終了時期はかかりつけの獣医師にご確認ください。

prevention_disclaimer_test:
予防を始める前に、感染の有無を調べる検査が必要な場合があります。獣医師の指示に
従ってください。

prevention_disclaimer_general:
petlo は記録とリマインダーのためのアプリです。診断・治療・投薬の指示を行うもの
ではありません。健康に関する判断は必ず獣医師にご相談ください。
```

---

## 10. L10n

### 10.1〜10.3（**実装済み / 変更なし**）

v1 §10 の 77 キーは 3 言語（`app_ja.arb` / `app_en.arb` / `app_zh.arb`）
すべてに実装済みで、キー一致・未使用ゼロ・ハードコードゼロを検証済み。
**既存 77 キーには手を触れないこと。**

### 10.4 ★**P5: v2 で追加する 2 キー**★

`prevention_year_label` / `prevention_year_locked_hint`（§8.4 用）。
3 ファイルすべてに追加し、`flutter gen-l10n` を再実行する。

**`app_ja.arb`**

```json
  "prevention_year_label": "対象年",
  "prevention_year_locked_hint": "投与の記録があるため、年は変更できません。"
```

**`app_en.arb`**

```json
  "prevention_year_label": "Year",
  "prevention_year_locked_hint": "The year can't be changed because doses have already been recorded."
```

**`app_zh.arb`**

```json
  "prevention_year_label": "对象年份",
  "prevention_year_locked_hint": "已存在给药记录，无法更改年份。"
```

---

## 11. v2 で変更する既存ファイル（**全 5 箇所**）

| # | ファイル | 変更内容 | 破壊性 |
|---:|:---|:---|:---|
| 1 | `core/prevention/prevention_notification_scheduler.dart` | スロット配分を優先度ラダーへ（§5.4）。`_kPreventionTestReminderReserve` を追加 | 予防内で完結 |
| 2 | `presentation/providers/pet_context_builder.dart` | 予防サマリの取得を追加（§6.2）。11 行目の誤コメントを修正 | 追加のみ |
| 3 | `core/ai/ai_pet_context.dart` | 予防サマリのフィールドを追加（§6.2） | 追加のみ |
| 4 | `presentation/screens/prevention/prevention_course_form_screen.dart` (+controller/state) | 編集モードの年フィールド（§8.4） | 予防内で完結 |
| 5 | `l10n/app_ja.arb` / `app_en.arb` / `app_zh.arb` | 2 キー追加（§10.4） | 追加のみ |

加えて **§6.3 の検証結果しだい**で、投与記録・取消の実装
（`prevention_doses_repository.dart` 等）に修正が入る。

> **DB・migration・constants・notification_service の ID 採番・pets_repository の
> cascade は v2 で変更しない。** build 72 のままでよい。

---

## 12. v2 の作業手順

L10n を UI より先に行う順序を標準とする（§0.4）。

- [ ] **Step 1** — §10.4 の 2 キーを 3 言語に追加 → `flutter gen-l10n`
- [ ] **Step 2** — §6.3 の 6 項目を検証。外れていれば修正（**最優先。正しさの問題**）
- [ ] **Step 3** — §5.4 の優先度ラダーを実装。§5.4「配分の検算」の 3 ケースを
      ユニットテストで固定する
- [ ] **Step 4** — §6.2 の AI コンテキスト追加 + 誤コメント修正
- [ ] **Step 5** — §8.4 の年フィールド（編集モードのみ / 実績ありでロック）
- [ ] **Step 6** — `appBuildNumber` を 72 → 73 に
- [ ] **Step 7** — §13 の回帰。特に v2 追加分（#13〜#17）

---

## 13. 回帰テスト項目

### build 72 で自動化済み（再実行のみ）

| # | 項目 | 期待結果 |
|---:|:---|:---|
| 1 | v9 → v10 アップグレード | 既存のペット・全記録・写真が無傷 |
| 5 | ペット論理削除 | 予防コースと dose も一緒に論理削除される |
| 6 | お別れ (`markAsParted`) | 予防データは**消えない** |
| 9 | コース期間の短縮 | 範囲外になった**投与済み** dose が消えない |
| 10 | 投与記録の取り消し | `medications` の該当行が論理削除される |
| 11 | 家族共有スコープ | `sync_queue` に予防の op が正しく積まれる |
| 12 | 無料プラン | 2 件目のコース作成でペイウォールが出る |

### 実機必須（build 72 から未実施 — **最優先**）

| # | 項目 | 期待結果 |
|---:|:---|:---|
| 2 | 既存の投薬リマインダー通知 | v10 後も従来どおり発火する |
| 3 | ワクチン期限通知 | 予防通知追加後も枯渇しない |
| 4 | `pending()` の総数 | iOS で 64 未満 |
| 7 | バックアップ書き出し | zip 内 sqlite に予防テーブルが含まれる |
| 8 | v9 バックアップの復元 | 成功し、起動時に v10 migration が走る |

### v2 で追加

| # | 項目 | 期待結果 |
|---:|:---|:---|
| 13 | 無料・1 コース・未検査 | 検査 2 slot + dose 8 slot = シーズン全回が予約される |
| 14 | Pro・4 コース | 検査リマインドが**必ず**予約される（dose に押し出されない） |
| 15 | 過去年コース | 通知が 1 件もスケジュールされない |
| 16 | 実績ありコースの編集 | 年フィールドがロックされ、ヒントが表示される |
| 17 | 実績 0 件コースの年変更 | 全 dose が単純 UPDATE され、「コース外の記録」が発生しない |

#### 実機での通知確認手順（#2 / #3 / #4 / #13 / #14）

`developer_settings_screen.dart` に `NotificationService.pending()` の
一覧デバッグ表示を追加し、ID レンジで仕分けて表示する。

| レンジ | 中身 |
|---:|:---|
| 1,000,000〜 | ワクチン |
| 100,000,000〜 | schedule（投薬） |
| 400,000,000〜 | 予防 dose |
| 500,000,000〜 | 予防 course |

最悪ケース（投薬 schedule 3 件 + ワクチン数件 + 2 ペット × 2 種の予防 4 コース）を
作成し、**合計 64 未満**かつ**ワクチン・投薬が 1 件も消えていない**ことを確認する。
`_kScheduleSlotBudget` を 50 → 38 に下げた影響を見る唯一の手段であり、
ここが通らなければリリースしない。

---

## 14. ファイル別チェックリスト（v1 から変更なし）

各ファイル完成ごとに確認:

- [ ] import のパス深度は正しいか
- [ ] enum 名が `dart:ui` 等と衝突していないか
- [ ] 永続化に `jsonEncode` を使っているか（`.toString()` 禁止）
- [ ] `pubspec.yaml` への追加は不要か（v2 も新規依存なし）
- [ ] UI 文字列はすべて L10n キー経由か
- [ ] Bundle ID は `mamonis.studio.petlo` のままか
- [ ] 未使用 import が残っていないか
- [ ] `withOpacity()` ではなく `withValues()` を使っているか
- [ ] TODO / 未実装のスタブが 1 つも残っていないか
- [ ] 絵文字を使っていないか（SVG アイコンのみ）

---

## 15. 別チケット（v2 の範囲外）

- **既存ウィジェットテスト 19 件の緑化。** `AppTab.more` の削除と
  `SemanticsNode` / `SemanticsFlag` の Flutter SDK API 変更に起因し、
  予防機能とは無関係かつ本実装以前から失敗している。
  ただし**常時レッドのスイートは次の本物の回帰を隠す**ため、
  修正か削除のいずれかで緑に戻す。優先度は低
- 予防記録の CSV / PDF 書き出し（通院時に見せる用途）
- 前年コースからの「今年もこれで」ワンタップ複製
- `expiration_items` 死にテーブルの棚卸しと撤去
- `ScheduleRecurrence.monthly` / `yearly` を scheduler 側で実装
- `medications` のリポジトリと投薬履歴 UI（実装されれば §6 の INSERT が可視化される）
