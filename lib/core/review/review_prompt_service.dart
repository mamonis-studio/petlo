// ============================================================================
// petlo - Review Prompt Service (build 70)
// ============================================================================
//
// 通算記録数が閾値 (20 件) に達したら、`InAppReview.requestReview()` を
// 1 回だけ呼ぶ。
//
// 動作:
//   - onRecordAdded() は、8 種の記録 form_controller (meal / poop / pee /
//     vomit / diary / weight / temperature / visit) で repo.create() が
//     成功した直後に fire-and-forget で呼ばれる。
//   - SharedPreferences の `review.record_count` を +1。
//   - `review.requested` が既に true なら以降は何もしない。
//   - count が閾値未満なら return。
//   - 閾値以上で `InAppReview.isAvailable()` が true なら `requestReview()`
//     を呼んで `review.requested = true` を保存。
//   - `isAvailable()` が false の時は `requested` を立てない (次回の記録追加
//     で再試行できるように)。
//
// 注意: 実際にレビューポップアップが出るかは OS 任せ (iOS は年 3 回まで)。
// ============================================================================

import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';

class ReviewPromptService {
  ReviewPromptService._();

  static final ReviewPromptService instance = ReviewPromptService._();

  static const int _kReviewThreshold = 20;
  static const String _kRecordCountKey = 'review.record_count';
  static const String _kRequestedKey = 'review.requested';

  /// 8 種の記録の form_controller が DB insert 成功直後に fire-and-forget で
  /// 呼ぶ。例外は内部で握り潰して呼び出し側の save 動線をブロックしない。
  Future<void> onRecordAdded() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kRequestedKey) ?? false) return;
      final int next = (prefs.getInt(_kRecordCountKey) ?? 0) + 1;
      await prefs.setInt(_kRecordCountKey, next);
      if (next < _kReviewThreshold) return;
      final InAppReview inAppReview = InAppReview.instance;
      if (!(await inAppReview.isAvailable())) {
        // isAvailable false の時は requested を立てない (Simulator や
        // TestFlight ビルド等、次回試行で OS が判断できる可能性を残す)。
        PetloLogger.instance.i('Review: not available (count=$next)');
        return;
      }
      PetloLogger.instance.i('Review: requesting at count=$next');
      await inAppReview.requestReview();
      await prefs.setBool(_kRequestedKey, true);
    } catch (e, st) {
      PetloLogger.instance
          .w('Review prompt failed', error: e, stackTrace: st);
    }
  }
}
