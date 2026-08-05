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
