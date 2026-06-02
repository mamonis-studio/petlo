// ============================================================================
// petlo - Temperature Chart Screen
// ============================================================================
//
// 体温推移グラフの専用画面。Health タブから push される。
//
// 構成:
//   - AppBar: TEMPERATURE TREND
//   - エディトリアル ヒーロー: "Temperature, over time."
//   - 最新値表示 (PetType連動の正常範囲外なら警告色)
//   - ChartRangeSelector
//   - PetloLineChart with normalRangeMin/Max (犬: 37.5-39.0、猫: 38.0-39.5)
//   - 履歴リスト
//
// rev3 F-07: 体温 + 推移グラフ
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/unit_converters.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../data/models/chart_range.dart';
import '../../providers/chart_provider.dart';
import '../../providers/pets_providers.dart';
import '../../providers/pro_status_provider.dart';
import '../../widgets/charts/chart_range_selector.dart';
import '../../widgets/charts/petlo_line_chart.dart';
import 'temperature_record_screen.dart';

class TemperatureChartScreen extends ConsumerStatefulWidget {
  const TemperatureChartScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const TemperatureChartScreen(),
      ),
    );
  }

  @override
  ConsumerState<TemperatureChartScreen> createState() =>
      _TemperatureChartScreenState();
}

class _TemperatureChartScreenState
    extends ConsumerState<TemperatureChartScreen> {
  ChartRange _range = ChartRange.month3;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final AsyncValue<List<TemperatureEntity>> dataAsync =
        ref.watch(temperatureChartProvider(_range));
    final AsyncValue<PetEntity?> petAsync = ref.watch(currentPetProvider);

    final PetType? petType =
        petAsync.maybeWhen(data: (PetEntity? p) => p?.type, orElse: () => null);

    // 正常範囲(PetType依存)
    final (double? minNormal, double? maxNormal) = switch (petType) {
      PetType.dog => (37.5, 39.0),
      PetType.cat => (38.0, 39.5),
      _ => (null, null),
    };

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'TEMPERATURE TREND',
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
                data: (List<TemperatureEntity> list) =>
                    _LatestValueHeader(history: list, petType: petType),
                orElse: () => const SizedBox(height: 56),
              ),
              const SizedBox(height: 24),

              // ===== Range selector =====
              ChartRangeSelector(
                current: _range,
                onChanged: (ChartRange r) => setState(() => _range = r),
                // build 71: Pro なら全期間、Free は 3M まで。
                isProUser: ref.watch(isProProvider),
              ),
              const SizedBox(height: 16),

              // ===== Normal range hint =====
              if (minNormal != null && maxNormal != null) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'NORMAL · ${minNormal.toStringAsFixed(1)} – ${maxNormal.toStringAsFixed(1)} °C',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 9,
                      letterSpacing: 9 * 0.2,
                      color: colors.fgMuted,
                    ),
                  ),
                ),
              ],

              // ===== Chart =====
              dataAsync.when(
                data: (List<TemperatureEntity> list) {
                  final List<ChartPoint> points =
                      list.map((TemperatureEntity t) {
                    return ChartPoint(
                      timestamp: t.measuredAt,
                      value: t.tempCelsiusX10 / 10.0,
                    );
                  }).toList();

                  return PetloLineChart(
                    points: points,
                    range: _range,
                    unitLabel: ' °C',
                    normalRangeMin: minNormal,
                    normalRangeMax: maxNormal,
                    yAxisFormatter: (double v) => v.toStringAsFixed(1),
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
                data: (List<TemperatureEntity> list) {
                  if (list.isEmpty) {
                    return Text(
                      'No records in this range.',
                      style: typo.bodySmall.copyWith(color: colors.fgMuted),
                    );
                  }
                  final List<TemperatureEntity> sorted =
                      List<TemperatureEntity>.from(list)
                        ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
                  return Column(
                    children: <Widget>[
                      for (final TemperatureEntity t in sorted.take(10))
                        _HistoryRow(temperature: t, petType: petType),
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
// LatestValueHeader (PetType連動で警告色)
// ============================================================================
class _LatestValueHeader extends StatelessWidget {
  const _LatestValueHeader({required this.history, required this.petType});

  final List<TemperatureEntity> history;
  final PetType? petType;

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

    final TemperatureEntity latest = history
        .reduce((a, b) => a.measuredAt > b.measuredAt ? a : b);
    final double celsius = latest.tempCelsiusX10 / 10.0;
    final DateTime t =
        DateTime.fromMillisecondsSinceEpoch(latest.measuredAt);

    final Color valueColor = petType == null
        ? colors.fg
        : _statusToColor(
            TemperatureConverter.statusFor(
              tempCelsiusX10: latest.tempCelsiusX10,
              petType: petType!,
            ),
            colors,
          );

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
              color: valueColor,
            ),
            children: <TextSpan>[
              TextSpan(text: celsius.toStringAsFixed(1)),
              TextSpan(
                text: ' °C',
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
// HistoryRow (PetType連動で正常/異常マーク)
// ============================================================================
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.temperature, required this.petType});

  final TemperatureEntity temperature;
  final PetType? petType;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final DateTime t =
        DateTime.fromMillisecondsSinceEpoch(temperature.measuredAt);
    final String dateStr = formatFullDate(
      t,
      Localizations.localeOf(context).toLanguageTag(),
    );
    final String celsius =
        (temperature.tempCelsiusX10 / 10.0).toStringAsFixed(1);

    final TemperatureStatus? status = petType == null
        ? null
        : TemperatureConverter.statusFor(
            tempCelsiusX10: temperature.tempCelsiusX10,
            petType: petType!,
          );
    final Color valueColor =
        status == null ? colors.fg : _statusToColor(status, colors);

    return InkWell(
      onTap: () => TemperatureRecordScreen.push(
        context,
        editingTempId: temperature.id,
      ),
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
                '$celsius °C',
                style: typo.bodyMedium.copyWith(
                  color: valueColor,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            if (status != null && status != TemperatureStatus.normal)
              Text(
                _statusLabel(status),
                style: typo.metaSmall.copyWith(color: valueColor),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(TemperatureStatus s) {
    switch (s) {
      case TemperatureStatus.normal:
        return '';
      case TemperatureStatus.cautionLow:
        return 'LOW';
      case TemperatureStatus.cautionHigh:
        return 'HIGH';
      case TemperatureStatus.urgentLow:
        return 'URGENT LOW';
      case TemperatureStatus.urgentHigh:
        return 'URGENT HIGH';
    }
  }
}

// ============================================================================
// Helpers
// ============================================================================
Color _statusToColor(TemperatureStatus s, AppColors c) {
  return switch (s) {
    TemperatureStatus.normal => c.fg,
    TemperatureStatus.cautionLow ||
    TemperatureStatus.cautionHigh =>
      c.accentWarn,
    TemperatureStatus.urgentLow ||
    TemperatureStatus.urgentHigh =>
      c.accentDanger,
  };
}
