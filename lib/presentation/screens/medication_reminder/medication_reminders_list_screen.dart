// ============================================================================
// petlo - Medication Reminders List Screen
// ============================================================================
//
// 現在ペットの全リマインダー一覧。
// More タブの "Medications" 行や、Plansタブから push される。
//
// rev3 F-13
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/outlined_action_button.dart';
import '../../../data/local/app_database.dart';
import '../../providers/medication_reminders_providers.dart';
import '../../providers/notification_scheduler_provider.dart';
import '../../providers/scope_providers.dart';
import 'medication_reminder_form_controller.dart';
import 'medication_reminder_record_screen.dart';

class MedicationRemindersListScreen extends ConsumerWidget {
  const MedicationRemindersListScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MedicationRemindersListScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final bool canEdit = ref.watch(canEditProvider);
    final AsyncValue<List<MedicationReminderEntity>> remindersAsync =
        ref.watch(currentPetRemindersProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          AppLocalizations.of(context).medication_reminders_app_bar,
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
                AppLocalizations.of(context).health_record_medication,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              ),

              // Add ボタン
              if (canEdit) ...<Widget>[
                OutlinedActionButton(
                  label: AppLocalizations.of(context).medication_reminders_add,
                  onPressed: () =>
                      MedicationReminderRecordScreen.push(context),
                ),
                const SizedBox(height: 24),
              ],

              // 一覧
              remindersAsync.when(
                data: (List<MedicationReminderEntity> list) {
                  if (list.isEmpty) {
                    return _EmptyState(colors: colors, typo: typo);
                  }
                  // 有効と無効でセクション分け
                  final List<MedicationReminderEntity> active =
                      list.where((r) => r.enabled).toList();
                  final List<MedicationReminderEntity> paused =
                      list.where((r) => !r.enabled).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (active.isNotEmpty) ...<Widget>[
                        _SectionHeader(
                            label:
                                '${AppLocalizations.of(context).medication_reminders_section_active} · ${active.length}',
                            color: colors.fgMuted),
                        const SizedBox(height: 8),
                        for (final MedicationReminderEntity r in active)
                          _ReminderRow(reminder: r),
                      ],
                      if (paused.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 24),
                        _SectionHeader(
                            label:
                                '${AppLocalizations.of(context).medication_reminders_section_paused} · ${paused.length}',
                            color: colors.fgFaint),
                        const SizedBox(height: 8),
                        for (final MedicationReminderEntity r in paused)
                          _ReminderRow(reminder: r),
                      ],
                      // 無料制限の注意書き(将来 Pro判定で出し分け)
                      const SizedBox(height: 32),
                      Text(
                        AppLocalizations.of(context).medication_reminder_free_limit,
                        style: typo.bodySmall.copyWith(
                          color: colors.fgFaint,
                          height: 1.5,
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                ),
                error: (Object e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    AppLocalizations.of(context).common_load_failed,
                    style: typo.bodySmall.copyWith(color: colors.fgMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            AppLocalizations.of(context).medication_reminders_empty,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 28,
              color: colors.fgMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).medication_reminders_description,
            style:
                typo.bodyMedium.copyWith(color: colors.fgMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 9,
        letterSpacing: 9 * 0.2,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ============================================================================
// ReminderRow
// ============================================================================
class _ReminderRow extends ConsumerWidget {
  const _ReminderRow({required this.reminder});

  final MedicationReminderEntity reminder;

  String _formatTimes() {
    if (reminder.times.length <= 4) {
      return reminder.times.join(' · ');
    }
    return '${reminder.times.take(3).join(' · ')} +${reminder.times.length - 3}';
  }

  String _formatWeekdays(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (reminder.weekdaysBits.isEmpty) {
      return l10n.medication_reminder_form_every_day;
    }
    final List<String> labels = <String>[
      l10n.medication_reminder_weekday_sun,
      l10n.medication_reminder_weekday_mon,
      l10n.medication_reminder_weekday_tue,
      l10n.medication_reminder_weekday_wed,
      l10n.medication_reminder_weekday_thu,
      l10n.medication_reminder_weekday_fri,
      l10n.medication_reminder_weekday_sat,
    ];
    final List<int> sorted = reminder.weekdaysBits.toList()..sort();
    return sorted.map((int wd) => labels[wd]).join(' ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool isPaused = !reminder.enabled;

    return InkWell(
      onTap: () => MedicationReminderRecordScreen.push(
        context,
        editingReminderId: reminder.id,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    reminder.medicineName,
                    style: typo.bodyLarge.copyWith(
                      color: isPaused ? colors.fgMuted : colors.fg,
                      decoration:
                          isPaused ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (reminder.dosage != null &&
                      reminder.dosage!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      reminder.dosage!,
                      style: typo.bodySmall.copyWith(color: colors.fgMuted),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '${_formatTimes()} · ${_formatWeekdays(context)}',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 10 * 0.15,
                      color: colors.fgMuted,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ON/OFFトグル
            Switch.adaptive(
              value: reminder.enabled,
              onChanged: (bool v) async {
                final repo =
                    ref.read(medicationRemindersRepositoryProvider);
                final scheduler =
                    ref.read(notificationSchedulerProvider);
                await repo.setEnabled(reminder.id, v);
                // 通知の再構築 / キャンセル
                await scheduler.syncReminder(reminder.id);
              },
              activeColor: colors.fg,
            ),
          ],
        ),
      ),
    );
  }
}
