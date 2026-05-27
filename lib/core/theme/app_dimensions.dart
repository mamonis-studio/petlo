// ============================================================================
// petlo - Dimension Tokens
// ============================================================================
//
// rev5.5仕様§4とモックで確定したサイズ・余白の定数。
// マジックナンバーをコードに散らさないため一箇所に集約。
//
// 命名規則:
//   - 余白: paddingX, gapX (例: paddingPage, gapMedium)
//   - サイズ: sizeX, dimensionX
//   - 角丸: radiusX
//   - ストローク: strokeX
//
// ============================================================================


abstract final class AppDimensions {
  AppDimensions._();

  // ===== 余白 =====
  /// 画面の左右パディング (28px)
  static const double paddingPage = 28;

  /// セクション内の縦余白 (24-28px)
  static const double paddingSection = 24;

  /// 行アイテムの縦余白 (18px)
  static const double paddingRow = 18;

  /// 細かい要素の余白 (12-14px)
  static const double paddingCompact = 14;

  /// 最小余白 (8px)
  static const double paddingTight = 8;

  // ===== ギャップ (要素間スペース) =====
  static const double gapTight = 4;
  static const double gapSmall = 8;
  static const double gapMedium = 12;
  static const double gapLarge = 16;
  static const double gapXLarge = 24;

  // ===== コンポーネントサイズ =====
  /// アイコンボタンのサイズ (28px)
  static const double iconBtnSize = 28;

  /// アイコンサイズ標準 (20-22px)
  static const double iconStandard = 22;

  /// アイコンサイズ小 (14-16px)
  static const double iconSmall = 16;

  /// アイコンサイズ最小 (10-12px)
  static const double iconTiny = 12;

  /// タブバーアイコンサイズ
  static const double iconTabBar = 20;

  /// ペットセレクターのアバター (28px)
  static const double avatarSelector = 28;

  /// ヒーローのアバター (96px)
  static const double avatarHero = 96;

  /// メモリアル画面のアバター (140px)
  static const double avatarMemorial = 140;

  /// メンバー一覧のアバター (36px)
  static const double avatarMember = 36;

  /// ペットサマリカードのアバター (48px)
  static const double avatarPetSummary = 48;

  // ===== ストローク =====
  /// 線画アイコンのストローク幅 (1.4px)
  /// rev5.3で確定。雑誌的な繊細さを保つ。
  static const double strokeIcon = 1.4;

  /// 標準罫線
  static const double strokeLine = 1.0;

  /// 強調罫線 (アンダーライン等)
  static const double strokeAccent = 2.0;

  // ===== 角丸 =====
  /// 角丸ゼロが基本。雑誌的な四角形を維持。
  static const double radiusNone = 0;

  /// やわらか四角(IoSライク、まれに使用)
  static const double radiusSubtle = 4;

  /// 円形 (写真、アバター用) - infinityで指定
  static double get radiusCircle => 9999;

  // ===== 画面ブレークポイント (rev5.3 iPad対応) =====
  /// iPad縦・横の境界 (600px以上は2カラム)
  static const double breakpointTablet = 600;

  /// iPad横でさらに余白拡大
  static const double breakpointTabletLarge = 900;

  // ===== タップ最小サイズ (アクセシビリティ) =====
  /// iOS HIG / Material 共通の最小タップサイズ (48dp)
  static const double minTapTarget = 48;

  // ===== ステータスバー周辺 =====
  /// ブランドバーの高さ (slim)
  static const double brandBarHeight = 36;

  /// グループセレクターの高さ
  static const double groupSelectorHeight = 48;

  /// ペットセレクターの高さ
  static const double petSelectorHeight = 56;

  /// タブバー本体の高さ (excluding bottom safe area)
  static const double tabBarHeight = 64;

  // ===== Scaffold body insets (3階層トップバー考慮) =====
  /// トップバー全体の高さ (status除く):
  /// brand + group + pet = 36 + 48 + 56 = 140px
  static const double topBarTotalHeight = 140;

  // ===== グラフ =====
  /// ホームのスパークライン高さ
  static const double sparklineHeight = 48;

  /// 健康タブの大グラフ高さ
  static const double chartLargeHeight = 120;
}
