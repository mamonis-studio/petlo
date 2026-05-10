// ============================================================================
// petlo - Database Provider
// ============================================================================
//
// AppDatabase をアプリ全体でシングルトンとして提供する。
//
// アプリ終了時にdb.close()を確実に呼ぶため、ProviderScopeのoverridesで
// 明示的にdisposeする想定。Riverpodの autoDispose は使わない (DBはアプリ寿命と同じ)。
//
// テスト時は overrideWithValue で AppDatabase.forTesting(NativeDatabase.memory()) を渡せる。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';

final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (Ref ref) {
    final AppDatabase db = AppDatabase();
    // アプリ終了時(ProviderContainer破棄時)にDBクローズ
    ref.onDispose(db.close);
    return db;
  },
);
