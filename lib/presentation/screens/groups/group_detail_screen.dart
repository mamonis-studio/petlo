// ============================================================================
// petlo - Group Detail Screen
// ============================================================================
//
// グループの詳細 (メンバー一覧 + 招待コード発行 + 退出)。
//
// レイアウト:
//   - eyebrow + ヒーロー(グループ名)
//   - Owner時: "Issue invite code" ボタン → BottomSheet で権限選択 → コード表示
//   - メンバー一覧 (自分以外、Owner時は権限変更/除名アクション)
//   - 退出 ボタン (画面末尾、確認ダイアログ付き)
//
// rev5.3 F-25/F-29/F-29a/F-29b/F-30
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/groups/group_api_dtos.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/outlined_action_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../providers/group_members_providers.dart';
import '../../providers/groups_providers.dart';
import '../../widgets/groups/group_closure_banner.dart';
import 'group_detail_controller.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({required this.groupRemoteId, super.key});

  final String groupRemoteId;

  static Future<void> push(
    BuildContext context, {
    required String groupRemoteId,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailScreen(groupRemoteId: groupRemoteId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final groupsRepo = ref.watch(groupsRepositoryProvider);
    final AsyncValue<List<GroupMemberEntity>> membersAsync =
        ref.watch(membersForGroupProvider(groupRemoteId));
    final GroupDetailState state =
        ref.watch(groupDetailControllerProvider(groupRemoteId));
    final GroupDetailController controller = ref
        .read(groupDetailControllerProvider(groupRemoteId).notifier);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'GROUP',
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
        child: StreamBuilder<GroupEntity?>(
          stream: groupsRepo.watchGroupByRemoteId(groupRemoteId),
          builder: (BuildContext c,
              AsyncSnapshot<GroupEntity?> snap) {
            final GroupEntity? group = snap.data;
            if (group == null) {
              return const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 1.5),
                ),
              );
            }
            final bool isOwner =
                group.myPermission == MemberPermission.owner;
            return SingleChildScrollView(
              padding:
                  const EdgeInsets.fromLTRB(28, 8, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionLabel(
                    group.name,
                    size: EyebrowSize.large,
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  ),
                  _PermissionBadge(
                    permission: group.myPermission,
                    colors: colors,
                  ),
                  const SizedBox(height: 24),

                  // ===== F-80: Pro解約30日カウントダウン =====
                  GroupClosureBanner(group: group),

                  // ===== Owner: 招待コード発行 =====
                  if (isOwner) ...<Widget>[
                    OutlinedActionButton(
                      label: state.isIssuingInvite
                          ? 'Issuing...'
                          : 'Issue invite code',
                      onPressed: state.isIssuingInvite
                          ? null
                          : () => _onIssueInvite(
                              context, controller),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ===== メンバー =====
                  membersAsync.when(
                    data: (List<GroupMemberEntity> list) {
                      // 自分含めた人数を表示するため +1
                      return Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'MEMBERS · ${list.length + 1}',
                            style: TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 9,
                              letterSpacing: 9 * 0.2,
                              color: colors.fgMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 自分の行
                          _MemberRow(
                            displayName: 'You',
                            permission: group.myPermission,
                            isSelf: true,
                            isOwner: isOwner,
                            onUpdatePermission: null,
                            onRemove: null,
                          ),
                          // 他のメンバー
                          for (final GroupMemberEntity m in list)
                            _MemberRow(
                              displayName: m.displayName,
                              permission: m.permission,
                              isSelf: false,
                              isOwner: isOwner,
                              onUpdatePermission: isOwner
                                  ? (MemberPermission p) =>
                                      _onUpdatePermission(
                                        context,
                                        controller,
                                        m.userId,
                                        m.displayName,
                                        p,
                                      )
                                  : null,
                              onRemove: isOwner
                                  ? () => _onRemoveMember(
                                        context,
                                        controller,
                                        m.userId,
                                        m.displayName,
                                      )
                                  : null,
                            ),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5),
                        ),
                      ),
                    ),
                    error: (Object e, _) => Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 24),
                      child: Text(
                        'Failed to load members',
                        style: typo.bodySmall.copyWith(
                            color: colors.fgMuted),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ===== 退出ボタン (Owner以外、または最後のOwnerは不可) =====
                  SectionLabel(AppLocalizations.of(context).section_danger_zone),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: state.isLeaving
                        ? null
                        : () =>
                            _onLeaveGroup(context, controller),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: colors.accentDanger, width: 1),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  state.isLeaving
                                      ? AppLocalizations.of(context)
                                          .group_detail_leaving
                                      : AppLocalizations.of(context)
                                          .group_detail_leave_button,
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 14,
                                    color: colors.accentDanger,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  AppLocalizations.of(context)
                                      .group_detail_leave_note,
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 12,
                                    color: colors.fgMuted,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ==========================================================================
  // Actions
  // ==========================================================================

  Future<void> _onIssueInvite(
    BuildContext context,
    GroupDetailController controller,
  ) async {
    final MemberPermission? permission =
        await showModalBottomSheet<MemberPermission>(
      context: context,
      backgroundColor: AppColors.of(context).bg,
      builder: (_) => const _PermissionPickerSheet(),
    );
    if (permission == null) return;

    final CreateInviteResultDto? result =
        await controller.issueInvite(permission, AppLocalizations.of(context));
    if (result == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).groups_snackbar_invite_issue_failed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => _IssuedCodeDialog(result: result),
      );
    }
  }

  Future<void> _onUpdatePermission(
    BuildContext context,
    GroupDetailController controller,
    String userId,
    String displayName,
    MemberPermission newPermission,
  ) async {
    final bool ok = await controller.updateMemberPermission(
      userId: userId,
      permission: newPermission,
      l10n: AppLocalizations.of(context),
    );
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).groups_snackbar_role_changed(displayName)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onRemoveMember(
    BuildContext context,
    GroupDetailController controller,
    String userId,
    String displayName,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)
            .group_detail_remove_member_title),
        content: Text(AppLocalizations.of(dialogContext)
            .groups_snackbar_member_remove_confirm(displayName)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(dialogContext).common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(dialogContext)
                .group_detail_remove_member_action),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final bool ok =
        await controller.removeMember(userId, AppLocalizations.of(context));
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).groups_snackbar_member_removed(displayName)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onLeaveGroup(
    BuildContext context,
    GroupDetailController controller,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)
            .group_detail_leave_dialog_title),
        content: Text(AppLocalizations.of(dialogContext)
            .group_detail_leave_dialog_body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(dialogContext).common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(dialogContext)
                .group_detail_leave_action),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final bool ok = await controller.leaveGroup(AppLocalizations.of(context));
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).groups_snackbar_left),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    }
  }
}

// ============================================================================
// _PermissionBadge - 自分の権限を表示
// ============================================================================
class _PermissionBadge extends StatelessWidget {
  const _PermissionBadge({
    required this.permission,
    required this.colors,
  });

  final MemberPermission permission;
  final AppColors colors;

  String get _label {
    switch (permission) {
      case MemberPermission.owner:
        return 'YOU · OWNER';
      case MemberPermission.editor:
        return 'YOU · EDITOR';
      case MemberPermission.viewer:
        return 'YOU · VIEWER';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: colors.fg, width: 1),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 9,
          letterSpacing: 9 * 0.2,
          color: colors.fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ============================================================================
// _MemberRow - メンバー1行
// ============================================================================
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.displayName,
    required this.permission,
    required this.isSelf,
    required this.isOwner,
    required this.onUpdatePermission,
    required this.onRemove,
  });

  final String displayName;
  final MemberPermission permission;
  final bool isSelf;
  /// 自分が Owner かどうか(他人の権限変更・除名権限の判定用)
  final bool isOwner;
  final ValueChanged<MemberPermission>? onUpdatePermission;
  final VoidCallback? onRemove;

  String get _permLabel {
    switch (permission) {
      case MemberPermission.owner:
        return 'OWNER';
      case MemberPermission.editor:
        return 'EDITOR';
      case MemberPermission.viewer:
        return 'VIEWER';
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool canShowMenu = !isSelf &&
        isOwner &&
        permission != MemberPermission.owner;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      displayName,
                      style: typo.bodyLarge.copyWith(color: colors.fg),
                    ),
                    if (isSelf) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        '· you',
                        style: typo.bodySmall
                            .copyWith(color: colors.fgFaint),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _permLabel,
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 9,
                    letterSpacing: 9 * 0.2,
                    color: colors.fgMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (canShowMenu)
            PopupMenuButton<_MemberAction>(
              icon: Icon(Icons.more_vert,
                  size: 18, color: colors.fgMuted),
              onSelected: (a) {
                switch (a) {
                  case _MemberAction.makeEditor:
                    onUpdatePermission?.call(MemberPermission.editor);
                  case _MemberAction.makeViewer:
                    onUpdatePermission?.call(MemberPermission.viewer);
                  case _MemberAction.remove:
                    onRemove?.call();
                }
              },
              itemBuilder: (BuildContext menuCtx) =>
                  <PopupMenuEntry<_MemberAction>>[
                if (permission != MemberPermission.editor)
                  PopupMenuItem<_MemberAction>(
                    value: _MemberAction.makeEditor,
                    child: Text(AppLocalizations.of(menuCtx)
                        .group_detail_member_action_make_editor),
                  ),
                if (permission != MemberPermission.viewer)
                  PopupMenuItem<_MemberAction>(
                    value: _MemberAction.makeViewer,
                    child: Text(AppLocalizations.of(menuCtx)
                        .group_detail_member_action_make_viewer),
                  ),
                PopupMenuItem<_MemberAction>(
                  value: _MemberAction.remove,
                  child: Text(AppLocalizations.of(menuCtx)
                      .group_detail_member_action_remove),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _MemberAction { makeEditor, makeViewer, remove }

// ============================================================================
// _PermissionPickerSheet - 招待コード発行時の権限選択
// ============================================================================
class _PermissionPickerSheet extends StatelessWidget {
  const _PermissionPickerSheet();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            EyebrowText(AppLocalizations.of(context).section_invite_permission),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).invite_permission_picker_hero,
              style: typo.heroName
                  .copyWith(height: 0.95, fontSize: 36),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).invite_permission_picker_body,
              style: typo.bodyMedium
                  .copyWith(color: colors.fgMuted, height: 1.6),
            ),
            const SizedBox(height: 24),
            _PickerRow(
              label: AppLocalizations.of(context).invite_permission_editor_label,
              note: AppLocalizations.of(context).invite_permission_editor_note,
              onTap: () =>
                  Navigator.of(context).pop(MemberPermission.editor),
            ),
            _PickerRow(
              label: AppLocalizations.of(context).invite_permission_viewer_label,
              note: AppLocalizations.of(context).invite_permission_viewer_note,
              onTap: () =>
                  Navigator.of(context).pop(MemberPermission.viewer),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.note,
    required this.onTap,
  });

  final String label;
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
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
                    label,
                    style: typo.bodyLarge.copyWith(color: colors.fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: typo.bodySmall
                        .copyWith(color: colors.fgMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: colors.fgMuted),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _IssuedCodeDialog - 発行された6桁コード表示
// ============================================================================
class _IssuedCodeDialog extends StatelessWidget {
  const _IssuedCodeDialog({required this.result});

  final CreateInviteResultDto result;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final Duration remaining =
        result.expiresAt.difference(DateTime.now());
    final int hours = remaining.inHours;
    return AlertDialog(
      backgroundColor: colors.bg,
      title: Text(
        'Invite code',
        style: typo.bodyLarge.copyWith(color: colors.fg),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Text(
              result.code,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 36,
                letterSpacing: 36 * 0.15,
                color: colors.fg,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context).invite_code_dialog_permission_label(
                result.grantedPermission.name.toUpperCase()),
            style: typo.bodySmall.copyWith(color: colors.fgMuted),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)
                .invite_code_dialog_expiry_label(hours.toString()),
            style: typo.bodySmall.copyWith(color: colors.fgMuted),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () async {
            await Clipboard.setData(
                ClipboardData(text: result.code));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context).groups_snackbar_code_copied),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: Text(AppLocalizations.of(context).common_copy),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).common_close),
        ),
      ],
    );
  }
}
