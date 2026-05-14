// ============================================================================
// petlo - PetloLineChart
// ============================================================================
//
// fl_chart をエディトリアル風にカスタムした折れ線グラフ。
//
// 特徴:
//   - 黒白基調、データ点は黒丸、線は1.5px stroke
//   - グリッドは横線のみ(縦は無し、すっきり)
//   - 正常範囲帯(オプション、体温用): 薄い背景でゾーン表示
//   - 値が1点以下なら "Not enough data" 表示
//
// ============================================================================

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/chart_range.dart';

class PetloLineChart extends StatelessWidget {
  const PetloLineChart({
    required this.points,
    required this.range,
    this.unitLabel = '',
    this.normalRangeMin,
    this.normalRangeMax,
    this.height = 220,
    this.yAxisFormatter,
    super.key,
  });

  final List<ChartPoint> points;
  final ChartRange range;
  final String unitLabel;

  /// 正常範囲の下限(あれば帯表示)
  final double? normalRangeMin;

  /// 正常範囲の上限
  final double? normalRangeMax;

  final double height;

  /// Y軸のラベルカスタムフォーマッタ(例: kg小数2桁)
  final String Function(double)? yAxisFormatter;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            points.isEmpty
                ? 'No data yet'
                : 'Need at least 2 records to show trend',
            style: typo.bodySmall.copyWith(color: colors.fgMuted),
          ),
        ),
      );
    }

    // FlSpot に変換
    final List<FlSpot> spots = points
        .map((p) => FlSpot(p.timestamp.toDouble(), p.value))
        .toList();

    // X軸範囲
    final double minX = spots.first.x;
    final double maxX = spots.last.x;

    // Y軸範囲(値の最小最大に余白を加える)
    double minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    double maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    if (normalRangeMin != null && normalRangeMin! < minY) {
      minY = normalRangeMin!;
    }
    if (normalRangeMax != null && normalRangeMax! > maxY) {
      maxY = normalRangeMax!;
    }
    final double yRange = maxY - minY;
    final double yPad = yRange == 0 ? 1.0 : yRange * 0.15;
    minY -= yPad;
    maxY += yPad;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          backgroundColor: colors.bg,

          // ===== グリッド (横線のみ) =====
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yRange == 0 ? 1.0 : yRange / 4,
            getDrawingHorizontalLine: (double v) => FlLine(
              color: colors.line,
              strokeWidth: 1,
              dashArray: const <int>[2, 4],
            ),
          ),

          // ===== ボーダー =====
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(color: colors.fgMuted, width: 1),
              bottom: BorderSide(color: colors.fgMuted, width: 1),
            ),
          ),

          // ===== タイトル =====
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                interval: yRange == 0 ? 1.0 : yRange / 2,
                getTitlesWidget: (double value, TitleMeta meta) {
                  if (value < minY + yPad / 2 || value > maxY - yPad / 2) {
                    return const SizedBox.shrink();
                  }
                  final String label = yAxisFormatter != null
                      ? yAxisFormatter!(value)
                      : value.toStringAsFixed(1);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 9,
                        letterSpacing: 9 * 0.15,
                        color: colors.fgMuted,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (maxX - minX) / 4,
                getTitlesWidget: (double value, TitleMeta meta) {
                  // 端は省略
                  if (value <= minX || value >= maxX) {
                    return const SizedBox.shrink();
                  }
                  final DateTime t =
                      DateTime.fromMillisecondsSinceEpoch(value.toInt());
                  final String label = _formatDateForRange(t, range);
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 9,
                        letterSpacing: 9 * 0.15,
                        color: colors.fgMuted,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ===== 正常範囲ゾーン (背景) =====
          extraLinesData: ExtraLinesData(
            horizontalLines: <HorizontalLine>[
              if (normalRangeMin != null)
                HorizontalLine(
                  y: normalRangeMin!,
                  color: colors.fgFaint,
                  strokeWidth: 0.8,
                  dashArray: const <int>[3, 3],
                ),
              if (normalRangeMax != null)
                HorizontalLine(
                  y: normalRangeMax!,
                  color: colors.fgFaint,
                  strokeWidth: 0.8,
                  dashArray: const <int>[3, 3],
                ),
            ],
          ),

          // ===== 線 + 点 =====
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: colors.fg,
              barWidth: 1.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (FlSpot s, double xp, LineChartBarData bar,
                        int idx) =>
                    FlDotCirclePainter(
                  radius: 2.5,
                  color: colors.fg,
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(show: false),
            ),
          ],

          // ===== タッチで値表示 =====
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (LineBarSpot s) => colors.fg,
              tooltipBorder: BorderSide.none,
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tooltipMargin: 8,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (List<LineBarSpot> spots) {
                return spots.map((LineBarSpot s) {
                  final DateTime t =
                      DateTime.fromMillisecondsSinceEpoch(s.x.toInt());
                  final String label = yAxisFormatter != null
                      ? yAxisFormatter!(s.y)
                      : s.y.toStringAsFixed(1);
                  return LineTooltipItem(
                    '$label$unitLabel\n${t.month}/${t.day}',
                    TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 10 * 0.15,
                      color: colors.bg,
                      height: 1.4,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  String _formatDateForRange(DateTime t, ChartRange range) {
    switch (range) {
      case ChartRange.month1:
      case ChartRange.month3:
        // 月/日
        return '${t.month}/${t.day}';
      case ChartRange.month6:
      case ChartRange.year1:
        // 年/月
        return '${t.year.toString().substring(2)}/${t.month}';
      case ChartRange.all:
        return '${t.year}';
    }
  }
}
