// ============================================================================
// petlo - Onboarding Completed Provider
// ============================================================================
//
// 初回起動チュートリアルの完了状態を管理。
//
// rev5.4 §4.7
//
// 起動時に値を読み出し、未完了なら OnboardingFlow を表示、
// 完了なら通常の TabShell を表示する。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences/user_preferences.dart';

final NotifierProvider<OnboardingCompletedNotifier, bool>
    onboardingCompletedProvider =
    NotifierProvider<OnboardingCompletedNotifier, bool>(
  OnboardingCompletedNotifier.new,
);

class OnboardingCompletedNotifier extends Notifier<bool> {
  @override
  bool build() {
    return UserPreferences.instance.onboardingCompleted;
  }

  Future<void> markCompleted() async {
    state = true;
    await UserPreferences.instance.setOnboardingCompleted(true);
  }

  /// デバッグ用: オンボーディングを再表示するためのリセット
  /// (Settings画面の隠しメニュー等で呼ぶ想定、本番UIには出さない)
  Future<void> reset() async {
    state = false;
    await UserPreferences.instance.setOnboardingCompleted(false);
  }
}
