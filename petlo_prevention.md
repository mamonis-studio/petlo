# petlo — 予防コース (フィラリア / ノミダニ) 実装仕様

**対象ビルド**: build 72 / schemaVersion v10
**作成日**: 2026-07-29
**実装担当**: Claude Code (CLI)

---

## 0. 最重要 — 非破壊制約

この機能は**既存テーブル・既存 enum を一切変更しない**。追加のみで完結させる。

| 項目 | 内容 |
|:---|:---|
| 既存テーブルのカラム追加 | **ゼロ** |
| 既存テーブルのカラム変更・削除 | **ゼロ** |
| 既存 enum への値追加 | **ゼロ**（新規 enum のみ定義） |
| 既存 `medications` への操作 | **INSERT のみ**。既存行は不変 |
| migration の backfill | **なし**。`createTable` 2 本のみ |
| `schedules` への影響 | **なし**。予防は独立系統で扱う |

### なぜ `schedules` に相乗りしないか

`notification_scheduler.dart` の現行実装は `category=medication` のとき
`weekdaysBits` を見て「毎日」か「毎週指定曜日」しか組み立てられない
(`syncSchedule` 内 L85-120)。`ScheduleRecurrence.monthly` / `yearly` は enum に
存在するが scheduler 側が完全に無視している。

予防薬は「毎月 1 回 × 特定シーズンのみ」なので、この器には構造的に入らない。
`schedules` を拡張すると既存の投薬リマインダー (v7 で `medication_reminders`
から移行済みのユーザーデータ) の挙動に影響が出るため、**触らない**。

### 死にテーブル `expiration_items` について

`expiration_items` は `ReminderKind.filaria` を持ち、コメントに
「プリセット 6 種 (フィラリア、ノミダニ、ワクチン等)」と書かれているが、
**repository も UI も存在しない完全な未使用テーブル**。

本仕様では **`expiration_items` を使わない / 削除もしない**。
理由: 実データが 0 行である保証がなく (過去ビルドで書き込んだ可能性を排除
できない)、DROP は不可逆。放置が最も安全。将来の掃除は別チケットとする。

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
- 月マスをタップ → 投与記録 → 既存の `medications` テーブルにも 1 行 INSERT され、
  既存の投薬履歴と自然に統合される

### 設計の芯

1. **シーズンという単位**を第一級の概念にする（月次繰り返しではなく年次コース）
2. **投与実績は独立レコード**として持つ。コース設定を変更しても実績は不滅
3. **最終回を特別扱いする**。予防中断の最頻出パターンが「12 月の最後 1 回の飛ばし」

---

## 2. データモデル

### 2.1 新規 enum

`lib/data/local/database_enums.dart` の**末尾に追記**（既存 enum は触らない）。

```dart
// ============================================================================
// Prevention (build 72)
// ============================================================================

/// 予防コースの種別
enum PreventionKind {
  /// フィラリア (犬糸状虫) 予防
  filaria,
  /// ノミ・マダニ予防
  flea_tick,
  /// オールインワン製剤 (フィラリア + ノミダニ同時)
  combo;
}

/// 予防薬の剤型
enum PreventionForm {
  /// チュアブル (おやつタイプ)
  chewable,
  /// 錠剤
  tablet,
  /// スポットオン (滴下)
  spot_on,
  /// 注射 (年 1 回タイプ)
  injection;
}

/// 地域プリセット。予防期間の初期値算出にのみ使う。
/// あくまで一般的な目安であり、医学的な指示ではない。
enum PreventionRegion {
  hokkaido,
  tohoku,
  kanto,
  chubu,
  kansai,
  chugoku_shikoku,
  kyushu,
  okinawa,
  /// ユーザーが月を手動指定
  custom;
}

/// 1 回分の投与状態 (導出値。DB には保存しない)
enum PreventionDoseStatus {
  /// 未来の予定
  upcoming,
  /// 今日が予定日
  due,
  /// 予定日を過ぎたが未投与
  overdue,
  /// 投与済み
  administered,
  /// スキップ (獣医指示等でユーザーが明示的に飛ばした)
  skipped;
}
```

### 2.2 新規テーブル (1) `prevention_courses`

`lib/data/local/tables/prevention_courses.dart`

```dart
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
```

### 2.3 新規テーブル (2) `prevention_doses`

`lib/data/local/tables/prevention_doses.dart`

```dart
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
```

### 2.4 `app_database.dart` への登録

以下 4 箇所すべてに追記する。既存の行は並べ替えない。

```dart
// (1) import 節 — tables/pets.dart の後にアルファベット順で
import 'tables/prevention_courses.dart';
import 'tables/prevention_doses.dart';

// (2) export 節 — 同上
export 'tables/prevention_courses.dart';
export 'tables/prevention_doses.dart';

// (3) @DriftDatabase tables 配列 — 「予定・ストリーク」ブロックの直後に
//     新ブロックとして追加
    // 予防 (build 72)
    PreventionCourses,
    PreventionDoses,

// (4) ファイル冒頭のドキュメントコメント
//   予防(2):    prevention_courses, prevention_doses
//   合計:       29テーブル (build 72 で予防 2 テーブル追加)
```

### 2.5 マイグレーション v9 → v10

`lib/data/local/migrations/migrations.dart`:

```dart
  /// v10: 予防コース機能 (build 72)。
  ///      prevention_courses / prevention_doses を新規作成。
  ///      既存テーブル・既存データへの変更は一切なし。純粋な追加のみ。
  static const int currentVersion = 10;
```

`lib/data/local/app_database.dart` の `onUpgrade` closure、
`if (from < 9)` ブロックの**直後**に追記:

```dart
          // build 72: 予防コース機能。テーブル 2 本の新規作成のみ。
          // backfill なし、既存テーブルへの ALTER なし。
          if (from < 10) {
            await m.createTable(preventionCourses);
            await m.createTable(preventionDoses);
          }
```

> **注意**: `beforeOpen` のセーフティネット (`backfillPetScopesFromPets` /
> `backfillPersonalScopes`) には**手を入れない**。予防テーブルは backfill 不要。

#### バックアップ復元との整合

`backup_archive_service.dart` は sqlite ファイルごと差し替える方式で、
復元時に `_meta.json` の `schemaVersion` が現在値以下であることを検証する
(L493-529)。したがって:

- v9 以前のバックアップを v10 アプリに復元 → 検証通過 → DB 再オープン時に
  `onUpgrade(from: 9, to: 10)` が走り、予防テーブルが作成される → **安全**
- v10 のバックアップを v9 アプリに復元 → `schema 10 > 9` で**拒否される** →
  既存の防御が正しく機能する

バックアップ側のコード変更は不要。写真サブディレクトリの追加もなし
(予防機能は画像を持たない)。

---

## 3. 地域プリセット

`lib/core/prevention/prevention_region_presets.dart` (新規)

```dart
// ============================================================================
// petlo - Prevention Region Presets
// ============================================================================
//
// 地域別の予防期間の「目安」。
//
// !!! 重要 !!!
// これは医学的な指示ではなく、一般的な目安にすぎない。
// 蚊の発生時期は気候・標高・その年の気温で大きく変動する。
// UI では必ず免責文 (prevention_disclaimer_period) を併記すること。
//
// ============================================================================

import '../../data/local/database_enums.dart';

/// 地域プリセットの期間 (開始月, 終了月)
typedef PreventionPeriod = ({int startMonth, int endMonth});

abstract final class PreventionRegionPresets {
  PreventionRegionPresets._();

  /// フィラリア予防期間の目安
  static const Map<PreventionRegion, PreventionPeriod> filaria =
      <PreventionRegion, PreventionPeriod>{
    PreventionRegion.hokkaido: (startMonth: 6, endMonth: 10),
    PreventionRegion.tohoku: (startMonth: 5, endMonth: 11),
    PreventionRegion.kanto: (startMonth: 5, endMonth: 12),
    PreventionRegion.chubu: (startMonth: 5, endMonth: 12),
    PreventionRegion.kansai: (startMonth: 5, endMonth: 12),
    PreventionRegion.chugoku_shikoku: (startMonth: 4, endMonth: 12),
    PreventionRegion.kyushu: (startMonth: 4, endMonth: 12),
    // 越年 = 通年
    PreventionRegion.okinawa: (startMonth: 1, endMonth: 12),
    PreventionRegion.custom: (startMonth: 5, endMonth: 12),
  };

  /// ノミダニ予防期間の目安 (フィラリアより長め。通年推奨の地域も多い)
  static const Map<PreventionRegion, PreventionPeriod> fleaTick =
      <PreventionRegion, PreventionPeriod>{
    PreventionRegion.hokkaido: (startMonth: 5, endMonth: 11),
    PreventionRegion.tohoku: (startMonth: 4, endMonth: 11),
    PreventionRegion.kanto: (startMonth: 1, endMonth: 12),
    PreventionRegion.chubu: (startMonth: 1, endMonth: 12),
    PreventionRegion.kansai: (startMonth: 1, endMonth: 12),
    PreventionRegion.chugoku_shikoku: (startMonth: 1, endMonth: 12),
    PreventionRegion.kyushu: (startMonth: 1, endMonth: 12),
    PreventionRegion.okinawa: (startMonth: 1, endMonth: 12),
    PreventionRegion.custom: (startMonth: 4, endMonth: 11),
  };

  static PreventionPeriod periodFor({
    required PreventionKind kind,
    required PreventionRegion region,
  }) {
    switch (kind) {
      case PreventionKind.filaria:
        return filaria[region] ?? filaria[PreventionRegion.custom]!;
      case PreventionKind.flea_tick:
        return fleaTick[region] ?? fleaTick[PreventionRegion.custom]!;
      case PreventionKind.combo:
        // オールインワンはフィラリア側の期間に合わせる
        return filaria[region] ?? filaria[PreventionRegion.custom]!;
    }
  }
}
```

---

## 4. dose の materialize ロジック

`PreventionCoursesRepository` 内に実装する。

### 4.1 生成ルール

```
入力: year, startMonth, endMonth, dayOfMonth, form

form == injection の場合:
  dose 1 件のみ。seq=1, scheduledDate = year/startMonth/dayOfMonth, isFinal=true

それ以外:
  越年判定: endMonth >= startMonth → 同年内 / endMonth < startMonth → 越年
  同年内: startMonth..endMonth の各月に 1 件
  越年  : startMonth..12 (year年) + 1..endMonth (year+1年) の各月に 1 件

  各 dose:
    seq            = 1 始まりの通し番号
    scheduledDate  = 対象年月の dayOfMonth (存在しなければ月末日) のローカル 00:00 を UTC msec 化
    isFinal        = 最後の 1 件のみ true
```

### 4.2 月末丸めの実装

```dart
/// 指定年月に dayOfMonth が存在しなければ月末日に丸める。
/// 例: 2026年2月 + dayOfMonth=31 → 2026-02-28
int _clampDay(int year, int month, int dayOfMonth) {
  final int lastDay = DateTime(year, month + 1, 0).day;
  return dayOfMonth > lastDay ? lastDay : dayOfMonth;
}
```

### 4.3 コース設定変更時の再 materialize（**最重要**）

期間や投与日を変更したとき、**投与実績のある dose は絶対に消さない**。

```
再 materialize の手順 (単一トランザクション):

1. 新しい設定から「あるべき dose の (年, 月) 集合」を算出する
2. 既存 dose を全件取得する
3. 既存 dose のうち:
   a. 新集合に含まれる年月       → scheduledDate / seq / isFinal を UPDATE
                                    (administeredAt / medicationId / notes は不変)
   b. 新集合に無い かつ 未投与かつ未スキップ → 論理削除 (deletedAt セット)
   c. 新集合に無い が 投与済み or スキップ済み → **削除しない**。
                                    seq を末尾に退避し、orphan フラグ扱いで残す。
                                    UI では「コース外の記録」として別枠表示。
4. 新集合にあって既存 dose が無い年月 → INSERT
5. 通知を全部 cancel → 再スケジュール (§5)
```

> ケース (c) が本仕様の肝。「12 月まで飲ませたあとに終了月を 10 月へ修正」
> のような操作で 11・12 月の実績が消えると、ユーザーの信頼を永久に失う。

---

## 5. 通知設計

### 5.1 通知 ID レンジ

既存レンジと衝突しないこと。`notification_service.dart` の採番ヘルパー末尾に追記。

| 用途 | ベース | 既存/新規 |
|:---|---:|:---|
| ワクチン | 1,000,000 | 既存 |
| 投薬リマインダー (legacy) | 10,000,000 | 既存 |
| schedule | 100,000,000 | 既存 (上限 ~200,000,000) |
| **prevention dose** | **400,000,000** | **新規** |
| **prevention course** | **500,000,000** | **新規** |

```dart
  /// 予防 1 回分の通知 ID (build 72)。slot は 0-3。
  /// 400_000_000 + doseId * 4 + slot。
  /// doseId が 24_999_999 を超えると course レンジと衝突するが、
  /// 現実的に到達不能 (1 ペット年 8 件想定) なので無視する。
  static int idForPreventionDose(int doseId, int slot) {
    return 400000000 + doseId * 4 + slot;
  }

  /// 予防コース単位の通知 ID (build 72)。slot は 0-3。
  static int idForPreventionCourse(int courseId, int slot) {
    return 500000000 + courseId * 4 + slot;
  }
```

> Android の通知 ID は int32 (上限 2,147,483,647)。500,000,000 + courseId*4 は
> 十分に収まる。

### 5.2 dose 単位の通知 (one-shot)

`NotificationService.scheduleOneTime` を使う (L142)。

| slot | 発火 | 条件 | 文言キー |
|---:|:---|:---|:---|
| 0 | 予定日 `notifyTime` | 常時 | `prevention_notify_due_title` / `_body` |
| 1 | 予定日翌日 `notifyTime` | Pro のみ | `prevention_notify_followup_title` / `_body` |
| 2 | 予定日 3 日前 `notifyTime` | `isFinal == true` かつ Pro | `prevention_notify_final_title` / `_body` |

- 投与記録した瞬間に、その dose の slot 0-2 を `cancel` する
- 投与を取り消したら再スケジュールする

### 5.3 course 単位の通知 (one-shot)

| slot | 発火 | 条件 | 文言キー |
|---:|:---|:---|:---|
| 0 | シーズン開始日の 30 日前 09:00 | `kind != flea_tick` かつ `testReminderEnabled` かつ `testedAt == null` | `prevention_notify_test_title` / `_body` |
| 1 | シーズン開始日の 7 日前 09:00 | 同上 (`testedAt` が依然 null のとき) | `prevention_notify_test_again_title` / `_body` |
| 2 | シーズン終了 + 90 日後 09:00 | 常時 (Pro のみ) | `prevention_notify_next_season_title` / `_body` |

slot 2 は「翌年のコースを作ろう」という再訪導線。これがリテンションの本体。

### 5.4 iOS 64 スロット上限への対応（**必須**）

現状 `notification_scheduler.dart` は `_kGlobalSlotBudget = 50` を
schedule 系だけで消費している。予防を無制限に積むと**既存のワクチン通知が
枯渇する**。以下を必ず実装すること。

```dart
/// build 72: グローバル 50 slot を schedule 系 / 予防系に分割する。
/// 予防は「直近の未投与 dose 2 件分」のみ積み、投与記録時とアプリ起動時に
/// 再 materialize する。これで 1 コース最大 6 slot に抑える。
const int _kScheduleSlotBudget = 38;
const int _kPreventionSlotBudget = 12;
```

**予防通知のスケジュール方針:**

1. シーズン全 8 回分を一度に積まない
2. 各コースにつき「今日以降で最も近い未投与 dose を 2 件」だけ積む
3. 全コース横断で `scheduledDate` の昇順に並べ、`_kPreventionSlotBudget` に
   収まるところで打ち切る
4. 再構築のトリガー:
   - アプリ起動時 (`rescheduleAllSchedules` と同じ場所に `rescheduleAllPreventions` を追加)
   - dose の投与記録 / 取り消し時
   - コースの作成 / 更新 / 削除時

`_kScheduleSlotBudget` を 50 → 38 に下げる変更は既存の投薬通知に影響しうるが、
実運用上ユーザーが持つ medication schedule は 2-3 件 (= 最大 ~6 slot) 想定
なので実害はない。**この変更は §9 の回帰テストで必ず検証すること。**

---

## 6. 既存 `medications` との連携

投与記録時、`prevention_doses` の更新と同一トランザクションで
`medications` に 1 行 INSERT する。これにより既存の投薬履歴 UI・AI コンテキスト
に自動で載る。

```
投与記録 (単一トランザクション):
  1. medications へ INSERT
       petId          = course.petId
       groupId        = course.groupId
       reminderId     = null            ← 既存カラム。予防では使わない
       medicineName   = course.medicineName ?? (kind のローカライズ名)
       dosage         = course.dosage
       administeredAt = ユーザー指定日時
       notes          = dose.notes
       + buildCreateMetadata()
  2. 1 で得た id を dose.medicationId に UPDATE
  3. dose.administeredAt を UPDATE
  4. enqueueSyncIfShared を medications / prevention_doses それぞれで呼ぶ
  5. 該当 dose の通知 slot 0-2 を cancel
  6. rescheduleAllPreventions() を呼び直す

投与取り消し (単一トランザクション):
  1. dose.medicationId が非 null なら該当 medications 行を論理削除
  2. dose.administeredAt = null, dose.medicationId = null
  3. 通知を再スケジュール
```

> `medications.reminderId` は既存カラムだが `schedules` 系の参照であり、
> 予防 dose を入れてはならない (型は同じ int だが意味が違う)。**必ず null**。

---

## 7. 課金ゲート

`app_constants.dart` の「各種上限」ブロックに追記:

```dart
  // ===== 予防コース (build 72) =====
  /// 無料プランで作成できる予防コース数 (created_at 昇順で先着)
  static const int freeMaxPreventionCourses = 1;
  /// 無料プランで閲覧できる予防履歴の年数
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
| 家族共有 (groupId != personal) | × | ○ |

**カウント方法**: 無料枠の判定は `created_at` 昇順で先着 1 件を無料扱いとする。
`year` 基準にすると「年を変えれば何個でも作れる」抜け道が生まれるため。
(既存の freemium ゲート方針と一致)

シーズン前検査のリマインドは**安全に直結するため無料でも通知する**。
ここを課金の壁にしてはいけない。

---

## 8. UI 仕様

### 8.1 画面構成

```
健康タブ
  └ [予防] セクション (新規、ワクチンセクションの下)
       ├ 進行中コースのサマリーカード (進捗バー + 次回予定日)
       └ 「予防を管理」→ PreventionCourseListScreen
                            ├ コース一覧 (年でグルーピング)
                            ├ [+] → PreventionCourseFormScreen
                            └ タップ → PreventionCourseDetailScreen
                                          ├ 月グリッド (§1 の図)
                                          ├ 検査ステータス行
                                          └ 月マップタップ → PreventionDoseSheet
```

新規ファイル:

```
lib/presentation/screens/prevention/prevention_course_list_screen.dart
lib/presentation/screens/prevention/prevention_course_detail_screen.dart
lib/presentation/screens/prevention/prevention_course_form_screen.dart
lib/presentation/screens/prevention/prevention_course_form_controller.dart
lib/presentation/screens/prevention/prevention_course_form_state.dart
lib/presentation/widgets/prevention/prevention_month_grid.dart
lib/presentation/widgets/prevention/prevention_dose_sheet.dart
lib/presentation/widgets/prevention/prevention_progress_bar.dart
lib/presentation/providers/prevention_providers.dart
lib/data/repositories/prevention_courses_repository.dart
lib/data/repositories/prevention_doses_repository.dart
lib/core/prevention/prevention_region_presets.dart
lib/core/prevention/prevention_notification_scheduler.dart
```

### 8.2 月グリッドの表示規則

- 既存の `AppColors` / `AppTypography` / `AppDimensions` に従う。白黒ミニマル
- 状態表示は**色だけに依存しない**（既存の色覚配慮方針に準拠）。記号を併記:
  - 投与済み: `✓` + 塗りつぶし
  - 今日が予定日: `●` + 太枠
  - 予定日超過・未投与: `!` + 太枠（既存の urgent 表現に揃える）
  - 未来: `○` + 細枠
  - スキップ: `–` + グレー
- 最終回のマスには `prevention_final_badge` のラベルを付与
- 絵文字は使わない。既存の `LineIcon` / `AppIcons` に SVG パスを追加する

### 8.3 コース作成フローの順序（**固定**）

```
1. ペット選択
2. 種別選択 (フィラリア / ノミダニ / オールインワン)
3. 地域選択 → 開始月・終了月が自動入力される
       ↓ この直下に免責文を常設表示 (prevention_disclaimer_period)
4. 投与日 (1-31) と通知時刻
5. 薬剤名・用量・剤型 (任意)
6. [フィラリア/オールインワンのみ] シーズン前検査
       ↓ 免責文 (prevention_disclaimer_test) を常設表示
       ・「検査済み」→ 実施日を入力
       ・「まだ」→ testReminderEnabled = true で保存
7. 確認 → 保存 → dose を materialize → 通知スケジュール
```

---

## 9. 医療免責（**必須。省略不可**）

petlo は記録・リマインダーアプリであり、獣医療の指示を行うものではない。
以下を必ず実装すること。App Store 審査でも指摘されうる箇所。

### 9.1 表示箇所

| 箇所 | キー |
|:---|:---|
| コース作成画面・地域選択の直下（常設、折りたたみ不可） | `prevention_disclaimer_period` |
| コース作成画面・検査セクションの直下（常設） | `prevention_disclaimer_test` |
| コース詳細画面の最下部（常設） | `prevention_disclaimer_period` |
| 設定 > このアプリについて の医療免責セクション | `prevention_disclaimer_general` |

### 9.2 禁止事項

- 通知本文に医学的な断定を入れない（「今日飲ませないと危険です」は **NG**）
- 「必須」「しなければなりません」という語を使わない
- 地域プリセットを「推奨期間」と呼ばない。**必ず「目安」**
- 検査を UI 上で強制フローにしない。スキップ可能にした上で注意喚起に留める

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

## 10. L10n キー一覧

`lib/l10n/app_ja.arb` / `app_en.arb` / `app_zh.arb` の 3 ファイルすべてに追加。
ハードコード文字列は 1 つも残さない。

### 10.1 日本語 (`app_ja.arb`)

```json
  "prevention_section_title": "予防",
  "prevention_list_appbar": "予防の管理",
  "prevention_list_empty": "予防コースがまだありません",
  "prevention_list_empty_action": "コースをつくる",
  "prevention_form_appbar_new": "新しい予防コース",
  "prevention_form_appbar_edit": "予防コースを編集",
  "prevention_form_hero_new": "予防を、はじめる。",
  "prevention_form_hero_edit": "予防を、編集。",
  "prevention_kind_filaria": "フィラリア予防",
  "prevention_kind_flea_tick": "ノミ・マダニ予防",
  "prevention_kind_combo": "オールインワン",
  "prevention_form_chewable": "チュアブル",
  "prevention_form_tablet": "錠剤",
  "prevention_form_spot_on": "スポットオン",
  "prevention_form_injection": "注射（年1回）",
  "prevention_region_label": "お住まいの地域",
  "prevention_region_hokkaido": "北海道",
  "prevention_region_tohoku": "東北",
  "prevention_region_kanto": "関東",
  "prevention_region_chubu": "中部",
  "prevention_region_kansai": "関西",
  "prevention_region_chugoku_shikoku": "中国・四国",
  "prevention_region_kyushu": "九州",
  "prevention_region_okinawa": "沖縄",
  "prevention_region_custom": "自分で設定する",
  "prevention_period_label": "予防期間",
  "prevention_period_value": "{start}月 〜 {end}月",
  "prevention_period_year_round": "通年",
  "prevention_day_label": "毎月の投与日",
  "prevention_day_value": "毎月{day}日",
  "prevention_time_label": "通知時刻",
  "prevention_medicine_label": "薬の名前",
  "prevention_medicine_hint": "例: ネクスガードスペクトラ",
  "prevention_dosage_label": "用量",
  "prevention_dosage_hint": "例: 1錠 / 1ピペット",
  "prevention_test_section": "シーズン前の検査",
  "prevention_test_done": "検査済み",
  "prevention_test_not_yet": "まだ",
  "prevention_test_date_label": "検査日",
  "prevention_test_reminder_label": "検査のリマインドを受け取る",
  "prevention_test_status_done": "検査済み（{date}）",
  "prevention_test_status_pending": "検査がまだです",
  "prevention_progress_label": "{done} / {total} 回",
  "prevention_next_dose_label": "次回 {date}",
  "prevention_season_complete": "今シーズン完了",
  "prevention_final_badge": "最終回",
  "prevention_dose_status_upcoming": "予定",
  "prevention_dose_status_due": "今日",
  "prevention_dose_status_overdue": "未投与",
  "prevention_dose_status_administered": "投与済み",
  "prevention_dose_status_skipped": "スキップ",
  "prevention_dose_sheet_title": "{month}月分",
  "prevention_dose_record_action": "投与を記録",
  "prevention_dose_undo_action": "記録を取り消す",
  "prevention_dose_skip_action": "この回をスキップ",
  "prevention_dose_recorded_at": "{date} に投与",
  "prevention_orphan_section": "コース外の記録",
  "prevention_notify_due_title": "{petName} の予防薬の日",
  "prevention_notify_due_body": "{kind}の予定日です。",
  "prevention_notify_followup_title": "{petName} の予防薬",
  "prevention_notify_followup_body": "昨日の分は記録されていません。",
  "prevention_notify_final_title": "{petName} 今シーズン最後の1回",
  "prevention_notify_final_body": "{date} が最終回の予定です。",
  "prevention_notify_test_title": "{petName} のシーズン前検査",
  "prevention_notify_test_body": "予防開始まであと1か月です。",
  "prevention_notify_test_again_title": "{petName} のシーズン前検査",
  "prevention_notify_test_again_body": "予防開始まであと1週間です。",
  "prevention_notify_next_season_title": "{petName} の次のシーズン",
  "prevention_notify_next_season_body": "そろそろ今年のコースを準備しませんか。",
  "prevention_paywall_courses": "予防コースを追加するには petlo Pro が必要です",
  "prevention_paywall_history": "過去の記録を見るには petlo Pro が必要です",
  "prevention_delete_confirm_title": "このコースを削除しますか",
  "prevention_delete_confirm_body": "投与の記録は残ります。",
  "prevention_disclaimer_period": "予防期間はお住まいの地域や気候、その年の気温によって変わります。表示は一般的な目安です。実際の開始・終了時期はかかりつけの獣医師にご確認ください。",
  "prevention_disclaimer_test": "予防を始める前に、感染の有無を調べる検査が必要な場合があります。獣医師の指示に従ってください。",
  "prevention_disclaimer_general": "petlo は記録とリマインダーのためのアプリです。診断・治療・投薬の指示を行うものではありません。健康に関する判断は必ず獣医師にご相談ください。"
```

### 10.2 英語 (`app_en.arb`)

```json
  "prevention_section_title": "Prevention",
  "prevention_list_appbar": "Manage Prevention",
  "prevention_list_empty": "No prevention courses yet",
  "prevention_list_empty_action": "Create a course",
  "prevention_form_appbar_new": "New prevention course",
  "prevention_form_appbar_edit": "Edit prevention course",
  "prevention_form_hero_new": "Start prevention.",
  "prevention_form_hero_edit": "Edit prevention.",
  "prevention_kind_filaria": "Heartworm prevention",
  "prevention_kind_flea_tick": "Flea & tick prevention",
  "prevention_kind_combo": "All-in-one",
  "prevention_form_chewable": "Chewable",
  "prevention_form_tablet": "Tablet",
  "prevention_form_spot_on": "Spot-on",
  "prevention_form_injection": "Injection (yearly)",
  "prevention_region_label": "Your region",
  "prevention_region_hokkaido": "Hokkaido",
  "prevention_region_tohoku": "Tohoku",
  "prevention_region_kanto": "Kanto",
  "prevention_region_chubu": "Chubu",
  "prevention_region_kansai": "Kansai",
  "prevention_region_chugoku_shikoku": "Chugoku & Shikoku",
  "prevention_region_kyushu": "Kyushu",
  "prevention_region_okinawa": "Okinawa",
  "prevention_region_custom": "Set manually",
  "prevention_period_label": "Prevention period",
  "prevention_period_value": "{start} – {end}",
  "prevention_period_year_round": "Year-round",
  "prevention_day_label": "Day of the month",
  "prevention_day_value": "Day {day} of each month",
  "prevention_time_label": "Notification time",
  "prevention_medicine_label": "Medicine name",
  "prevention_medicine_hint": "e.g. NexGard Spectra",
  "prevention_dosage_label": "Dosage",
  "prevention_dosage_hint": "e.g. 1 tablet / 1 pipette",
  "prevention_test_section": "Pre-season test",
  "prevention_test_done": "Tested",
  "prevention_test_not_yet": "Not yet",
  "prevention_test_date_label": "Test date",
  "prevention_test_reminder_label": "Remind me about the test",
  "prevention_test_status_done": "Tested on {date}",
  "prevention_test_status_pending": "Not tested yet",
  "prevention_progress_label": "{done} of {total}",
  "prevention_next_dose_label": "Next: {date}",
  "prevention_season_complete": "Season complete",
  "prevention_final_badge": "Final dose",
  "prevention_dose_status_upcoming": "Scheduled",
  "prevention_dose_status_due": "Today",
  "prevention_dose_status_overdue": "Missed",
  "prevention_dose_status_administered": "Given",
  "prevention_dose_status_skipped": "Skipped",
  "prevention_dose_sheet_title": "{month}",
  "prevention_dose_record_action": "Record dose",
  "prevention_dose_undo_action": "Undo record",
  "prevention_dose_skip_action": "Skip this dose",
  "prevention_dose_recorded_at": "Given on {date}",
  "prevention_orphan_section": "Records outside this course",
  "prevention_notify_due_title": "{petName}'s prevention day",
  "prevention_notify_due_body": "{kind} is scheduled for today.",
  "prevention_notify_followup_title": "{petName}'s prevention",
  "prevention_notify_followup_body": "Yesterday's dose hasn't been recorded.",
  "prevention_notify_final_title": "{petName}'s final dose of the season",
  "prevention_notify_final_body": "The last dose is scheduled for {date}.",
  "prevention_notify_test_title": "{petName}'s pre-season test",
  "prevention_notify_test_body": "Prevention starts in one month.",
  "prevention_notify_test_again_title": "{petName}'s pre-season test",
  "prevention_notify_test_again_body": "Prevention starts in one week.",
  "prevention_notify_next_season_title": "{petName}'s next season",
  "prevention_notify_next_season_body": "It may be time to set up this year's course.",
  "prevention_paywall_courses": "petlo Pro is required to add more prevention courses",
  "prevention_paywall_history": "petlo Pro is required to view past records",
  "prevention_delete_confirm_title": "Delete this course?",
  "prevention_delete_confirm_body": "Your dose records will be kept.",
  "prevention_disclaimer_period": "Prevention periods vary by region, climate, and the weather of a given year. These are general guidelines only. Please confirm the actual start and end dates with your veterinarian.",
  "prevention_disclaimer_test": "A test for existing infection may be required before starting prevention. Please follow your veterinarian's instructions.",
  "prevention_disclaimer_general": "petlo is a record-keeping and reminder app. It does not provide diagnosis, treatment, or medication instructions. Always consult a veterinarian for health decisions."
```

### 10.3 簡体字中国語 (`app_zh.arb`)

```json
  "prevention_section_title": "预防",
  "prevention_list_appbar": "预防管理",
  "prevention_list_empty": "还没有预防计划",
  "prevention_list_empty_action": "创建计划",
  "prevention_form_appbar_new": "新建预防计划",
  "prevention_form_appbar_edit": "编辑预防计划",
  "prevention_form_hero_new": "开始预防。",
  "prevention_form_hero_edit": "编辑预防。",
  "prevention_kind_filaria": "心丝虫预防",
  "prevention_kind_flea_tick": "跳蚤与蜱虫预防",
  "prevention_kind_combo": "综合预防",
  "prevention_form_chewable": "咀嚼片",
  "prevention_form_tablet": "药片",
  "prevention_form_spot_on": "滴剂",
  "prevention_form_injection": "注射（每年一次）",
  "prevention_region_label": "所在地区",
  "prevention_region_hokkaido": "北海道",
  "prevention_region_tohoku": "东北",
  "prevention_region_kanto": "关东",
  "prevention_region_chubu": "中部",
  "prevention_region_kansai": "关西",
  "prevention_region_chugoku_shikoku": "中国・四国",
  "prevention_region_kyushu": "九州",
  "prevention_region_okinawa": "冲绳",
  "prevention_region_custom": "手动设置",
  "prevention_period_label": "预防期间",
  "prevention_period_value": "{start}月 至 {end}月",
  "prevention_period_year_round": "全年",
  "prevention_day_label": "每月给药日",
  "prevention_day_value": "每月{day}日",
  "prevention_time_label": "提醒时间",
  "prevention_medicine_label": "药品名称",
  "prevention_medicine_hint": "例：尼可信全能",
  "prevention_dosage_label": "剂量",
  "prevention_dosage_hint": "例：1片 / 1支",
  "prevention_test_section": "季前检查",
  "prevention_test_done": "已检查",
  "prevention_test_not_yet": "尚未检查",
  "prevention_test_date_label": "检查日期",
  "prevention_test_reminder_label": "接收检查提醒",
  "prevention_test_status_done": "已于{date}检查",
  "prevention_test_status_pending": "尚未检查",
  "prevention_progress_label": "{done} / {total} 次",
  "prevention_next_dose_label": "下次 {date}",
  "prevention_season_complete": "本季已完成",
  "prevention_final_badge": "最后一次",
  "prevention_dose_status_upcoming": "计划中",
  "prevention_dose_status_due": "今天",
  "prevention_dose_status_overdue": "未给药",
  "prevention_dose_status_administered": "已给药",
  "prevention_dose_status_skipped": "已跳过",
  "prevention_dose_sheet_title": "{month}月",
  "prevention_dose_record_action": "记录给药",
  "prevention_dose_undo_action": "撤销记录",
  "prevention_dose_skip_action": "跳过这一次",
  "prevention_dose_recorded_at": "{date} 已给药",
  "prevention_orphan_section": "计划外的记录",
  "prevention_notify_due_title": "{petName} 的预防日",
  "prevention_notify_due_body": "今天是{kind}的预定日。",
  "prevention_notify_followup_title": "{petName} 的预防",
  "prevention_notify_followup_body": "昨天的给药尚未记录。",
  "prevention_notify_final_title": "{petName} 本季最后一次",
  "prevention_notify_final_body": "最后一次预定于{date}。",
  "prevention_notify_test_title": "{petName} 的季前检查",
  "prevention_notify_test_body": "距离预防开始还有一个月。",
  "prevention_notify_test_again_title": "{petName} 的季前检查",
  "prevention_notify_test_again_body": "距离预防开始还有一周。",
  "prevention_notify_next_season_title": "{petName} 的下一季",
  "prevention_notify_next_season_body": "可以准备今年的计划了。",
  "prevention_paywall_courses": "添加更多预防计划需要 petlo Pro",
  "prevention_paywall_history": "查看历史记录需要 petlo Pro",
  "prevention_delete_confirm_title": "要删除此计划吗？",
  "prevention_delete_confirm_body": "给药记录将会保留。",
  "prevention_disclaimer_period": "预防期间会因所在地区、气候以及当年气温而不同。此处显示的仅为一般参考。实际的开始与结束时间请向您的兽医确认。",
  "prevention_disclaimer_test": "开始预防前可能需要进行感染检查。请遵从兽医的指示。",
  "prevention_disclaimer_general": "petlo 是记录与提醒类应用，不提供诊断、治疗或用药指示。健康相关的判断请务必咨询兽医。"
```

> プレースホルダを持つキー (`{start}` `{done}` `{date}` `{petName}` 等) は
> 3 ファイルすべてで `placeholders` 定義を揃えること。`app_ja.arb` を
> テンプレートとして `@key` メタデータを記述する。

---

## 11. 既存コードへの変更点（全 8 箇所）

| # | ファイル | 変更内容 | 破壊性 |
|---:|:---|:---|:---|
| 1 | `data/local/database_enums.dart` | 新規 enum 4 つを**末尾に追記** | なし |
| 2 | `data/local/app_database.dart` | import / export / tables 配列 / onUpgrade に追記 | なし |
| 3 | `data/local/migrations/migrations.dart` | `currentVersion` 9 → 10、コメント追記 | なし |
| 4 | `core/constants/app_constants.dart` | 定数 2 つ追加、`appBuildNumber` 71 → 72 | なし |
| 5 | `core/notifications/notification_service.dart` | ID 採番ヘルパー 2 つを**末尾に追記** | なし |
| 6 | `core/notifications/notification_scheduler.dart` | `_kGlobalSlotBudget` を 2 定数に分割、`rescheduleAllPreventions` 呼び出しを追加 | **要回帰テスト** |
| 7 | `data/repositories/pets_repository.dart` | `petBoundTables` に 2 テーブル追加 | なし（追加のみ） |
| 8 | `presentation/screens/health/health_tab_screen.dart` | 予防セクションを追加 | なし |

### #7 の具体的な差分

```dart
    const List<String> petBoundTables = <String>[
      'meals', 'poops', 'pees', 'vomits',
      'weights', 'temperatures', 'bcs_checks',
      'diaries', 'visits', 'vaccinations',
      'medications', 'expiration_items',
      // build 72: 予防コース。両テーブルとも pet_id を持つので
      // 既存の一括論理削除ループにそのまま乗る。
      'prevention_courses', 'prevention_doses',
    ];
```

> `softDeletePet` は `SELECT id FROM $table WHERE pet_id = ? AND deleted_at IS NULL`
> で回すだけなので、両テーブルが `pet_id` / `deleted_at` を持っていれば
> 追加のコード変更は不要。だから `prevention_doses` に冗長な `petId` を持たせている。

### バックアップ系は変更不要

`backup_archive_service.dart` は sqlite ファイルを丸ごと固める方式なので、
新テーブルは自動的に含まれる。写真を持たないため `_photoSubdirs` の変更も不要。

---

## 12. 実装フェーズ（小バッチ）

各フェーズ完了ごとに検証してから次へ進む。まとめて実装しない。

### Phase 1 — データ層

- [ ] `database_enums.dart` に enum 4 つ追記
- [ ] `tables/prevention_courses.dart` 作成
- [ ] `tables/prevention_doses.dart` 作成
- [ ] `app_database.dart` の 4 箇所に追記
- [ ] `migrations.dart` の `currentVersion` を 10 に
- [ ] `onUpgrade` に `if (from < 10)` ブロック追加
- [ ] `flutter pub run build_runner build --delete-conflicting-outputs`
- [ ] `core/prevention/prevention_region_presets.dart` 作成
- [ ] `prevention_courses_repository.dart` / `prevention_doses_repository.dart` 作成
      （materialize / 再 materialize / 投与記録 / 取り消しを含む）

**検証**: v9 のデータを入れた端末に v10 を上書きインストール → 既存のペット・記録・
写真がすべて残っていること。新テーブルが空で作成されていること。

### Phase 2 — UI

- [ ] `prevention_providers.dart`
- [ ] コース一覧・作成フォーム・詳細画面
- [ ] 月グリッド / dose シート / 進捗バー
- [ ] 健康タブに予防セクション追加
- [ ] `AppIcons` に予防アイコンの SVG パス追加

**検証**: コース作成 → 月グリッド表示 → 投与記録 → 既存の投薬履歴にも反映される
ことを目視確認。

### Phase 3 — 通知

- [ ] `notification_service.dart` に ID 採番ヘルパー追加
- [ ] `prevention_notification_scheduler.dart` 作成
- [ ] `notification_scheduler.dart` のバジェット分割
- [ ] アプリ起動時の再スケジュール導線

**検証**: `NotificationService.pending()` を叩いて、予防が 12 slot 以内に
収まっていること・既存のワクチン通知と投薬通知が消えていないことを確認。

### Phase 4 — L10n / 課金 / 免責

- [ ] ARB 3 ファイルにキー追加 → `flutter gen-l10n`
- [ ] 課金ゲート実装（コース数 / 通知種別 / 履歴年数）
- [ ] 免責文の 4 箇所への配置
- [ ] `appBuildNumber` を 72 に

**検証**: 3 言語すべてで画面を一巡。ハードコード文字列ゼロを grep で確認。

### Phase 5 — 統合と回帰

- [ ] `pets_repository.dart` の cascade に 2 テーブル追加
- [ ] バックアップ書き出し → 復元 → 予防データが復元されること
- [ ] v9 バックアップを v10 アプリで復元 → 通る
- [ ] 既存機能の回帰（下記 §13）

---

## 13. 回帰テスト項目（**必須**）

| # | 項目 | 期待結果 |
|---:|:---|:---|
| 1 | v9 → v10 アップグレード | 既存のペット・全記録・写真が無傷 |
| 2 | 既存の投薬リマインダー通知 | v10 後も従来どおり発火する |
| 3 | ワクチン期限通知 | 予防通知追加後も枯渇しない |
| 4 | `pending()` の総数 | iOS で 64 未満に収まる |
| 5 | ペット論理削除 | 予防コースと dose も一緒に論理削除される |
| 6 | お別れ (`markAsParted`) | 予防データは**消えない**（記録は宝物） |
| 7 | バックアップ書き出し | zip 内 sqlite に予防テーブルが含まれる |
| 8 | v9 バックアップの復元 | 成功し、起動時に v10 migration が走る |
| 9 | コース期間の短縮 | 範囲外になった**投与済み** dose が消えない |
| 10 | 投与記録の取り消し | `medications` の該当行が論理削除される |
| 11 | 家族共有スコープ | `sync_queue` に予防の op が正しく積まれる |
| 12 | 無料プラン | 2 件目のコース作成でペイウォールが出る |

**特に #9 と #6 は必ず手で確認すること。** ここが壊れるとユーザーデータが
静かに失われる。

---

## 14. ファイル別チェックリスト（既存ルール準拠）

各ファイル完成ごとに以下を確認:

- [ ] import のパス深度は正しいか
- [ ] enum 名が `dart:ui` 等と衝突していないか
- [ ] 永続化に `jsonEncode` を使っているか（`.toString()` 禁止）
- [ ] `pubspec.yaml` への追加は不要か（本機能は新規依存なし）
- [ ] UI 文字列はすべて L10n キー経由か
- [ ] Bundle ID は `mamonis.studio.petlo` のままか
- [ ] 未使用 import が残っていないか
- [ ] `withOpacity()` ではなく `withValues()` を使っているか
- [ ] TODO / 未実装のスタブが 1 つも残っていないか
- [ ] 絵文字を使っていないか（SVG アイコンのみ）

---

## 15. 将来課題（本ビルドでは実装しない）

- `pet_context_builder.dart` に「今シーズンの予防状況」を追加し、AI チャットが
  飲み忘れに触れられるようにする
- 予防記録の CSV / PDF 書き出し（通院時に見せる用途）
- 前年コースからの「今年もこれで」ワンタップ複製
- `expiration_items` 死にテーブルの棚卸しと撤去
- `ScheduleRecurrence.monthly` / `yearly` を scheduler 側で実装（別チケット）
