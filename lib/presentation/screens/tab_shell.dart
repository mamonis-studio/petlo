// ============================================================================
// petlo - Tab Shell
// ============================================================================
//
// 5タブのRoot Widget。
//
// 各タブは IndexedStack で状態を保持しながら切り替え。
// (TabBarView と違って未visibleタブのStateも生きる → 戻った時にスクロール位置が残る)
//
// PetloScaffold は各タブが独立して持つ(タブ毎に異なるトップバー設定可能)。
//
// rev6 (UX 改修):
//   - F-80 警告は常時バナーを廃止 → ヘッダー右上の⚠アイコン + 起動時 SnackBar
//   - SnackBar は アプリ起動後 1 回のみ(タブ切替で再表示しない)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/app_database.dart';
import '../../l10n/generated/app_localizations.dart';
import '../providers/groups_providers.dart';
import '../providers/pet_selection_controller.dart';
import '../providers/pets_providers.dart';
import '../providers/scope_providers.dart';
import '../providers/tab_provider.dart';
import '../widgets/groups/group_closure_banner.dart';
import '../widgets/tabs/petlo_tab_bar.dart';
import 'ai_chat/ai_tab_screen.dart';
import 'groups/group_detail_screen.dart';
import 'health/health_tab_screen.dart';
import 'home/home_tab_screen.dart';
import 'life/life_tab_screen.dart';
import 'plans/plans_tab_screen.dart';

class TabShell extends ConsumerStatefulWidget {
  const TabShell({super.key});

  @override
  ConsumerState<TabShell> createState() => _TabShellState();
}

class _TabShellState extends ConsumerState<TabShell> {
  bool _warningSnackbarShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkClosureWarning();
    });
  }

  Future<void> _checkClosureWarning() async {
    // 起動直後の画面遷移を待ってから表示
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted || _warningSnackbarShown) return;

    final AsyncValue<GroupEntity?> groupAsync =
        ref.read(currentGroupProvider);
    final GroupEntity? group =
        groupAsync.maybeWhen(data: (g) => g, orElse: () => null);
    if (group == null) return;
    if (!GroupClosureBanner.shouldShow(group)) return;

    _warningSnackbarShown = true;
    if (!mounted) return;

    final AppColors colors = AppColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.fg,
        content: Row(
          children: <Widget>[
            CustomPaint(
              size: const Size(20, 20),
              painter: _BrandWarningPainter(color: colors.bg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.of(context)
                    .tab_shell_group_closure_warning_title(group.name),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  color: colors.bg,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: colors.bg,
          onPressed: () {
            GroupDetailScreen.push(
              context,
              groupRemoteId: group.remoteId,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTab currentTab = ref.watch(currentTabProvider);

    // build 10: タブ切替時に showAllPets=false タブへ移動 + 現在 petId="all" なら
    // 先頭ペットを自動選択。ref.listen は build 内で安全に再登録可能。
    ref.listen<AppTab>(currentTabProvider, (AppTab? prev, AppTab next) {
      if (prev == next) return;
      if (_tabShowsAllPets(next)) return; // よていなどは All Pets を許容
      final String? petIdStr = ref.read(currentPetIdProvider);
      if (petIdStr != kAllPetsId) return;
      final List<PetEntity>? pets =
          ref.read(currentGroupPetsProvider).valueOrNull;
      if (pets == null || pets.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(petSelectionControllerProvider.notifier)
            .selectPet(pets.first.id);
      });
    });

    // Material で外側を colors.bg に塗ることで、edge-to-edge 化された
    // ステータスバー / Dynamic Island / ホームインジケーター領域も
    // 白背景で塗られる(問題 1: 黒帯解消)。
    return Material(
      color: colors.bg,
      child: Scaffold(
        backgroundColor: colors.bg,
        // SystemNavigationBar用の余白を効かせる
        extendBody: false,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: currentTab.index,
            children: const <Widget>[
              HomeTabScreen(),
              LifeTabScreen(),
              HealthTabScreen(),
              PlansTabScreen(),
              AiTabScreen(),
            ],
          ),
        ),
        bottomNavigationBar: PetloTabBar(
          currentTab: currentTab,
          onTabSelected: (AppTab tab) =>
              ref.read(currentTabProvider.notifier).select(tab),
        ),
      ),
    );
  }
}

/// このタブが All Pets ピル表示を許容するか。
/// 現状は plans (よてい) のみ。
bool _tabShowsAllPets(AppTab tab) => tab == AppTab.plans;

// ============================================================================
// _BrandWarningPainter — SnackBar / BrandBar 共用の線画警告アイコン
// (group_closure_banner.dart:_WarningPainter のコピー、共通化は v1.1 で実施)
// ============================================================================
class _BrandWarningPainter extends CustomPainter {
  _BrandWarningPainter({required this.color});

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
  bool shouldRepaint(covariant _BrandWarningPainter old) =>
      old.color != color;
}
