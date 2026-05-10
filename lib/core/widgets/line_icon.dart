// ============================================================================
// petlo - LineIcon
// ============================================================================
//
// 1.4px ストロークの線画アイコンを描画する CustomPainter ベースのウィジェット。
// rev3 で確定: stroke 1.4px、22x22 viewBox、丸い線端、丸い角接合。
//
// アイコン本体は app_icons.dart で個別に定義する。
// このファイルは描画の枠組みのみ提供。
//
// 使い方:
// ```dart
// LineIcon(icon: AppIcons.meal, size: 22)
// ```
//
// ============================================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

/// 個別のアイコンが実装する型。
/// CustomPainter の paint() に対応する関数。
typedef IconPathPainter = void Function(Canvas canvas, Size size, Paint paint);

/// 線画アイコンの定義。
/// - viewBoxSize: 元のSVG viewBoxのサイズ (基本24)
/// - paint: 描画ロジック
class LineIconData {
  const LineIconData({
    required this.paint,
    this.viewBoxSize = 24,
    this.semanticLabel,
  });

  final IconPathPainter paint;
  final double viewBoxSize;
  final String? semanticLabel;
}

class LineIcon extends StatelessWidget {
  const LineIcon({
    required this.icon,
    this.size = AppDimensions.iconStandard,
    this.color,
    this.strokeWidth = AppDimensions.strokeIcon,
    this.semanticLabel,
    super.key,
  });

  final LineIconData icon;
  final double size;

  /// nullの場合は AppColors.fg を使用
  final Color? color;

  final double strokeWidth;

  /// VoiceOver用ラベル。アイコンのラベルが意味を持つ場合のみ指定。
  /// 装飾的なアイコンは null のままにし、親側で `ExcludeSemantics` する。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color resolvedColor = color ?? AppColors.of(context).fg;
    final String? label = semanticLabel ?? icon.semanticLabel;

    return Semantics(
      label: label,
      excludeSemantics: label == null,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _LineIconPainter(
            data: icon,
            color: resolvedColor,
            strokeWidth: strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _LineIconPainter extends CustomPainter {
  _LineIconPainter({
    required this.data,
    required this.color,
    required this.strokeWidth,
  });

  final LineIconData data;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // viewBoxからサイズへスケール
    final double scale = size.width / data.viewBoxSize;
    canvas.save();
    canvas.scale(scale);

    data.paint(canvas, Size(data.viewBoxSize, data.viewBoxSize), paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LineIconPainter oldDelegate) {
    return data != oldDelegate.data ||
        color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth;
  }
}
