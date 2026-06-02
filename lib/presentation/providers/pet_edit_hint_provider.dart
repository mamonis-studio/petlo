// ============================================================================
// petlo - Pet Edit Hint Provider (build 58)
// ============================================================================
//
// 「長押しで編集・削除」ヒントの表示制御。
//   - 初期値: SharedPreferences の `has_opened_pet_edit` を読む
//   - true → 一度でも編集画面を開いた → ヒント永続非表示
//   - false → まだ → ヒント表示
//
// PetFormScreen (editingPetId 指定) を開くタイミングで markOpened() を呼ぶ。
// 一度立てたら以降は再起動を跨いでも消えたまま。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import 'storage_providers.dart';

/// true = ヒント非表示、false = 初回まだ
final NotifierProvider<PetEditHintNotifier, bool>
    hasOpenedPetEditProvider =
    NotifierProvider<PetEditHintNotifier, bool>(
  PetEditHintNotifier.new,
);

class PetEditHintNotifier extends Notifier<bool> {
  @override
  bool build() {
    // 同期で読めないので、起動直後は false (= ヒント表示) として、
    // 非同期で SharedPreferences から復元する。
    _restore();
    return false;
  }

  Future<void> _restore() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final bool? saved = await prefs.getBool(PrefsKeys.hasOpenedPetEdit);
      if (saved == true && saved != state) {
        state = true;
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('hasOpenedPetEdit restore failed', error: e, stackTrace: st);
    }
  }

  /// ペット編集画面に遷移したタイミングで呼ぶ。永続化 + state を true に。
  Future<void> markOpened() async {
    if (state == true) return;
    state = true;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setBool(PrefsKeys.hasOpenedPetEdit, true);
    } catch (e, st) {
      PetloLogger.instance
          .w('hasOpenedPetEdit persist failed', error: e, stackTrace: st);
    }
  }
}
