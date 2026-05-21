// ============================================================================
// petlo - GroupSwitcherModal
// ============================================================================
//
// グループセレクターをタップすると表示されるモーダル。
//
// 構造 (rev5.3 §4.2):
//   ┌─────────────────────────────┐
//   │ Switch group       [Cancel] │
//   ├─────────────────────────────┤
//   │ ⊙ Personal                  │
//   │   1 pet · only on this device│
//   ├─────────────────────────────┤
//   │ ◉ お父さん家族 (active)      │
//   │   2 pets · 3 members · Owner│
//   ├─────────────────────────────┤
//   │ ○ ご近所ペットの会            │
//   │   1 pet · 5 members · Editor│
//   ├─────────────────────────────┤
//   │ + Create new group  (Pro)   │
//   └─────────────────────────────┘
//
// 使い方:
//   showModalBottomSheet(
//     context: context,
//     builder: (_) => const GroupSwitcherModal(),
//   );
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/local/app_database.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/group_selection_controller.dart';
import '../../providers/groups_providers.dart';
import '../../providers/scope_providers.dart';
import '../../screens/groups/create_group_screen.dart';
import 'group_role_badge.dart';

class GroupSwitcherModal extends ConsumerWidget {
  const GroupSwitcherModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final String currentGroupId = ref.watch(currentGroupIdProvider);
    final AsyncValue<List<GroupEntity>> groupsAsync =
        ref.watch(userGroupsProvider);
    final AsyncValue<int> remainingSlots =
        ref.watch(remainingGroupSlotsProvider);

    final controller = ref.read(groupSelectionControllerProvider.notifier);

    return Container(
      color: colors.bg,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Header(onCancel: () => Navigator.of(context).pop()),
            const Divider(height: 1),

            // Personal row
            _GroupRow.personal(
              isSelected: currentGroupId == kPersonalGroupId,
              onTap: () async {
                await controller.switchToPersonal();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),

            // Group rows
            groupsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (Object e, StackTrace st) => _ErrorRow(message: '$e'),
              data: (List<GroupEntity> groups) => Column(
                children: <Widget>[
                  for (final GroupEntity g in groups)
                    _GroupRow.group(
                      group: g,
                      isSelected: currentGroupId == g.remoteId,
                      onTap: () async {
                        await controller.switchTo(g.remoteId);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),

            // Create new group row
            // build 30: モーダル内で完結させる。
            // 旧設計は外部から onCreateNewGroup callback を渡す方針だったが、
            // 全 5 タブ画面どこからも渡しておらず、結果として永久に
            // onTap=null になって LIMIT REACHED 誤判定になっていた。
            _CreateNewGroupRow(
              remainingSlots: remainingSlots.maybeWhen(
                data: (int n) => n,
                orElse: () => 0,
              ),
              onTap: () async {
                final NavigatorState navigator = Navigator.of(context);
                final String? createdGroupId =
                    await CreateGroupScreen.push(context);
                if (createdGroupId != null) {
                  await controller.switchTo(createdGroupId);
                }
                navigator.pop(); // モーダルを閉じる
              },
            ),

            // Footer info
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 32),
              child: Text(
                _slotsText(remainingSlots),
                style: typo.metaSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _slotsText(AsyncValue<int> remaining) {
    return remaining.maybeWhen(
      data: (int n) {
        final int used = 3 - n;
        return '$used of 3 groups used';
      },
      orElse: () => '',
    );
  }
}

// ============================================================================
// Header
// ============================================================================
class _Header extends StatelessWidget {
  const _Header({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Text(
              'Switch group',
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontStyle: FontStyle.italic,
                fontSize: 36,
                letterSpacing: -36 * 0.04,
                height: 0.95,
                color: colors.fg,
              ),
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                AppLocalizations.of(context).common_cancel.toUpperCase(),
                style: typo.metaSmall.copyWith(color: colors.fgMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// GroupRow (Personal / Shared共用)
// ============================================================================
class _GroupRow extends StatelessWidget {
  const _GroupRow.personal({
    required this.isSelected,
    required this.onTap,
  })  : _kind = _RowKind.personal,
        _name = 'Personal',
        _meta = '1 pet · only on this device',
        _badge = null;

  _GroupRow.group({
    required GroupEntity group,
    required this.isSelected,
    required this.onTap,
  })  : _kind = _RowKind.group,
        _name = group.name,
        _meta = '${group.myPermission.name} · last active', // TODO: メンバー数等
        _badge = group.myPermission;

  final _RowKind _kind;
  final String _name;
  final String _meta;
  final MemberPermission? _badge;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$_name, $_meta',
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: colors.bgSoft,
        child: Container(
          color: isSelected ? colors.bgSoft : null,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingPage,
            vertical: 20,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _RadioMark(isSelected: isSelected),
              const SizedBox(width: AppDimensions.gapLarge),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _name,
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontStyle: FontStyle.italic,
                        fontSize: 22,
                        height: 1.0,
                        color: colors.fg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _meta,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w500,
                        fontSize: 9,
                        letterSpacing: 9 * 0.15,
                        color: colors.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (_kind == _RowKind.personal)
                const GroupRoleBadge.localOnly()
              else
                GroupRoleBadge.role(permission: _badge!),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.isSelected});
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? colors.fg : colors.fgMuted,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.fg,
                ),
              ),
            )
          : null,
    );
  }
}

// ============================================================================
// "+ Create new group" Row
// ============================================================================
class _CreateNewGroupRow extends StatelessWidget {
  const _CreateNewGroupRow({
    required this.remainingSlots,
    required this.onTap,
  });

  final int remainingSlots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    // build 30: 旧コードは `&& onTap != null` で判定していたが、
    // 呼び出し側から callback が来ないケースが多数あり常に false に落ちていた。
    // モーダル内で navigation を完結させた今は残数だけで判定する。
    final bool enabled = remainingSlots > 0;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingPage,
          vertical: 24,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.fgMuted, width: 1),
              ),
              alignment: Alignment.center,
              child: Text(
                '+',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 18,
                  color: colors.fgMuted,
                ),
              ),
            ),
            const SizedBox(width: AppDimensions.gapMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Create new group',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 16,
                      color: enabled ? colors.fg : colors.fgFaint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled ? 'PRO · UP TO 3 GROUPS' : 'GROUP LIMIT REACHED',
                    style: typo.metaSmall.copyWith(
                      color: enabled ? colors.fgMuted : colors.accentWarn,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Helpers
// ============================================================================

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppDimensions.paddingPage),
      child: Text(
        'Could not load groups: $message',
        style: TextStyle(color: colors.accentDanger, fontSize: 12),
      ),
    );
  }
}

enum _RowKind { personal, group }
