// ============================================================================
// petlo - Weight Chart Screen
// ============================================================================
//
// 体重推移グラフの専用画面。Health タブから push される。
//
// 構成:
//   - AppBar: WEIGHT TREND
//   - エディトリアル ヒーロー: "Weight, over time."
//   - 最新値表示 (Fraunces 大、サブで日付)
//   - ChartRangeSelector (1M/3M/6M/1Y/ALL — 無料は3Mまで)
//   - PetloLineChart
//   - 下部に履歴リスト(最新10件)
//
// rev3 F-06: 体重 + 推移グラフ
// rev5: 無料3ヶ月、Pro全期間
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/models/chart_range.dart';
import '../../providers/chart_provider.dart';
import '../../widgets/charts/chart_range_selector.dart';
import '../../widgets/charts/petlo_line_chart.dart';
import '../weight/weight_record_screen.dart';

class WeightChartScreen extends ConsumerStatefulWidget {
  const WeightChartScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const WeightChartScreen(),
      ),
    );
  }

  @override
  ConsumerState<WeightChartScreen> createState() =>
      _WeightChartScreenState();
}

class _WeightChartScreenState extends ConsumerState<WeightChartScreen> {
  ChartRange _range = ChartRange.month3;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final AsyncValue<List<WeightEntity>> dataAsync =
        ref.watch(weightChartProvider(_range));

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'WEIGHT TREND',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.fg),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionLabel(
                AppLocalizations.of(context).common_trend,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              ),

              // ===== Latest value =====
              dataAsync.maybeWhen(
                data: (List<WeightEntity> list) =>
                    _LatestValueHeader(history: list),
                orElse: () => const SizedBox(height: 56),
              ),
              const SizedBox(height: 24),

              // ===== Range selector =====
              ChartRangeSelector(
                current: _range,
                onChanged: (ChartRange r) => setState(() => _range = r),
              ),
              const SizedBox(height: 16),

              // ===== Chart =====
              dataAsync.when(
                data: (List<WeightEntity> list) {
                  final List<ChartPoint> points = list.map((WeightEntity w) {
                    return ChartPoint(
                      timestamp: w.measuredAt,
                      // g → kg に変換して表示
                      value: w.weightG / 1000.0,
                    );
                  }).toList();

                  return PetloLineChart(
                    points: points,
                    range: _range,
                    unitLabel: ' kg',
                    yAxisFormatter: _formatKg,
                  );
                },
                loading: () => const SizedBox(
                  height: 220,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                ),
                error: (Object e, _) => SizedBox(
                  height: 220,
                  child: Center(
                    child: Text(
                      'Failed to load data',
                      style: typo.bodySmall.copyWith(color: colors.fgMuted),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ===== History list =====
              SectionLabel(AppLocalizations.of(context).common_history),
              const SizedBox(height: 12),
              dataAsync.maybeWhen(
                data: (List<WeightEntity> list) {
                  if (list.isEmpty) {
                    return Text(
                      'No records in this range.',
                      style: typo.bodySmall.copyWith(color: colors.fgMuted),
                    );
                  }
                  // 新しい順に最大10件
                  final List<WeightEntity> sorted =
                      List<WeightEntity>.from(list)
                        ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
                  return Column(
                    children: <Widget>[
                      for (final WeightEntity w in sorted.take(10))
                        _HistoryRow(weight: w),
                    ],
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LatestValueHeader
// ============================================================================
class _LatestValueHeader extends StatelessWidget {
  const _LatestValueHeader({required this.history});

  final List<WeightEntity> history;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    if (history.isEmpty) {
      return Text(
        '—',
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontStyle: FontStyle.italic,
          fontSize: 48,
          color: colors.fgFaint,
        ),
      );
    }

    // 最新(measuredAt が最大のもの)
    final WeightEntity latest = history
        .reduce((a, b) => a.measuredAt > b.measuredAt ? a : b);
    final double kg = latest.weightG / 1000.0;
    final DateTime t =
        DateTime.fromMillisecondsSinceEpoch(latest.measuredAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 48,
              height: 1.0,
              color: colors.fg,
            ),
            children: <TextSpan>[
              TextSpan(text: kg.toStringAsFixed(2)),
              TextSpan(
                text: ' kg',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontStyle: FontStyle.normal,
                  fontSize: 18,
                  color: colors.fgMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatRelative(
            t,
            Localizations.localeOf(context).toLanguageTag(),
          ),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 9,
            letterSpacing: 9 * 0.2,
            color: colors.fgMuted,
          ),
        ),
      ],
    );
  }

  String _formatRelative(DateTime t, String localeTag) {
    final DateTime now = DateTime.now();
    final Duration diff = now.difference(t);
    if (diff.inDays == 0) return 'TODAY';
    if (diff.inDays == 1) return 'YESTERDAY';
    if (diff.inDays < 7) return '${diff.inDays} DAYS AGO';
    return formatFullDate(t, localeTag);
  }
}

// ============================================================================
// HistoryRow
// ============================================================================
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.weight});

  final WeightEntity weight;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final DateTime t =
        DateTime.fromMillisecondsSinceEpoch(weight.measuredAt);
    final String dateStr = formatFullDate(
      t,
      Localizations.localeOf(context).toLanguageTag(),
    );
    final String kg = (weight.weightG / 1000.0).toStringAsFixed(2);

    return InkWell(
      onTap: () =>
          WeightRecordScreen.push(context, editingWeightId: weight.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 100,
              child: Text(
                dateStr,
                style: typo.metaSmall.copyWith(
                  color: colors.fgMuted,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Text(
                '$kg kg',
                style: typo.bodyMedium.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Y軸ラベル用: 整数なら小数なし、それ以外は小数1桁、末尾0除去。
String _formatKg(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}
