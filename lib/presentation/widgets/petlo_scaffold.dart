// ============================================================================
// petlo - PetloScaffold
// ============================================================================
//
// 全画面共通の Scaffold ラッパー。
// 3階層のトップバーをデフォルトで含む:
//
//   ┌──────────────────────────┐
//   │ Status bar (OS)          │
//   ├──────────────────────────┤
//   │ PETLO              ⚙     │  ← brand bar (slim)
//   ├──────────────────────────┤
//   │ Group: ▼ お父さん家族     │  ← group selector  (Chunk 7)
//   ├──────────────────────────┤
//   │ ◉ Taro · ○ Mike · +     │  ← pet selector   ★ Chunk 6で実装済み
//   ├──────────────────────────┤
//   │                          │
//   │ <body>                   │
//   │                          │
//   ├──────────────────────────┤
//   │ Tab bar (5 tabs)         │  ← (Chunk 14)
//   └──────────────────────────┘
//
// 画面ごとに「ヘッダー要素を非表示にしたい」場合は showXxx パラメータでON/OFF。
// オンボーディング、Personal scope、設定画面など特殊な状況で使う。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';
import '../../data/local/app_database.dart';
import '../providers/groups_providers.dart';
import '../screens/groups/group_detail_screen.dart';
import '../screens/settings/settings_screen.dart';
import 'group_selector/group_selector_bar.dart';
import 'groups/group_closure_banner.dart';
import 'pet_selector/pet_selector_bar.dart';

class PetloScaffold extends StatelessWidget {
  const PetloScaffold({
    required this.body,
    this.showBrandBar = true,
    this.showGroupSelector = true,
    this.showPetSelector = true,
    this.showTabBar = true,
    this.showAllPetsInSelector = false,
    this.onAddPetTapped,
    this.onCreateNewGroup,
    this.brandBarTrailing,
    super.key,
  });

  /// メインコンテンツ
  final Widget body;

  /// "PETLO" ロゴと歯車アイコンの行を表示するか
  final bool showBrandBar;

  /// グループセレクター
  final bool showGroupSelector;

  /// ペットセレクター
  final bool showPetSelector;

  /// 下部タブバー(Chunk 14で完全実装)
  final bool showTabBar;

  /// ペットセレクターで "All pets" ピルを表示するか
  /// rev5.1 F-00b: ホーム画面のみ true、それ以外画面では個別ペット必須
  final bool showAllPetsInSelector;

  /// "+" 追加ピル押下時のコールバック (Chunk 8で本実装と接続)
  final VoidCallback? onAddPetTapped;

  /// "+ Create new group" 選択時のコールバック (Phase 4で本実装と接続)
  final VoidCallback? onCreateNewGroup;

  /// brandBarの右側カスタムウィジェット (デフォルトは設定アイコン)
  final Widget? brandBarTrailing;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    // SafeArea は TabShell 側で確保済み(rev6 改修、二重塗り解消)
    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: <Widget>[
          if (showBrandBar) _BrandBar(trailing: brandBarTrailing),
          if (showGroupSelector)
            GroupSelectorBar(onCreateNewGroup: onCreateNewGroup),
          if (showPetSelector)
            PetSelectorBar(
              showAllPets: showAllPetsInSelector,
              onAddPetTapped: onAddPetTapped,
            ),
          Expanded(child: body),
          if (showTabBar) const _TabBarPlaceholder(),
        ],
      ),
    );
  }
}

// ============================================================================
// Brand Bar
// ============================================================================
class _BrandBar extends ConsumerWidget {
  const _BrandBar({this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);

    // F-80 警告状態の判定(警告時のみ⚠アイコンを歯車左に表示)
    final AsyncValue<GroupEntity?> groupAsync =
        ref.watch(currentGroupProvider);
    final GroupEntity? currentGroup =
        groupAsync.maybeWhen(data: (g) => g, orElse: () => null);
    final bool hasWarning = currentGroup != null &&
        GroupClosureBanner.shouldShow(currentGroup);

    return Container(
      height: AppDimensions.brandBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(
          bottom: BorderSide(color: colors.line),
        ),
      ),
      child: Row(
        children: <Widget>[
          // ロゴ
          Text(
            'PETLO',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w500,
              fontSize: 11,
              letterSpacing: 11 * 0.4,
              color: colors.fgMuted,
            ),
          ),
          const Spacer(),
          // 警告⚠アイコン(警告状態のみ、歯車の左)
          if (hasWarning) ...<Widget>[
            _BrandBarWarningButton(group: currentGroup),
            const SizedBox(width: 12),
          ],
          // 右端 (デフォルトは歯車、上書き可能)
          trailing ?? const _SettingsButtonPlaceholder(),
        ],
      ),
    );
  }
}

class _BrandBarWarningButton extends StatelessWidget {
  const _BrandBarWarningButton({required this.group});

  final GroupEntity group;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => GroupDetailScreen.push(
        context,
        groupRemoteId: group.remoteId,
      ),
      child: SizedBox(
        width: AppDimensions.iconBtnSize,
        height: AppDimensions.iconBtnSize,
        child: Center(
          child: CustomPaint(
            size: const Size(18, 18),
            painter: _BrandBarWarningPainter(color: colors.accentDanger),
          ),
        ),
      ),
    );
  }
}

class _BrandBarWarningPainter extends CustomPainter {
  _BrandBarWarningPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path triangle = Path()
      ..moveTo(size.width * 0.5, size.height * 0.1)
      ..lineTo(size.width * 0.95, size.height * 0.9)
      ..lineTo(size.width * 0.05, size.height * 0.9)
      ..close();
    canvas.drawPath(triangle, p);

    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.4),
      Offset(size.width * 0.5, size.height * 0.65),
      p,
    );

    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.78),
      0.8,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _BrandBarWarningPainter old) =>
      old.color != color;
}

class _SettingsButtonPlaceholder extends StatelessWidget {
  const _SettingsButtonPlaceholder();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: () => SettingsScreen.push(context),
      child: SizedBox(
        width: AppDimensions.iconBtnSize,
        height: AppDimensions.iconBtnSize,
        child: Icon(Icons.settings_outlined, size: 20, color: colors.fgMuted),
      ),
    );
  }
}

// ============================================================================
// Tab Bar (placeholder, Chunk 14で完全版)
// ============================================================================
class _TabBarPlaceholder extends StatelessWidget {
  const _TabBarPlaceholder();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.only(top: 12, bottom: 12 + bottomInset),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Center(
        child: Text('TAB BAR (Chunk 14)', style: typo.metaSmall),
      ),
    );
  }
}
