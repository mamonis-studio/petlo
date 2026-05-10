// ============================================================================
// petlo - Medication Reminder Record Screen
// ============================================================================
//
// 投薬リマインダーの登録/編集画面。
//
// レイアウト:
//   - 薬名 (必須)
//   - 量 (任意)
//   - 時刻リスト (Add ボタン + chip リスト + ×で削除)
//   - 曜日 (毎日 / 月..日 7チップ)
//   - 開始日/終了日 (任意)
//   - メモ (任意)
//   - ON/OFF トグル (編集時のみ)
//
// rev3 F-13
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../providers/pro_status_provider.dart';
import '../../widgets/forms/date_field.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../paywall/paywall_screen.dart';
import 'medication_reminder_form_controller.dart';
import 'medication_reminder_form_state.dart';

class MedicationReminderRecordScreen extends ConsumerStatefulWidget {
  const MedicationReminderRecordScreen({this.editingReminderId, super.key});

  final int? editingReminderId;

  static Future<bool?> push(BuildContext context, {int? editingReminderId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => MedicationReminderRecordScreen(
          editingReminderId: editingReminderId,
        ),
      ),
    );
  }

  @override
  ConsumerState<MedicationReminderRecordScreen> createState() =>
      _MedicationReminderRecordScreenState();
}

class _MedicationReminderRecordScreenState
    extends ConsumerState<MedicationReminderRecordScreen> {
  late final TextEditingController _medicineNameC;
  late final TextEditingController _dosageC;
  late final TextEditingController _notesC;

  bool _initialSynced = false;
  bool _hasNotificationPermission = false;
  bool _checkedPermission = false;

  @override
  void initState() {
    super.initState();
    _medicineNameC = TextEditingController();
    _dosageC = TextEditingController();
    _notesC = TextEditingController();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final bool granted =
        await NotificationService.instance.hasPermissions();
    if (mounted) {
      setState(() {
        _hasNotificationPermission = granted;
        _checkedPermission = true;
      });
    }
  }

  @override
  void dispose() {
    _medicineNameC.dispose();
    _dosageC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  void _syncControllers(MedicationReminderFormState s) {
    if (_initialSynced) return;
    if (!s.isEditing) {
      _initialSynced = true;
      return;
    }
    if (s.medicineName.isEmpty && s.times.isEmpty) return;
    _medicineNameC.text = s.medicineName;
    _dosageC.text = s.dosage;
    _notesC.text = s.notes;
    _initialSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final MedicationReminderFormState s = ref.watch(
        medicationReminderFormControllerProvider(widget.editingReminderId));
    final MedicationReminderFormController controller = ref.read(
        medicationReminderFormControllerProvider(widget.editingReminderId)
            .notifier);

    _syncControllers(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          s.isEditing ? 'EDIT REMINDER' : 'NEW REMINDER',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'CANCEL',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9,
              letterSpacing: 9 * 0.15,
              color: colors.fgMuted,
            ),
          ),
        ),
        leadingWidth: 80,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.paddingPage,
            AppDimensions.paddingPage,
            AppDimensions.paddingPage,
            AppDimensions.paddingPage * 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              EyebrowText(AppLocalizations.of(context).medication_reminders_eyebrow),
              const SizedBox(height: 8),
              Text(
                s.isEditing ? 'Update' : 'Medication,\nscheduled.',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontStyle: FontStyle.italic,
                  fontSize: 40,
                  letterSpacing: -40 * 0.04,
                  height: 0.95,
                  color: colors.fg,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 通知パーミッション警告 =====
              if (_checkedPermission && !_hasNotificationPermission)
                _PermissionBanner(
                  onRequest: () async {
                    final granted = await NotificationService.instance
                        .requestPermissions();
                    if (mounted) {
                      setState(() => _hasNotificationPermission = granted);
                    }
                  },
                ),
              if (_checkedPermission && !_hasNotificationPermission)
                const SizedBox(height: AppDimensions.paddingSection),

              // ===== 薬名 =====
              EditorialTextField(
                label: 'Medicine name',
                controller: _medicineNameC,
                hint: '例: フィラリア錠 / インスリン',
                required: true,
                maxLength: 50,
                errorText: s.errors.medicineName,
                onChanged: controller.updateMedicineName,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 量 =====
              EditorialTextField(
                label: 'Dosage (optional)',
                controller: _dosageC,
                hint: '例: 1錠 / 0.5ml / 半錠',
                maxLength: 30,
                onChanged: controller.updateDosage,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 時刻リスト =====
              SectionLabel(AppLocalizations.of(context).medication_reminder_form_time_label),
              const SizedBox(height: 8),
              _TimesEditor(
                times: s.times,
                onAdd: controller.addTime,
                onRemove: controller.removeTime,
                errorText: s.errors.times,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 曜日 =====
              SectionLabel(AppLocalizations.of(context).medication_reminder_form_weekdays_label),
              const SizedBox(height: 8),
              _WeekdayChips(
                weekdays: s.weekdays,
                isEveryday: s.isEveryday,
                onToggle: controller.toggleWeekday,
                onSetEveryday: controller.setEveryday,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 期間(任意)=====
              SectionLabel(AppLocalizations.of(context).medication_reminder_form_period_label),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: DateField(
                      label: 'Start',
                      value: s.startDate,
                      onChanged: controller.updateStartDate,
                      firstDate: DateTime(DateTime.now().year - 1),
                      lastDate: DateTime(DateTime.now().year + 5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DateField(
                      label: 'End',
                      value: s.endDate,
                      onChanged: controller.updateEndDate,
                      errorText: s.errors.dateRange,
                      firstDate: DateTime(DateTime.now().year - 1),
                      lastDate: DateTime(DateTime.now().year + 5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== メモ =====
              EditorialTextField(
                label: 'Notes (optional)',
                controller: _notesC,
                hint: '空腹時に / 食後 など',
                maxLength: 200,
                maxLines: 3,
                minLines: 1,
                onChanged: controller.updateNotes,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== ON/OFF (編集時のみ) =====
              if (s.isEditing) ...<Widget>[
                _EnabledToggle(
                  enabled: s.enabled,
                  onChanged: controller.updateEnabled,
                ),
                const SizedBox(height: AppDimensions.paddingSection),
              ],

              // ===== Save =====
              PrimaryButton(
                label: s.isSubmitting
                    ? 'Saving...'
                    : (s.isEditing ? 'Update' : 'Save'),
                onPressed: s.isSubmitting ? null : () => _onSave(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSave(MedicationReminderFormController controller) async {
    final bool isPro = ref.read(isProProvider);
    final r = await controller.save(isProUser: isPro);
    if (!mounted) return;
    switch (r) {
      case MedicationReminderSaveOutcome.success:
        Navigator.of(context).pop(true);
      case MedicationReminderSaveOutcome.validationFailed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).common_input_invalid),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case MedicationReminderSaveOutcome.freeLimitReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('無料プランは1件までです'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'VIEW PLANS',
              onPressed: () => PaywallScreen.push(context),
            ),
          ),
        );
      case MedicationReminderSaveOutcome.dbError:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).common_save_failed),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }
}

// ============================================================================
// PermissionBanner — 通知未許可警告
// ============================================================================
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: colors.accentWarn, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'NOTIFICATIONS DISABLED',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9,
              letterSpacing: 9 * 0.2,
              color: colors.accentWarn,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'リマインダーは作成できますが、\n通知が届きません。許可しますか?',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              height: 1.5,
              color: colors.fg,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: onRequest,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.fg,
                border: Border.all(color: colors.fg),
              ),
              child: Text(
                'ALLOW NOTIFICATIONS',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 9,
                  letterSpacing: 9 * 0.18,
                  color: colors.bg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TimesEditor - 時刻リスト + Add ボタン
// ============================================================================
class _TimesEditor extends StatelessWidget {
  const _TimesEditor({
    required this.times,
    required this.onAdd,
    required this.onRemove,
    this.errorText,
  });

  final List<String> times;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final String? errorText;

  Future<void> _pickTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      builder: (BuildContext c, Widget? child) {
        // 24h 表示固定
        return MediaQuery(
          data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return;
    final String hhmm =
        '${picked.hour.toString().padLeft(2, "0")}:${picked.minute.toString().padLeft(2, "0")}';
    onAdd(hhmm);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String t in times)
              Container(
                padding:
                    const EdgeInsets.fromLTRB(12, 7, 6, 7),
                decoration: BoxDecoration(
                  color: colors.fg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      t,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 13,
                        letterSpacing: 13 * 0.05,
                        color: colors.bg,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => onRemove(t),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6, right: 4),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: colors.bg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Add ボタン
            InkWell(
              onTap: () => _pickTime(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.fg, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.add, size: 14, color: colors.fg),
                    const SizedBox(width: 4),
                    Text(
                      'ADD',
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 10,
                        letterSpacing: 10 * 0.18,
                        color: colors.fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            errorText!,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              color: colors.accentDanger,
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// WeekdayChips - 毎日 + 月..日 7チップ
// ============================================================================
class _WeekdayChips extends StatelessWidget {
  const _WeekdayChips({
    required this.weekdays,
    required this.isEveryday,
    required this.onToggle,
    required this.onSetEveryday,
  });

  /// 0=日, 1=月, 2=火, 3=水, 4=木, 5=金, 6=土
  final Set<int> weekdays;
  final bool isEveryday;
  final ValueChanged<int> onToggle;
  final VoidCallback onSetEveryday;

  static const List<String> _labels = <String>[
    'SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        // Every day
        InkWell(
          onTap: onSetEveryday,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isEveryday ? colors.fg : colors.bg,
              border: Border.all(color: colors.fg, width: 1),
            ),
            child: Text(
              'EVERY DAY',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 10 * 0.18,
                color: isEveryday ? colors.bg : colors.fg,
                fontWeight: isEveryday ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),

        // 7曜日チップ
        for (int wd = 0; wd < 7; wd++)
          InkWell(
            onTap: () => onToggle(wd),
            child: Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: weekdays.contains(wd) && !isEveryday
                    ? colors.fg
                    : colors.bg,
                border: Border.all(color: colors.fg, width: 1),
              ),
              child: Text(
                _labels[wd],
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 9,
                  letterSpacing: 9 * 0.15,
                  color: weekdays.contains(wd) && !isEveryday
                      ? colors.bg
                      : colors.fg,
                  fontWeight: weekdays.contains(wd) && !isEveryday
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// EnabledToggle - ON/OFF
// ============================================================================
class _EnabledToggle extends StatelessWidget {
  const _EnabledToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: () => onChanged(!enabled),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: colors.line, width: 1),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    enabled ? 'Active' : 'Paused',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 18,
                      color: colors.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'Notifications will fire at scheduled times.'
                        : 'No notifications will be sent.',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: colors.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: enabled,
              onChanged: onChanged,
              activeColor: colors.fg,
            ),
          ],
        ),
      ),
    );
  }
}
