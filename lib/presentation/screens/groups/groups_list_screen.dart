// ============================================================================
// petlo - Groups List Screen
// ============================================================================
//
// 自分が参加しているグループ一覧 + 新規作成導線。
// More タブから push される。
//
// レイアウト:
//   - eyebrow + ヒーロー
//   - "Create new group" ボタン (Pro必須、無料時はPaywallへ)
//   - "Join with code" ボタン (誰でも)
//   - 既存グループ一覧 (タップで詳細画面へ)
//
// rev5.3 F-24/F-26
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../../core/widgets/outlined_action_button.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../providers/groups_providers.dart';
import '../../providers/pro_status_provider.dart';
import '../paywall/paywall_screen.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';
import 'join_by_code_screen.dart';

class GroupsListScreen extends ConsumerWidget {
  const GroupsListScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const GroupsListScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isPro = ref.watch(isProProvider);
    final AsyncValue<List<GroupEntity>> groupsAsync =
        ref.watch(userGroupsProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          AppLocalizations.of(context).appbar_groups,
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
                l10n.groups_list_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              ),
              Text(
                '家族や友人と、うちの子の記録を共有。',
                style: typo.bodyMedium
                    .copyWith(color: colors.fgMuted, height: 1.6),
              ),
              const SizedBox(height: 28),

              // ===== アクションボタン =====
              OutlinedActionButton(
                label: isPro ? 'Create new group' : 'Create new group · Pro',
                onPressed: () async {
                  if (!isPro) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            const Text('グループ作成は Pro プラン限定です'),
                        behavior: SnackBarBehavior.floating,
                        action: SnackBarAction(
                          label: 'VIEW PLANS',
                          onPressed: () => PaywallScreen.push(context),
                        ),
                      ),
                    );
                    return;
                  }
                  await CreateGroupScreen.push(context);
                },
              ),
              const SizedBox(height: 10),
              OutlinedActionButton(
                label: 'Join with code',
                onPressed: () => JoinByCodeScreen.push(context),
              ),
              const SizedBox(height: 32),

              // ===== グループ一覧 =====
              groupsAsync.when(
                data: (List<GroupEntity> list) {
                  if (list.isEmpty) {
                    return _EmptyState(colors: colors, typo: typo);
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'JOINED · ${list.length}',
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 9,
                          letterSpacing: 9 * 0.2,
                          color: colors.fgMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final GroupEntity g in list)
                        _GroupRow(group: g),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                ),
                error: (Object e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'Failed to load groups',
                    style: typo.bodySmall.copyWith(color: colors.fgMuted),
                  ),
                ),
              ),

              const SizedBox(height: 32),
              Text(
                '最大3つのグループに参加できます。',
                style: typo.bodySmall.copyWith(
                  color: colors.fgFaint,
                  height: 1.5,
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
            'No groups yet.',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 28,
              color: colors.fgMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '上のボタンから新しいグループを作るか、\n6桁コードで友人のグループに参加できます。',
            style: typo.bodyMedium
                .copyWith(color: colors.fgMuted, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// _GroupRow - グループ1件の表示
// ============================================================================
class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final GroupEntity group;

  String get _permissionLabel => switch (group.myPermission) {
        MemberPermission.owner => 'OWNER',
        MemberPermission.editor => 'EDITOR',
        MemberPermission.viewer => 'VIEWER',
      };

  String? get _statusBadge {
    switch (group.status) {
      case GroupStatus.active:
        return null;
      case GroupStatus.pendingDeletion:
        return 'PENDING DELETION';
      case GroupStatus.frozen:
        return 'FROZEN';
      case GroupStatus.deletionScheduled:
        return 'DELETION SCHEDULED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final String? badge = _statusBadge;
    final bool isWarning = badge != null;

    return InkWell(
      onTap: () =>
          GroupDetailScreen.push(context, groupRemoteId: group.remoteId),
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
                    group.name,
                    style: typo.bodyLarge.copyWith(color: colors.fg),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Text(
                        _permissionLabel,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 9,
                          letterSpacing: 9 * 0.18,
                          color: colors.fgMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (badge != null) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isWarning
                                  ? colors.accentWarn
                                  : colors.fg,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 8,
                              letterSpacing: 8 * 0.2,
                              color: isWarning
                                  ? colors.accentWarn
                                  : colors.fg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.fgMuted),
          ],
        ),
      ),
    );
  }
}
