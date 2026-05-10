// ============================================================================
// petlo - Color Tokens
// ============================================================================
//
// rev5.5仕様§4.3, §10で確定した配色トークン。
// モック (petlo_mock.html) のCSS変数と1:1対応する。
//
// Light/Dark両対応、ロケール非依存。
// 警告色のみ、彩度を最小限に抑えた「冷たい」エディトリアル振り。
//
// ============================================================================

import 'package:flutter/material.dart';

/// petlo のすべての色トークン。
///
/// 各色は Light/Dark 両方の値を持つ。
/// 使用時は `AppColors.fg.resolve(brightness)` のように呼ぶ、
/// または `Theme.of(context).extension<AppColors>()` 経由で取得する
/// (これは [AppColors.of] ヘルパーに集約)。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.bgSoft,
    required this.bgWarm,
    required this.fg,
    required this.fgMuted,
    required this.fgFaint,
    required this.line,
    required this.accentWarn,
    required this.accentDanger,
    required this.accentSoft,
    required this.canvas,
  });

  /// メイン背景。すべての画面の主要素背景。
  final Color bg;

  /// やや沈んだ背景。バックアップ警告バナー、選択中ピル、無効ボタン背景など。
  final Color bgSoft;

  /// メモリアル(お別れ)モード専用の温かみある背景。
  final Color bgWarm;

  /// メイン文字色。すべての本文・見出し。
  final Color fg;

  /// 補助文字色。eyebrow、説明文、メタ情報。
  final Color fgMuted;

  /// 最弱文字色。フッター、月外日付、装飾的なドット。
  final Color fgFaint;

  /// 罫線、区切り、輪郭。
  final Color line;

  /// 警告色(amber)。注意喚起、要観察、軽微な異常。
  final Color accentWarn;

  /// 至急色(crimson)。緊急、要受診、致命色。
  final Color accentDanger;

  /// 穏やかなアクセント(soft green)。スイッチON、成功、健康範囲。
  final Color accentSoft;

  /// 画面の最外殻のキャンバス色 (phone shellの背景)。
  /// アプリ内では基本見えない。デバッグ・モック用。
  final Color canvas;

  // ===== Light =====
  static const AppColors light = AppColors(
    bg: Color(0xFFFFFFFF),
    bgSoft: Color(0xFFFAFAF7),
    bgWarm: Color(0xFFF4EFE6),
    fg: Color(0xFF0A0A0A),
    fgMuted: Color(0xFF6B6B6B),
    fgFaint: Color(0xFFB8B8B8),
    line: Color(0xFFE8E6E0),
    accentWarn: Color(0xFFC24A00),
    accentDanger: Color(0xFF9B0F0F),
    accentSoft: Color(0xFF2B5F4A),
    canvas: Color(0xFFEDEAE3),
  );

  // ===== Dark =====
  static const AppColors dark = AppColors(
    bg: Color(0xFF0A0A0A),
    bgSoft: Color(0xFF141413),
    bgWarm: Color(0xFF1A1714),
    fg: Color(0xFFF5F2EC),
    fgMuted: Color(0xFF888683),
    fgFaint: Color(0xFF444240),
    line: Color(0xFF2A2826),
    accentWarn: Color(0xFFFFA040),
    accentDanger: Color(0xFFFF6B6B),
    accentSoft: Color(0xFF7BA88E),
    canvas: Color(0xFF050505),
  );

  /// 現在のBuildContextからAppColorsを取り出す便利ヘルパー。
  static AppColors of(BuildContext context) {
    final AppColors? colors = Theme.of(context).extension<AppColors>();
    if (colors == null) {
      throw FlutterError(
        'AppColors extension not found in current Theme. '
        'Make sure AppTheme.light()/dark() is applied.',
      );
    }
    return colors;
  }

  // ===== ThemeExtension implementation =====

  @override
  AppColors copyWith({
    Color? bg,
    Color? bgSoft,
    Color? bgWarm,
    Color? fg,
    Color? fgMuted,
    Color? fgFaint,
    Color? line,
    Color? accentWarn,
    Color? accentDanger,
    Color? accentSoft,
    Color? canvas,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      bgSoft: bgSoft ?? this.bgSoft,
      bgWarm: bgWarm ?? this.bgWarm,
      fg: fg ?? this.fg,
      fgMuted: fgMuted ?? this.fgMuted,
      fgFaint: fgFaint ?? this.fgFaint,
      line: line ?? this.line,
      accentWarn: accentWarn ?? this.accentWarn,
      accentDanger: accentDanger ?? this.accentDanger,
      accentSoft: accentSoft ?? this.accentSoft,
      canvas: canvas ?? this.canvas,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      bgSoft: Color.lerp(bgSoft, other.bgSoft, t)!,
      bgWarm: Color.lerp(bgWarm, other.bgWarm, t)!,
      fg: Color.lerp(fg, other.fg, t)!,
      fgMuted: Color.lerp(fgMuted, other.fgMuted, t)!,
      fgFaint: Color.lerp(fgFaint, other.fgFaint, t)!,
      line: Color.lerp(line, other.line, t)!,
      accentWarn: Color.lerp(accentWarn, other.accentWarn, t)!,
      accentDanger: Color.lerp(accentDanger, other.accentDanger, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
    );
  }
}
