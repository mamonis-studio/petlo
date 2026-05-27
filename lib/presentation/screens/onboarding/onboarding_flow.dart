// ============================================================================
// petlo - Onboarding Flow
// ============================================================================
//
// 初回起動時のチュートリアル。4ページ:
//   1. Welcome    — petlo の哲学
//   2. Pillars    — 5本柱の紹介
//   3. Pet form   — ペット登録
//   4. Done       — 完了 + TabShell へ
//
// rev5.4 §4.7
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../providers/onboarding_completed_provider.dart';
import '../tab_shell.dart';
import 'pages/onboarding_done_page.dart';
import 'pages/onboarding_pet_form_page.dart';
import 'pages/onboarding_pillars_page.dart';
import 'pages/onboarding_welcome_page.dart';

class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() =>
      _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  late final PageController _pageC;
  int _currentPage = 0;

  static const int _totalPages = 4;

  @override
  void initState() {
    super.initState();
    _pageC = PageController();
  }

  @override
  void dispose() {
    _pageC.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _totalPages - 1) {
      _pageC.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  void _back() {
    if (_currentPage > 0) {
      _pageC.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _finish() async {
    await ref
        .read(onboardingCompletedProvider.notifier)
        .markCompleted();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const TabShell(),
      ),
    );
  }

  /// Skipボタン (Welcome / Pillars のみ表示、Form 以降は skip 不可)
  Future<void> _skip() async {
    // Pet form をスキップした場合でも、データなしで TabShell に飛ばす。
    // ユーザーが後から Settings → 「Add pet」で追加できる前提。
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // ===== 上部 progress + skip =====
            _ProgressBar(
              current: _currentPage,
              total: _totalPages,
              showSkip: _currentPage < 2,
              onSkip: _skip,
              colors: colors,
            ),

            // ===== ページコンテンツ =====
            Expanded(
              child: PageView(
                controller: _pageC,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (int i) =>
                    setState(() => _currentPage = i),
                children: <Widget>[
                  OnboardingWelcomePage(onNext: _next),
                  OnboardingPillarsPage(onNext: _next),
                  OnboardingPetFormPage(
                    onNext: _next,
                    onSkip: _next, // フォームスキップは最終画面へ
                  ),
                  OnboardingDonePage(onFinish: _finish),
                ],
              ),
            ),

            // ===== 戻るボタン (Welcomeでは表示しない) =====
            if (_currentPage > 0 && _currentPage < _totalPages - 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextButton(
                  onPressed: _back,
                  child: Text(
                    'BACK',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 10 * 0.18,
                      color: colors.fgMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _ProgressBar
// ============================================================================
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.current,
    required this.total,
    required this.showSkip,
    required this.onSkip,
    required this.colors,
  });

  final int current;
  final int total;
  final bool showSkip;
  final VoidCallback onSkip;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 16, 8),
      child: Row(
        children: <Widget>[
          // ステップドット (0..total-1)
          for (int i = 0; i < total; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 6),
            Container(
              width: i == current ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i <= current ? colors.fg : colors.line,
              ),
            ),
          ],
          const Spacer(),
          if (showSkip)
            TextButton(
              onPressed: onSkip,
              child: Text(
                'SKIP',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 10 * 0.18,
                  color: colors.fgMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
