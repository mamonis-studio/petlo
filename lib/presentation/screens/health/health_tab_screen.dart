// ============================================================================
// petlo - Health Tab Screen
// ============================================================================
//
// 健康記録のダッシュボード。
//
// 構成:
//   - ヒーロー (Health タイトル)
//   - 期限切れワクチン警告 (該当があれば最上部に強調表示)
//   - 体重・体温の最新値カード(タップで記録画面)
//   - 通院・ワクチンの履歴セクション
//
// rev3 F-06/F-07/F-08
// rev5 リマインダー基盤接続(overdueVaccinationsProvider 使用)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/unit_converters.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/outlined_action_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/pets_providers.dart';
import '../../providers/scope_providers.dart';
import '../../providers/temperatures_providers.dart';
import '../../providers/vaccinations_providers.dart';
import '../../providers/visits_providers.dart';
import '../../providers/weights_providers.dart';
import '../../providers/tab_provider.dart';
import '../../widgets/pet_selector/auto_select_first_pet.dart';
import '../../widgets/petlo_scaffold.dart';
import '../temperature/temperature_chart_screen.dart';
import '../temperature/temperature_record_screen.dart';
import '../vaccination/vaccination_record_screen.dart';
import '../visit/visit_record_screen.dart';
import '../weight/weight_chart_screen.dart';
import '../weight/weight_record_screen.dart';

class HealthTabScreen extends ConsumerWidget {
  const HealthTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTypography typo = AppTypography.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? currentPetId = ref.watch(currentPetIdProvider);
    final bool canEdit = ref.watch(canEditProvider);
    final bool hasPet = currentPetId != null && currentPetId != kAllPetsId;

    autoSelectFirstPetIfAllSelected(ref, forTab: AppTab.health);

    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return PetloScaffold(
      showTabBar: false,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          28,
          16,
          28,
          28 + bottomInset + kBottomNavigationBarHeight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionLabel(
              l10n.tab_eyebrow_health,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
            ),
            if (!hasPet)
              _SelectPetEmpty(colors: colors, typo: typo)
            else ...<Widget>[
              const _OverdueVaccinationsBanner(),
              const _LatestVitalCards(),
              const SizedBox(height: 12),
              _TrendLinks(colors: colors),
              const SizedBox(height: 32),

              if (canEdit) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedActionButton(
                        label: l10n.health_record_visit,
                        onPressed: () => VisitRecordScreen.push(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedActionButton(
                        label: l10n.health_record_vaccination,
                        onPressed: () =>
                            VaccinationRecordScreen.push(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],

              const _VisitsList(),
              const SizedBox(height: 32),

              const _VaccinationsList(),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectPetEmpty extends StatelessWidget {
  const _SelectPetEmpty({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(
        AppLocalizations.of(context).tab_select_pet_health,
        style: typo.bodyMedium.copyWith(color: colors.fgMuted, height: 1.6),
      ),
    );
  }
}

// ============================================================================
// OverdueVaccinationsBanner
// ============================================================================
class _OverdueVaccinationsBanner extends ConsumerWidget {
  const _OverdueVaccinationsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<VaccinationEntity>> overdueAsync =
        ref.watch(overdueVaccinationsProvider);
    final AppColors colors = AppColors.of(context);

    return overdueAsync.maybeWhen(
      data: (List<VaccinationEntity> list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: colors.accentDanger, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'OVERDUE',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 9,
                    letterSpacing: 9 * 0.2,
                    color: colors.accentDanger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${list.length} vaccination${list.length > 1 ? "s" : ""} past due',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontStyle: FontStyle.italic,
                    fontSize: 22,
                    color: colors.fg,
                  ),
                ),
                const SizedBox(height: 8),
                for (final VaccinationEntity v in list.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '· ${v.kind}',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        color: colors.fg,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ============================================================================
// LatestVitalCards - 体重・体温の最新値
// ============================================================================
class _LatestVitalCards extends ConsumerWidget {
  const _LatestVitalCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        Expanded(child: _WeightCard()),
        SizedBox(width: 8),
        Expanded(child: _TemperatureCard()),
      ],
    );
  }
}

// ============================================================================
// _TrendLinks - 体重/体温グラフ画面への導線
// ============================================================================
class _TrendLinks extends StatelessWidget {
  const _TrendLinks({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _TrendLinkButton(
            label: l10n.health_weight_trend,
            onTap: () => WeightChartScreen.push(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TrendLinkButton(
            label: l10n.health_temp_trend,
            onTap: () => TemperatureChartScreen.push(context),
          ),
        ),
      ],
    );
  }
}

class _TrendLinkButton extends StatelessWidget {
  const _TrendLinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: colors.line, width: 1),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 10 * 0.18,
                  color: colors.fg,
                ),
              ),
            ),
            Text(
              '→',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 12,
                color: colors.fgMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightCard extends ConsumerWidget {
  const _WeightCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AsyncValue<WeightEntity?> latestAsync =
        ref.watch(currentPetLatestWeightProvider);

    return InkWell(
      onTap: () => WeightRecordScreen.push(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: colors.fg, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'WEIGHT',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 9,
                letterSpacing: 9 * 0.2,
                color: colors.fgMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            latestAsync.maybeWhen(
              data: (WeightEntity? w) {
                if (w == null) {
                  return Text(
                    '—',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 32,
                      color: colors.fgFaint,
                    ),
                  );
                }
                return RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 32,
                      height: 1.0,
                      color: colors.fg,
                    ),
                    children: <TextSpan>[
                      TextSpan(
                        text: WeightConverter.formatG(
                            weightG: w.weightG, unit: WeightUnit.kg),
                      ),
                      TextSpan(
                        text: ' kg',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontStyle: FontStyle.normal,
                          fontSize: 14,
                          color: colors.fgMuted,
                        ),
                      ),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox(height: 32),
            ),
            const SizedBox(height: 6),
            latestAsync.maybeWhen(
              data: (WeightEntity? w) {
                if (w == null) return const SizedBox.shrink();
                final DateTime t =
                    DateTime.fromMillisecondsSinceEpoch(w.measuredAt);
                return Text(
                  _formatRelativeDate(context, t),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: colors.fgMuted,
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemperatureCard extends ConsumerWidget {
  const _TemperatureCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AsyncValue<TemperatureEntity?> latestAsync =
        ref.watch(currentPetLatestTemperatureProvider);
    final AsyncValue<PetEntity?> petAsync =
        ref.watch(currentPetProvider);

    return InkWell(
      onTap: () => TemperatureRecordScreen.push(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: colors.fg, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'TEMPERATURE',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 9,
                letterSpacing: 9 * 0.2,
                color: colors.fgMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            latestAsync.maybeWhen(
              data: (TemperatureEntity? t) {
                if (t == null) {
                  return Text(
                    '—',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 32,
                      color: colors.fgFaint,
                    ),
                  );
                }
                final petType = petAsync.maybeWhen(
                  data: (PetEntity? p) => p?.type,
                  orElse: () => null,
                );
                final Color tempColor = petType == null
                    ? colors.fg
                    : _statusToColor(
                        TemperatureConverter.statusFor(
                          tempCelsiusX10: t.tempCelsiusX10,
                          petType: petType,
                        ),
                        colors,
                      );
                return RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 32,
                      height: 1.0,
                      color: tempColor,
                    ),
                    children: <TextSpan>[
                      TextSpan(
                        text: TemperatureConverter.formatX10(
                          tempCelsiusX10: t.tempCelsiusX10,
                          unit: TemperatureUnit.celsius,
                        ),
                      ),
                      TextSpan(
                        text: ' °C',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontStyle: FontStyle.normal,
                          fontSize: 14,
                          color: colors.fgMuted,
                        ),
                      ),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox(height: 32),
            ),
            const SizedBox(height: 6),
            latestAsync.maybeWhen(
              data: (TemperatureEntity? t) {
                if (t == null) return const SizedBox.shrink();
                final DateTime d =
                    DateTime.fromMillisecondsSinceEpoch(t.measuredAt);
                return Text(
                  _formatRelativeDate(context, d),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: colors.fgMuted,
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

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

String _formatRelativeDate(BuildContext context, DateTime t) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final DateTime now = DateTime.now();
  final Duration diff = now.difference(t);
  if (diff.inDays == 0) return l10n.record_today_label;
  if (diff.inDays == 1) return l10n.record_yesterday_label;
  if (diff.inDays < 7) return l10n.health_days_ago(diff.inDays);
  if (diff.inDays < 30) return l10n.health_weeks_ago((diff.inDays / 7).floor());
  return l10n.health_months_ago((diff.inDays / 30).floor());
}

// ============================================================================
// VisitsList
// ============================================================================
class _VisitsList extends ConsumerWidget {
  const _VisitsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AsyncValue<List<VisitEntity>> visitsAsync =
        ref.watch(currentPetVisitsProvider);

    return visitsAsync.maybeWhen(
      data: (List<VisitEntity> list) {
        if (list.isEmpty) {
          return Text(
            AppLocalizations.of(context).health_no_visits,
            style: typo.bodySmall.copyWith(color: colors.fgMuted),
          );
        }
        return Column(
          children: <Widget>[
            for (final VisitEntity v in list.take(5))
              InkWell(
                onTap: () =>
                    VisitRecordScreen.push(context, editingVisitId: v.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.line)),
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 80,
                        child: Text(
                          _formatDate(DateTime.fromMillisecondsSinceEpoch(
                              v.visitedAt)),
                          style: typo.metaSmall
                              .copyWith(color: colors.fgMuted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          v.reason,
                          style: typo.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ============================================================================
// VaccinationsList
// ============================================================================
class _VaccinationsList extends ConsumerWidget {
  const _VaccinationsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AsyncValue<List<VaccinationEntity>> vaxAsync =
        ref.watch(currentPetVaccinationsProvider);

    return vaxAsync.maybeWhen(
      data: (List<VaccinationEntity> list) {
        if (list.isEmpty) {
          return Text(
            AppLocalizations.of(context).health_no_vaccinations,
            style: typo.bodySmall.copyWith(color: colors.fgMuted),
          );
        }
        return Column(
          children: <Widget>[
            for (final VaccinationEntity vax in list.take(5))
              InkWell(
                onTap: () => VaccinationRecordScreen.push(
                  context,
                  editingVaccinationId: vax.id,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.line)),
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 80,
                        child: Text(
                          _formatDate(DateTime.fromMillisecondsSinceEpoch(
                              vax.administeredAt)),
                          style: typo.metaSmall
                              .copyWith(color: colors.fgMuted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          vax.kind,
                          style: typo.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (vax.nextDueAt != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            'NEXT ${_formatDateShort(DateTime.fromMillisecondsSinceEpoch(vax.nextDueAt!))}',
                            style: typo.metaSmall.copyWith(
                              color: _isPast(DateTime.fromMillisecondsSinceEpoch(
                                      vax.nextDueAt!))
                                  ? colors.accentDanger
                                  : colors.fgMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

bool _isPast(DateTime d) => d.isBefore(DateTime.now());

String _formatDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, "0")}.${d.day.toString().padLeft(2, "0")}';

String _formatDateShort(DateTime d) =>
    '${d.month.toString().padLeft(2, "0")}/${d.day.toString().padLeft(2, "0")}';
