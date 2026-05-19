// ============================================================================
// petlo - GroupSelectorBar
// ============================================================================
//
// rev5.3 §4.1 トップバー2階層目。全画面共通で常時表示。
//
// 構造:
//   [GROUP] [▾ お父さん家族]  ........... [Owner]
//
// 動作:
//   - タップで GroupSwitcherModal を表示
//   - currentGroupId / currentRole に連動
//   - Personal時: "▾ Personal" + "Local only" バッジ
//   - グループ時: "▾ <グループ名>" + 権限バッジ
//
// rev5.5 §4.15: pendingDeletion 状態のグループは警告色のテキスト
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/groups_providers.dart';
import '../../providers/scope_providers.dart';
import 'group_role_badge.dart';
import 'group_switcher_modal.dart';

class GroupSelectorBar extends ConsumerWidget {
  const GroupSelectorBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isPersonal = ref.watch(isPersonalScopeProvider);
    final AsyncValue<GroupEntity?> currentGroupAsync =
        ref.watch(currentGroupProvider);
    final MemberPermission role = ref.watch(currentRoleProvider);

    final String displayName = isPersonal
        ? l10n.group_selector_personal
        : currentGroupAsync.maybeWhen(
            data: (GroupEntity? g) => g?.name ?? '...',
            orElse: () => '...',
          );

    final bool isPendingDeletion = !isPersonal &&
        currentGroupAsync.maybeWhen(
          data: (GroupEntity? g) => g?.status == GroupStatus.pendingDeletion,
          orElse: () => false,
        );

    return Material(
      color: colors.bgSoft,
      child: InkWell(
        onTap: () => _openSwitcher(context),
        splashColor: Colors.transparent,
        highlightColor: colors.bg,
        child: Container(
          height: AppDimensions.groupSelectorHeight,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.line),
              bottom: BorderSide(color: colors.line),
            ),
          ),
          child: Semantics(
            button: true,
            label: 'Current group: $displayName, ${role.name}. Double tap to switch.',
            excludeSemantics: true,
            child: Row(
              children: <Widget>[
                // Label "GROUP"
                Text(
                  l10n.group_selector_label,
                  style: typo.metaSmall.copyWith(color: colors.fgMuted),
                ),
                const SizedBox(width: AppDimensions.gapSmall),

                // chevron
                Text(
                  '▾',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.fgMuted,
                  ),
                ),
                const SizedBox(width: 6),

                // Group name (Expanded で残り幅を全部取る、バッジは右端固定)
                Expanded(
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 16,
                      color: isPendingDeletion
                          ? colors.accentWarn
                          : colors.fg,
                    ),
                  ),
                ),

                const SizedBox(width: AppDimensions.gapSmall),

                // Right-side badge
                if (isPersonal)
                  const GroupRoleBadge.localOnly()
                else
                  GroupRoleBadge.role(permission: role),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSwitcher(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext _) => const GroupSwitcherModal(),
    );
  }
}
