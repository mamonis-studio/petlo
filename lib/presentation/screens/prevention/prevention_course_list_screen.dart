// ============================================================================
// petlo - Prevention Course List Screen
// ============================================================================
//
// 予防コースの一覧 (build 72)。年でグルーピングして表示する。
//
// 無料プランでは:
//   - コースは created_at 昇順で先着 1 件のみ開放 (§7)
//   - 過去年の履歴はロック
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prevention/prevention_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/outlined_action_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/prevention_providers.dart';
import '../../providers/scope_providers.dart';
import '../paywall/paywall_screen.dart';
import 'prevention_course_detail_screen.dart';
import 'prevention_course_form_screen.dart';

class PreventionCourseListScreen extends ConsumerWidget {
  const PreventionCourseListScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PreventionCourseListScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool canEdit = ref.watch(canEditProvider);
    final AsyncValue<List<PreventionCourseEntity>> coursesAsync =
        ref.watch(currentGroupPreventionCoursesProvider);
    final Set<int> unlocked =
        ref.watch(unlockedPreventionCourseIdsProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          l10n.prevention_list_appbar.toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        iconTheme: IconThemeData(color: colors.fg),
      ),
      body: SafeArea(
        child: coursesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (Object e, StackTrace st) => const SizedBox.shrink(),
          data: (List<PreventionCourseEntity> courses) {
            if (courses.isEmpty) {
              return _Empty(canEdit: canEdit);
            }
            final Map<int, List<PreventionCourseEntity>> byYear =
                <int, List<PreventionCourseEntity>>{};
            for (final PreventionCourseEntity c in courses) {
              byYear.putIfAbsent(c.year, () => <PreventionCourseEntity>[])
                  .add(c);
            }
            final List<int> years = byYear.keys.toList()
              ..sort((int a, int b) => b.compareTo(a));

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.paddingPage,
                AppDimensions.paddingSection,
                AppDimensions.paddingPage,
                AppDimensions.paddingPage * 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (canEdit) ...<Widget>[
                    OutlinedActionButton(
                      label: l10n.prevention_list_empty_action,
                      onPressed: () => _onCreate(context, ref),
                    ),
                    const SizedBox(height: AppDimensions.paddingSection),
                  ],
                  for (final int year in years) ...<Widget>[
                    SectionLabel(
                      '$year',
                      padding: const EdgeInsets.only(
                          bottom: AppDimensions.gapMedium),
                    ),
                    for (final PreventionCourseEntity c in byYear[year]!)
                      _CourseRow(
                        course: c,
                        locked: !unlocked.contains(c.id) ||
                            !ref.watch(canViewPreventionYearProvider(year)),
                      ),
                    const SizedBox(height: AppDimensions.paddingSection),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _onCreate(BuildContext context, WidgetRef ref) async {
    if (!ref.read(canCreatePreventionCourseProvider)) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.prevention_paywall_courses),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l10n.chart_range_pro_only_action,
            onPressed: () => PaywallScreen.push(context),
          ),
        ),
      );
      return;
    }
    await PreventionCourseFormScreen.push(context);
  }
}

// ============================================================================
// _Empty
// ============================================================================
class _Empty extends ConsumerWidget {
  const _Empty({required this.canEdit});

  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppDimensions.paddingPage),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.prevention_list_empty,
            textAlign: TextAlign.center,
            style: typo.bodyMedium.copyWith(color: colors.fgMuted),
          ),
          const SizedBox(height: AppDimensions.paddingSection),
          if (canEdit)
            OutlinedActionButton(
              label: l10n.prevention_list_empty_action,
              onPressed: () => PreventionCourseFormScreen.push(context),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// _CourseRow
// ============================================================================
class _CourseRow extends ConsumerWidget {
  const _CourseRow({required this.course, required this.locked});

  final PreventionCourseEntity course;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String localeTag = Localizations.localeOf(context).toLanguageTag();

    return InkWell(
      onTap: () {
        if (locked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.prevention_paywall_history),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: l10n.chart_range_pro_only_action,
                onPressed: () => PaywallScreen.push(context),
              ),
            ),
          );
          return;
        }
        PreventionCourseDetailScreen.push(context, courseId: course.id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: AppDimensions.paddingCompact),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    PreventionLabels.kind(course.kind, l10n),
                    style: typo.bodyMedium.copyWith(
                      color: locked ? colors.fgFaint : colors.fg,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.gapTight),
                  Text(
                    PreventionLabels.period(
                      startMonth: course.startMonth,
                      endMonth: course.endMonth,
                      l10n: l10n,
                      localeTag: localeTag,
                    ),
                    style: typo.metaSmall.copyWith(color: colors.fgMuted),
                  ),
                ],
              ),
            ),
            Text(
              locked ? 'PRO' : '→',
              style: typo.metaSmall.copyWith(color: colors.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}
