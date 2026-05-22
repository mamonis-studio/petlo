// ============================================================================
// petlo - EmptyState
// ============================================================================
//
// 「中身が空っぽ」を伝える画面・セクションの共通レイアウト。
//
// build 38 で導入。それまで home / groups_list / medication_reminders / gallery
// などで微妙に違う Column + Fraunces italic + (任意の) サブコピー + (任意の) CTA
// を各画面で個別実装していたのを集約した。
//
// 設計指針:
//   - props は `title` のみ必須。subtitle / eyebrow / cta / secondaryCta は任意。
//   - 既存実装の最大公約数: Fraunces italic, 28-36pt のヒーロー文字 +
//     bodyMedium fgMuted のサブコピー。本 widget は 28pt をデフォルトに、
//     画面ごとに `titleSize` で上書き。
//   - 余白・配色のレアな差分は props で吸収する (`titleColor`,
//     `crossAxisAlignment`, `paddingVertical`)。これ以上の差分は呼び出し側で
//     inline 実装で構わない (過剰一般化を避ける)。
//   - アイコン枠は v1.0 のデザインでは線画警告アイコン等が個別にあるだけで、
//     empty state に統一アイコンは無いので未提供。必要になったら slot 追加。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/eyebrow_text.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.titleSize = 28,
    this.titleColor,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.textAlign,
    this.cta,
    this.secondaryCta,
    this.secondaryCtaNote,
    this.paddingVertical = 40,
    this.paddingHorizontal = 0,
    super.key,
  });

  /// ヒーロー文字 (Fraunces italic)。
  final String title;

  /// サブコピー。bodyMedium fgMuted。改行込みで複数行を想定。
  final String? subtitle;

  /// 任意の上部ラベル (e.g. "EMPTY")。EyebrowText.small で描画。
  final String? eyebrow;

  /// ヒーロー文字のサイズ。既存実装の幅 = 28 / 32 / 36。
  final double titleSize;

  /// ヒーロー文字色。省略時は fgMuted (低彩度バリアント)、
  /// home のように主役級なら colors.fg を明示指定する。
  final Color? titleColor;

  /// Column の cross-axis 揃え。
  final CrossAxisAlignment crossAxisAlignment;

  /// Text 自体の text-align。`crossAxisAlignment = center` なら center を
  /// 渡すのが定石。省略時は start。
  final TextAlign? textAlign;

  /// メイン CTA (任意)。PrimaryButton を想定。
  final Widget? cta;

  /// 二次 CTA (任意)。OutlinedActionButton 等。
  final Widget? secondaryCta;

  /// 二次 CTA の下に表示する補足説明文 (bodySmall fgFaint)。
  final String? secondaryCtaNote;

  /// 上下パディング (default 40)。
  final double paddingVertical;

  /// 左右パディング (default 0、呼び出し側のスクロール領域に合わせる前提)。
  final double paddingHorizontal;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final Color effectiveTitleColor = titleColor ?? colors.fgMuted;
    final TextAlign effectiveAlign = textAlign ??
        (crossAxisAlignment == CrossAxisAlignment.center
            ? TextAlign.center
            : TextAlign.start);

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: paddingVertical,
        horizontal: paddingHorizontal,
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (eyebrow != null) ...<Widget>[
            EyebrowText(eyebrow!),
            const SizedBox(height: 8),
          ],
          Text(
            title,
            textAlign: effectiveAlign,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: titleSize,
              // 36pt 級は letter-spacing/height を詰めると印刷物の佇まいに近づく
              letterSpacing: titleSize >= 32 ? -titleSize * 0.04 : 0,
              height: titleSize >= 32 ? 0.95 : null,
              color: effectiveTitleColor,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            SizedBox(height: titleSize >= 32 ? 16 : 8),
            Text(
              subtitle!,
              textAlign: effectiveAlign,
              style: typo.bodyMedium.copyWith(
                color: colors.fgMuted,
                height: 1.6,
              ),
            ),
          ],
          if (cta != null) ...<Widget>[
            const SizedBox(height: 24),
            cta!,
          ],
          if (secondaryCta != null) ...<Widget>[
            const SizedBox(height: 12),
            secondaryCta!,
          ],
          if (secondaryCtaNote != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              secondaryCtaNote!,
              textAlign: effectiveAlign,
              style: typo.bodySmall.copyWith(
                color: colors.fgFaint,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
