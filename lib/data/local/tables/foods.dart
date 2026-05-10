// ============================================================================
// petlo - Foods Master Table
// ============================================================================
//
// 食事銘柄マスタ。
// ユーザーが過去に登録した銘柄を保存し、直近3銘柄ボタンで素早く再選択できるように。
//
// 設計:
//   - 完全にローカル (共有グループ間で共有しない、各ユーザー個別)
//   - lastUsedAt の降順で「直近3銘柄」を取得
//
// ============================================================================

import 'package:drift/drift.dart';

@DataClassName('FoodEntity')
class Foods extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 銘柄名
  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// メーカー (任意)
  TextColumn get brand => text().nullable()();

  /// デフォルト量 (グラム、よく与える量、入力補助用)
  IntColumn get defaultAmountG => integer().nullable()();

  /// 最終使用日時 (UTC msec) — 直近3銘柄取得用
  IntColumn get lastUsedAt => integer()();

  /// 使用回数 (人気順サブソート用)
  IntColumn get useCount => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();
}
