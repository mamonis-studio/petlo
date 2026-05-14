// ============================================================================
// petlo - Tab Index
// ============================================================================
//
// 5タブ構造の enum と現在タブを保持する Provider。
//
// rev3 モック仕様:
//   Home / Life / Health / Plans / More
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 5タブの種別
enum AppTab {
  home,
  life,
  health,
  plans,
  ai;

  /// JetBrainsMono大文字ラベル(タブバー表示用)
  String get label {
    switch (this) {
      case AppTab.home:
        return 'Home';
      case AppTab.life:
        return 'Life';
      case AppTab.health:
        return 'Health';
      case AppTab.plans:
        return 'Plans';
      case AppTab.ai:
        return 'AI';
    }
  }
}

/// 現在のタブ
final NotifierProvider<CurrentTabNotifier, AppTab> currentTabProvider =
    NotifierProvider<CurrentTabNotifier, AppTab>(CurrentTabNotifier.new);

class CurrentTabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  void select(AppTab tab) {
    if (state == tab) return;
    state = tab;
  }
}
