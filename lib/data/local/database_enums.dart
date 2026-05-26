// ============================================================================
// petlo - Database Enums
// ============================================================================
//
// driftテーブルで使う列挙型を集約。
// すべてDBにはString(name)で保存、コード側ではenumで安全に扱う。
//
// 命名規則: テーブル名_列名Enum で揃える(例: PetType, PoopForm)
//
// ============================================================================

import 'package:drift/drift.dart' show JsonKey;

// ============================================================================
// Pets
// ============================================================================

/// ペットの種別
enum PetType {
  @JsonKey('dog')
  dog,
  @JsonKey('cat')
  cat;
}

/// ペットの性別
enum PetSex {
  male,
  female,
  unknown;
}

// ============================================================================
// Records (Meals, Poops, Pees, Vomits)
// ============================================================================

/// 食いつき (5段階)
enum MealAppetite {
  /// 完食
  ate_all,
  /// よく食べた
  ate_well,
  /// 普通
  ate_normal,
  /// 少し残した
  left_some,
  /// ほとんど食べなかった
  refused;
}

/// うんちのブリストル分類 (5段階、犬猫向けに簡略化)
/// 1=硬い、3=正常、5=水様
enum PoopForm {
  /// 1. 硬い小球
  hard,
  /// 2. ゴツゴツ
  lumpy,
  /// 3. 正常 (推奨)
  normal,
  /// 4. やや軟らかい
  soft,
  /// 5. 水様
  watery;
}

/// うんちの色 (rev5: 5色)
/// rev5.5: 嘔吐色は別enumで2階層化、うんちは5色のままでOK
enum PoopColor {
  brown,    // 正常
  black,    // 至急
  red,      // 至急
  yellow,   // 注意
  pale;     // 注意
}

/// うんちの量 (3段階)
enum RecordAmount {
  little,
  normal,
  alot;
}

/// おしっこの色
enum PeeColor {
  pale_yellow,   // 正常薄め
  yellow,        // 正常
  dark_yellow,   // やや濃い
  amber,         // 濃い (注意)
  red,           // 血尿 (至急)
  cloudy;        // 濁り (注意)
}

/// 嘔吐の色 (rev5.5: 2階層化)
/// メイン4色 + Other経由で詳細5色
enum VomitColor {
  // ===== Main 4 (メイン) =====
  clear,         // 透明 (胃液)
  yellow,        // 黄 (胆汁)
  brown,         // 茶
  food,          // 食べ物まじり
  // ===== Other 5 (詳細) =====
  white_foam,    // 白い泡
  red,           // 血混入 (至急)
  green,         // 緑色
  black,         // 黒 (至急)
  other;         // 自由記述

  /// メイン4色か?(他はOther経由で選ぶ)
  bool get isMain {
    switch (this) {
      case VomitColor.clear:
      case VomitColor.yellow:
      case VomitColor.brown:
      case VomitColor.food:
        return true;
      default:
        return false;
    }
  }

  /// 緊急度(色覚異常配慮で文字併記)
  VomitUrgency get urgency {
    switch (this) {
      case VomitColor.red:
      case VomitColor.black:
        return VomitUrgency.urgent;
      case VomitColor.yellow:
      case VomitColor.green:
      case VomitColor.white_foam:
        return VomitUrgency.caution;
      default:
        return VomitUrgency.normal;
    }
  }
}

enum VomitUrgency {
  normal,
  caution,
  urgent;
}

// ============================================================================
// Health
// ============================================================================

/// 体重単位
enum WeightUnit {
  kg,
  lb;
}

/// 体温単位
enum TemperatureUnit {
  celsius,
  fahrenheit;
}

/// BCS (Body Condition Score) — 5段階
enum BcsScore {
  veryThin,    // 1: 痩せすぎ
  thin,        // 2: やや痩せ
  ideal,       // 3: 理想
  overweight,  // 4: やや太り
  obese;       // 5: 肥満
}

// ============================================================================
// Reminders & Plans
// ============================================================================

/// リマインダー種別
enum ReminderKind {
  vaccination,    // ワクチン
  filaria,        // フィラリア予防
  flea_tick,      // ノミダニ予防
  grooming,       // トリミング
  checkup,        // 健康診断
  birthday,       // 誕生日
  custom;         // カスタム
}

/// リマインダー前通知タイミング
enum ReminderLeadTime {
  on_day,         // 当日
  three_days,     // 3日前
  one_week;       // 1週間前
}

// ============================================================================
// Group / Sharing (rev5.3)
// ============================================================================

/// グループメンバーの権限 (rev5.3)
enum MemberPermission {
  owner,    // 全権
  editor,   // 編集可
  viewer;   // 閲覧のみ
}

/// グループの状態
enum GroupStatus {
  active,
  pendingDeletion,    // rev5.5: Pro解約30日カウントダウン中
  frozen,             // 30-90日: 操作不可、閲覧のみ
  deletionScheduled;  // 90日後物理削除待ち
}

/// 招待コードの状態
enum InviteCodeStatus {
  active,
  used,
  expired,
  cancelled;
}

// ============================================================================
// Sync (rev5.4)
// ============================================================================

/// 同期キューのレコード状態
enum SyncStatus {
  /// 未同期(これからpush予定)
  pending,
  /// 同期中(送信中)
  syncing,
  /// 同期成功
  synced,
  /// 同期失敗(リトライ待ち)
  failed,
  /// 競合発生(手動解決待ち、v1.0では自動last-write-wins)
  conflict;
}

/// 同期キューの操作種別
enum SyncOperation {
  insert,
  update,
  delete;
}

/// アップロード対象種別 (rev5.4: upload_queue)
enum UploadKind {
  photo,
  ai_image_diagnosis;
}

// ============================================================================
// AI (rev5.5)
// ============================================================================

/// AIメッセージの送信元
enum AiMessageRole {
  user,
  assistant,
  system;
}

/// AIフィードバック
enum AiFeedback {
  none,
  thumb_up,
  thumb_down;
}

// ============================================================================
// Memorial (rev5.4)
// ============================================================================

/// メモリアルモード(お別れ後)の通知頻度
///
/// build 47 で `yearly` (年命日) を追加。既存行は 'off' / 'monthly'
/// の文字列で保存されているだけなので、enum メンバを足してもマイグレーション
/// は不要 (AppEnumConverter は values から名前ベースで解決)。
enum MemorialNotifyFrequency {
  off,
  monthly,     // 月命日
  yearly;      // 年命日
}

// ============================================================================
// Schedule (build 5)
// ============================================================================

/// 予定の種類
enum ScheduleCategory {
  vaccination,   // 健康
  medication,    // 健康
  visit,         // 健康(通院)
  grooming,      // 日常
  meal,          // 日常
  birthday,      // 思い出
  memorial,      // 思い出(命日)
  anniversary,   // 思い出(記念日)
  custom,        // 日常
  urgent;        // 緊急
}

/// 予定の繰り返しパターン
enum ScheduleRecurrence {
  none,
  daily,
  weekly,
  monthly,
  yearly;
}

/// 予定の通知タイミング
enum ScheduleNotificationTiming {
  none,
  on_day,
  day_before,
  week_before;
}

/// 自動生成されたスケジュールのソース
/// 自動生成: ペット birthday などから生成 → ペット削除/編集で連動
enum ScheduleSourceType {
  manual,         // ユーザー手動作成
  pet_birthday,   // ペット birthday から自動生成
  pet_memorial;   // ペットお別れ日から自動生成 (将来用)
}
