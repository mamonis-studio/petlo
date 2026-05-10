// ============================================================================
// petlo - Theme Mode Provider
// ============================================================================
//
// テーマモードを永続化付き Notifier で管理。
//
// MaterialApp の themeMode に渡す。
// 起動時は UserPreferences から復元、変更時は永続化。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences/user_preferences.dart';

final NotifierProvider<ThemeModeNotifier, AppThemeMode>
    themeModeProvider = NotifierProvider<ThemeModeNotifier, AppThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    return UserPreferences.instance.themeMode;
  }

  Future<void> select(AppThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    await UserPreferences.instance.setThemeMode(mode);
  }
}
