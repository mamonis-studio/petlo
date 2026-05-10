// ============================================================================
// petlo - Cancel Feedback Table
// ============================================================================
//
// Pro解約時のアンケート回答 (rev5.1: F-53)。
// ローカルに保存後、サーバーへ送信。送信成功で論理削除。
//
// ============================================================================

import 'package:drift/drift.dart';

@DataClassName('CancelFeedbackEntity')
class CancelFeedback extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 選択された理由 (チェックボックス複数選択を JSON 配列で保存)
  /// 例: ["price", "not_using", "missing_feature"]
  TextColumn get reasons => text()();

  /// 自由記述 (任意)
  TextColumn get comment => text().nullable()();

  /// 解約日時 (UTC msec)
  IntColumn get cancelledAt => integer()();

  /// サーバー送信済みか
  BoolColumn get sentToServer => boolean().withDefault(const Constant(false))();

  IntColumn get createdAt => integer()();
}
