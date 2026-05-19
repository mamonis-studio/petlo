// ============================================================================
// petlo - Create Group Screen
// ============================================================================
//
// 新規グループ作成画面。Pro 必須。
//
// レイアウト (エディトリアル風):
//   - eyebrow + ヒーロー
//   - 「グループ名」EditorialTextField
//   - "Create" ボタン
//   - Pro 必須注意書き
//
// rev5.3 F-24
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../../core/widgets/primary_button.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../paywall/paywall_screen.dart';
import 'create_group_controller.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  static Future<String?> push(BuildContext context) {
    // 戻り値: 作成された groupId (キャンセル時 null)
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const CreateGroupScreen(),
      ),
    );
  }

  @override
  ConsumerState<CreateGroupScreen> createState() =>
      _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  late final TextEditingController _nameC;
  late final TextEditingController _displayNameC;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController();
    // build 18: 表示名は controller.build() で UserPreferences から
    // プリフィル済み。TextEditingController にも転記する。
    _displayNameC = TextEditingController(
      text: ref.read(createGroupControllerProvider).displayName,
    );
  }

  @override
  void dispose() {
    _nameC.dispose();
    _displayNameC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final CreateGroupState s =
        ref.watch(createGroupControllerProvider);
    final CreateGroupController controller =
        ref.read(createGroupControllerProvider.notifier);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          AppLocalizations.of(context).appbar_new_group,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
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
              SectionLabel(
                l10n.create_group_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              ),
              Text(
                '家族や信頼できる友人と、\nうちの子の記録を共有できるグループ。\n5人まで参加可能、最大3グループ作れます。',
                style: typo.bodyMedium.copyWith(
                  color: colors.fgMuted,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              EditorialTextField(
                label: 'Group name',
                controller: _nameC,
                hint: '例: 山田家のうちの子たち',
                required: true,
                maxLength: 50,
                errorText: s.nameError,
                onChanged: controller.updateName,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // build 18: 表示名 (グループ内であなたを呼ぶ名前)
              EditorialTextField(
                label: 'Your display name',
                controller: _displayNameC,
                hint: '例: お父さん, ママ',
                required: true,
                maxLength: 20,
                textCapitalization: TextCapitalization.words,
                errorText: s.displayNameError,
                onChanged: controller.updateDisplayName,
              ),
              const SizedBox(height: 8),
              Text(
                'グループのメンバーに表示される名前です。\n後から設定で変更できます。',
                style: typo.bodySmall
                    .copyWith(color: colors.fgFaint, height: 1.5),
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              if (s.errorMessage != null) ...<Widget>[
                _ErrorBox(
                  message: s.errorMessage!,
                  colors: colors,
                ),
                const SizedBox(height: AppDimensions.paddingSection),
              ],

              PrimaryButton(
                label: s.isSubmitting ? 'Creating...' : 'Create',
                onPressed: s.isSubmitting ? null : () => _onSubmit(controller),
              ),
              const SizedBox(height: 16),

              // 注意書き
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.line, width: 1),
                ),
                child: Text(
                  'NOTE\nグループ作成には Pro プランが必要です。\n参加するだけなら無料で可能です。',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 10 * 0.1,
                    height: 1.6,
                    color: colors.fgMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSubmit(CreateGroupController controller) async {
    final result = await controller.submit();
    if (!mounted) return;
    switch (result.outcome) {
      case CreateGroupOutcome.success:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).groups_snackbar_create_success),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(result.createdGroupId);
      case CreateGroupOutcome.validationFailed:
        // フォーム側にエラー表示が出る
        break;
      case CreateGroupOutcome.proRequired:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('グループ作成は Pro プラン限定です'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'VIEW PLANS',
              onPressed: () => PaywallScreen.push(context),
            ),
          ),
        );
      case CreateGroupOutcome.limitReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).groups_snackbar_max_groups),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case CreateGroupOutcome.network:
      case CreateGroupOutcome.serverError:
      case CreateGroupOutcome.unknown:
        // s.errorMessage 経由で表示
        break;
    }
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.colors});

  final String message;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.accentDanger, width: 1.5),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 13,
          color: colors.accentDanger,
          height: 1.5,
        ),
      ),
    );
  }
}
