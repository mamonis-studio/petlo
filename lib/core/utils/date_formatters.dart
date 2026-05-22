// ============================================================================
// petlo - Date Formatters (locale-aware)
// ============================================================================
//
// build 36 (M2) で導入。複数箇所に散らばっていた自前の `'${y}.${m}.${d}'`
// 系の整形コードを intl.DateFormat に統一する。
//
// 設計:
//   - `BuildContext` ではなく `localeTag` (e.g. 'ja' / 'en' / 'zh') を引数に
//     取る。これにより:
//       1. Widget 内: `Localizations.localeOf(context).toLanguageTag()` を渡す
//       2. Widget 外 (controller / state): 呼び出し側から localeTag を受け取り
//          そのまま伝播 (build 34 の `validate(l10n)` パターンと同じ思想)
//   - DateFormat の各スケルトン (`yMMMMd` / `MMMd` / `Md` / `yMd` / `y`) は
//     ICU 仕様で locale ごとに自動でフィールド順を切り替える。
//     ja: '2026年5月20日', en: 'May 20, 2026', zh: '2026年5月20日'
//   - 時刻は 24h 表記 (`Hm`) で統一。AM/PM は `jm` に切り替えれば追従する。
//
// ============================================================================

import 'package:intl/intl.dart';

/// 完全日付 (year + long month + day)。
/// ja: '2026年5月20日' / en: 'May 20, 2026' / zh: '2026年5月20日'
String formatFullDate(DateTime d, String localeTag) =>
    DateFormat.yMMMMd(localeTag).format(d);

/// 月日 (long month + day)。年なし、表示順は locale 追従。
/// ja: '5月20日' / en: 'May 20' / zh: '5月20日'
String formatMonthDay(DateTime d, String localeTag) =>
    DateFormat.MMMd(localeTag).format(d);

/// 月日 (数字のみ、コンパクト)。チャート軸など狭い場所向け。
/// ja: '5/20' / en: '5/20' / zh: '5/20'
String formatMonthDayShort(DateTime d, String localeTag) =>
    DateFormat.Md(localeTag).format(d);

/// 年月 (数字のみ、コンパクト)。
/// ja: '2026/5' / en: '5/2026' / zh: '2026/5'
String formatYearMonthShort(DateTime d, String localeTag) =>
    DateFormat.yM(localeTag).format(d);

/// 年のみ。
String formatYear(DateTime d, String localeTag) =>
    DateFormat.y(localeTag).format(d);

/// 日時 (yMd + Hm)。区切りはスペース。
/// ja: '2026/5/20 14:30' / en: '5/20/2026 14:30' / zh: '2026/5/20 14:30'
String formatDateTime(DateTime d, String localeTag) =>
    '${DateFormat.yMd(localeTag).format(d)} ${DateFormat.Hm().format(d)}';
