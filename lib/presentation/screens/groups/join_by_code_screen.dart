// ============================================================================
// petlo - Join By Code Screen
// ============================================================================
//
// 6桁招待コードでグループに参加する画面。
//
// レイアウト:
//   - eyebrow + ヒーロー
//   - 6桁コード入力 (大型 monospace)
//   - 表示名入力
//   - "Join group" ボタン
//   - 注意書き
//
// 成功時:
//   - F-31 同名ペット警告: ローカルにペットがある場合、注意ダイアログ
//   - グループ詳細画面に遷移
//
// rev5.3 F-26 / F-31
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
import 'group_detail_screen.dart';
import 'join_by_code_controller.dart';

class JoinByCodeScreen extends ConsumerStatefulWidget {
  const JoinByCodeScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const JoinByCodeScreen(),
      ),
    );
  }

  @override
  ConsumerState<JoinByCodeScreen> createState() =>
      _JoinByCodeScreenState();
}

class _JoinByCodeScreenState extends ConsumerState<JoinByCodeScreen> {
  late final TextEditingController _codeC;
  late final TextEditingController _nameC;

  @override
  void initState() {
    super.initState();
    _codeC = TextEditingController();
    // build 18: 表示名は controller.build() でプリフィル済み、
    // TextEditingController にも転記する。
    _nameC = TextEditingController(
      text: ref.read(joinByCodeControllerProvider).displayName,
    );
  }

  @override
  void dispose() {
    _codeC.dispose();
    _nameC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final JoinByCodeState s =
        ref.watch(joinByCodeControllerProvider);
    final JoinByCodeController controller =
        ref.read(joinByCodeControllerProvider.notifier);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          AppLocalizations.of(context).appbar_join_group,
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
                l10n.join_by_code_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              ),
              Text(
                'グループのオーナーから受け取った\n6桁の招待コードを入力してください。',
                style: typo.bodyMedium
                    .copyWith(color: colors.fgMuted, height: 1.7),
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 6桁コード入力 =====
              EditorialTextField(
                label: 'Invite code',
                controller: _codeC,
                hint: '000000',
                required: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                errorText: s.codeError,
                onChanged: controller.updateCode,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 表示名 =====
              EditorialTextField(
                label: 'Your display name',
                controller: _nameC,
                hint: '例: お父さん, ママ',
                required: true,
                maxLength: 20,
                textCapitalization: TextCapitalization.words,
                errorText: s.nameError,
                onChanged: controller.updateDisplayName,
              ),
              const SizedBox(height: 8),
              Text(
                'グループのメンバーに表示される名前です。',
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
                label: s.isSubmitting ? 'Joining...' : 'Join group',
                onPressed: !s.canSubmit
                    ? null
                    : () => _onJoin(controller),
              ),
              const SizedBox(height: 16),

              // 注意書き
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.line, width: 1),
                ),
                child: Text(
                  'NOTE\n参加は無料です。\nコードの有効期限は発行から72時間です。',
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

  Future<void> _onJoin(JoinByCodeController controller) async {
    // キーボードを閉じる
    FocusScope.of(context).unfocus();

    final r = await controller.submit();
    if (!mounted) return;
    switch (r.outcome) {
      case JoinByCodeOutcome.success:
        await _handleSuccess(controller, r.result!);
      case JoinByCodeOutcome.validationFailed:
        // フォーム側にエラー
        break;
      case JoinByCodeOutcome.invalid:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).groups_snackbar_invite_invalid),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case JoinByCodeOutcome.alreadyUsed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).groups_snackbar_invite_used),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case JoinByCodeOutcome.full:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).groups_snackbar_group_full),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case JoinByCodeOutcome.alreadyMember:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).groups_snackbar_already_member),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case JoinByCodeOutcome.limitReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).groups_snackbar_max_3_groups),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case JoinByCodeOutcome.network:
      case JoinByCodeOutcome.serverError:
      case JoinByCodeOutcome.unknown:
        // s.errorMessage 経由で表示
        break;
    }
  }

  /// 成功時の処理: 同名ペット警告 → グループ詳細画面へ
  Future<void> _handleSuccess(
    JoinByCodeController controller,
    JoinResult result,
  ) async {
    // F-31: ローカルにペットがあれば注意喚起
    final List<String> localNames =
        await controller.findLocalPetNames();

    if (!mounted) return;

    if (localNames.isNotEmpty) {
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (_) => _DuplicatePetWarningDialog(
          groupName: result.groupName,
          localPetNames: localNames,
        ),
      );
      if (proceed != true) {
        // ユーザーが「あとで対応」を選んだ場合も画面遷移はする
        // (グループ自体は参加済みなので)
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).groups_snackbar_joined(result.groupName)),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // 現在の画面を閉じてからグループ詳細を push
    Navigator.of(context).pop();
    await GroupDetailScreen.push(
      context,
      groupRemoteId: result.groupRemoteId,
    );
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

// ============================================================================
// _DuplicatePetWarningDialog - F-31 同名ペット警告
// ============================================================================
class _DuplicatePetWarningDialog extends StatelessWidget {
  const _DuplicatePetWarningDialog({
    required this.groupName,
    required this.localPetNames,
  });

  final String groupName;
  final List<String> localPetNames;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return AlertDialog(
      backgroundColor: colors.bg,
      title: Text(
        '同じ名前のペットに注意',
        style: typo.bodyLarge.copyWith(color: colors.fg),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'あなたは現在、以下のペットを記録しています:',
            style: typo.bodySmall.copyWith(color: colors.fgMuted),
          ),
          const SizedBox(height: 8),
          ...localPetNames.map(
            (n) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '· $n',
                style: typo.bodyMedium.copyWith(color: colors.fg),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '"$groupName" に同じ名前のペットがいる場合、\n別のペットとして同期されます。\n同じ子の場合は、両方の記録が分かれてしまうので\nグループ参加後にペット情報を確認してください。',
            style:
                typo.bodySmall.copyWith(color: colors.fgMuted, height: 1.6),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
