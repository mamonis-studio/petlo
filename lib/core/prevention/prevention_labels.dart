// ============================================================================
// petlo - Prevention Labels
// ============================================================================
//
// 予防コース (build 72) の enum → 表示名の解決を一箇所に集約する。
// UI と通知スケジューラの両方から使うため core に置く。
//
// ハードコード文字列は 1 つも持たない。すべて l10n キー経由。
//
// 月ラベルだけは locale ごとに扱いが違う:
//   ARB の "prevention_period_value" が ja/zh では "{start}月" と月を
//   数字前提で書いているのに対し、en は "{start} – {end}" と月名前提。
//   そのため monthLabel() は en のときだけ月名を返す。
//
// ============================================================================

import 'package:intl/intl.dart';

import '../../data/local/database_enums.dart';
import '../../l10n/generated/app_localizations.dart';

abstract final class PreventionLabels {
  PreventionLabels._();

  /// 予防の種別
  static String kind(PreventionKind value, AppLocalizations l10n) {
    switch (value) {
      case PreventionKind.filaria:
        return l10n.prevention_kind_filaria;
      case PreventionKind.flea_tick:
        return l10n.prevention_kind_flea_tick;
      case PreventionKind.combo:
        return l10n.prevention_kind_combo;
    }
  }

  /// 剤型
  static String form(PreventionForm value, AppLocalizations l10n) {
    switch (value) {
      case PreventionForm.chewable:
        return l10n.prevention_form_chewable;
      case PreventionForm.tablet:
        return l10n.prevention_form_tablet;
      case PreventionForm.spot_on:
        return l10n.prevention_form_spot_on;
      case PreventionForm.injection:
        return l10n.prevention_form_injection;
    }
  }

  /// 地域プリセット
  static String region(PreventionRegion value, AppLocalizations l10n) {
    switch (value) {
      case PreventionRegion.hokkaido:
        return l10n.prevention_region_hokkaido;
      case PreventionRegion.tohoku:
        return l10n.prevention_region_tohoku;
      case PreventionRegion.kanto:
        return l10n.prevention_region_kanto;
      case PreventionRegion.chubu:
        return l10n.prevention_region_chubu;
      case PreventionRegion.kansai:
        return l10n.prevention_region_kansai;
      case PreventionRegion.chugoku_shikoku:
        return l10n.prevention_region_chugoku_shikoku;
      case PreventionRegion.kyushu:
        return l10n.prevention_region_kyushu;
      case PreventionRegion.okinawa:
        return l10n.prevention_region_okinawa;
      case PreventionRegion.custom:
        return l10n.prevention_region_custom;
    }
  }

  /// 1 回分の状態
  static String doseStatus(PreventionDoseStatus value, AppLocalizations l10n) {
    switch (value) {
      case PreventionDoseStatus.upcoming:
        return l10n.prevention_dose_status_upcoming;
      case PreventionDoseStatus.due:
        return l10n.prevention_dose_status_due;
      case PreventionDoseStatus.overdue:
        return l10n.prevention_dose_status_overdue;
      case PreventionDoseStatus.administered:
        return l10n.prevention_dose_status_administered;
      case PreventionDoseStatus.skipped:
        return l10n.prevention_dose_status_skipped;
    }
  }

  /// 月 (1-12) の表示ラベル。
  /// en は月名 ("May")、ja / zh は数字 ("5") を返す。
  /// ARB 側の書式 ("{start}月" vs "{start}") に合わせるため。
  static String monthLabel(int month, String localeTag) {
    if (localeTag.toLowerCase().startsWith('en')) {
      return DateFormat.MMM('en').format(DateTime(2000, month));
    }
    return '$month';
  }

  /// 単位付きの月表示。ja / zh は「5月」、en は「May」。
  ///
  /// ステッパーに裸の数字だけを出すと、開始と終了のどちらを触っているのか
  /// 読み取れないため、値そのものに単位を持たせる。
  static String monthValue(
    int month,
    AppLocalizations l10n,
    String localeTag,
  ) {
    return l10n.prevention_month_value(monthLabel(month, localeTag));
  }

  /// 予防期間の表示。通年 (1-12月) は専用文言にする。
  static String period({
    required int startMonth,
    required int endMonth,
    required AppLocalizations l10n,
    required String localeTag,
  }) {
    if (startMonth == 1 && endMonth == 12) {
      return l10n.prevention_period_year_round;
    }
    return l10n.prevention_period_value(
      monthLabel(startMonth, localeTag),
      monthLabel(endMonth, localeTag),
    );
  }
}
