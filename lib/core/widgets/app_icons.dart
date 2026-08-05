// ============================================================================
// petlo - App Icons
// ============================================================================
//
// モック (petlo_mock.html) の SVG アイコンを Flutter の Path で再現。
// すべて 24x24 viewBox、stroke 1.4px、strokeLinecap round、strokeLinejoin round。
//
// 命名: モックの SVG `<symbol id="i-meal">` と1:1で対応。
//
// Path文字列はSVGの 'd' 属性をそのまま使用するために、
// `flutter_svg`相当の小さな簡易パーサ ... ではなく、
// Canvasコマンドに手動変換する。
//
// 簡易のため、よく使う L, M, h, v, q, etc. のみサポート。
// 複雑な曲線は専用関数を作成。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../widgets/line_icon.dart';

abstract final class AppIcons {
  AppIcons._();

  // ===== Tab bar icons =====

  /// 家アイコン (Homeタブ)
  static final LineIconData home = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // M3 11.5 L12 4 L21 11.5 V20 a1 1 0 0 1 -1 1 h-5 v-7 H9 v7 H4 a1 1 0 0 1 -1 -1 z
      final Path path = Path()
        ..moveTo(3, 11.5)
        ..lineTo(12, 4)
        ..lineTo(21, 11.5)
        ..lineTo(21, 20)
        ..arcToPoint(const Offset(20, 21), radius: const Radius.circular(1))
        ..lineTo(15, 21)
        ..lineTo(15, 14)
        ..lineTo(9, 14)
        ..lineTo(9, 21)
        ..lineTo(4, 21)
        ..arcToPoint(const Offset(3, 20), radius: const Radius.circular(1))
        ..close();
      c.drawPath(path, p);
    },
    semanticLabel: 'Home',
  );

  /// 4つのドット顔アイコン (Lifeタブ - 雑多な記録の象徴)
  static final LineIconData life = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // 4 small circles + smile arc
      c.drawCircle(const Offset(6, 7), 2, p);
      c.drawCircle(const Offset(18, 7), 2, p);
      c.drawCircle(const Offset(9, 14), 2, p);
      c.drawCircle(const Offset(15, 14), 2, p);
      // smile: M8 19 c1 -2 2.5 -3 4 -3 s3 1 4 3
      final Path smile = Path()
        ..moveTo(8, 19)
        ..relativeCubicTo(1, -2, 2.5, -3, 4, -3)
        ..relativeCubicTo(0, 0, 3, 1, 4, 3);
      c.drawPath(smile, p);
    },
    semanticLabel: 'Life',
  );

  /// 心拍アイコン (Healthタブ)
  static final LineIconData health = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // M3 12 h4 l2 -7 l4 14 l2 -7 h6
      final Path path = Path()
        ..moveTo(3, 12)
        ..relativeLineTo(4, 0)
        ..relativeLineTo(2, -7)
        ..relativeLineTo(4, 14)
        ..relativeLineTo(2, -7)
        ..relativeLineTo(6, 0);
      c.drawPath(path, p);
    },
    semanticLabel: 'Health',
  );

  /// カレンダーアイコン (Plansタブ)
  static final LineIconData plans = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // rect 4 5 16 16 + 上ライン + 2本のクリップ
      c.drawRect(const Rect.fromLTWH(4, 5, 16, 16), p);
      c.drawLine(const Offset(4, 9), const Offset(20, 9), p);
      c.drawLine(const Offset(9, 3), const Offset(9, 7), p);
      c.drawLine(const Offset(15, 3), const Offset(15, 7), p);
    },
    semanticLabel: 'Plans',
  );

  /// 3点リーダー (Moreタブ)
  static final LineIconData more = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // 塗りつぶしの円3つ。strokeでもOKだが視認性のためfillに切替
      final Paint dotPaint = Paint()
        ..color = p.color
        ..style = PaintingStyle.fill;
      c.drawCircle(const Offset(6, 12), 1, dotPaint);
      c.drawCircle(const Offset(12, 12), 1, dotPaint);
      c.drawCircle(const Offset(18, 12), 1, dotPaint);
    },
    semanticLabel: 'More',
  );

  // ===== Quick log icons =====

  /// ご飯ボウルアイコン
  static final LineIconData meal = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // ボウル: M3 11 h18 l-2 8 H5 z
      final Path bowl = Path()
        ..moveTo(3, 11)
        ..relativeLineTo(18, 0)
        ..relativeLineTo(-2, 8)
        ..lineTo(5, 19)
        ..close();
      c.drawPath(bowl, p);
      // 湯気1: M5 8 c1 -2 2.5 -3 4 -3
      final Path steam1 = Path()
        ..moveTo(5, 8)
        ..relativeCubicTo(1, -2, 2.5, -3, 4, -3);
      c.drawPath(steam1, p);
      // 湯気2: M11 8 c1 -2 2.5 -3 4 -3
      final Path steam2 = Path()
        ..moveTo(11, 8)
        ..relativeCubicTo(1, -2, 2.5, -3, 4, -3);
      c.drawPath(steam2, p);
    },
    semanticLabel: 'Meal',
  );

  /// うんちアイコン
  static final LineIconData stool = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // ウェーブ状のシルエット
      final Path path = Path()
        ..moveTo(7, 18)
        ..relativeCubicTo(-2, 0, -3, -1, -3, -3)
        ..relativeCubicTo(0, -1, 1, -2, 2, -2)
        ..relativeCubicTo(0, -2, 2, -3, 3, -3)
        ..relativeCubicTo(-1, -2, 0, -4, 2, -4)
        ..relativeCubicTo(0, 0, 3, 1, 3, 3)
        ..relativeCubicTo(2, 0, 3, 2, 3, 4)
        ..relativeCubicTo(1, 0, 2, 1, 2, 2)
        ..relativeCubicTo(0, 1, -1, 3, -3, 3)
        ..close();
      c.drawPath(path, p);
    },
    semanticLabel: 'Stool',
  );

  /// しずく (おしっこ)
  static final LineIconData pee = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // M12 3 c-3 5 -5 8 -5 11 a5 5 0 0 0 10 0 c0 -3 -2 -6 -5 -11 z
      final Path path = Path()
        ..moveTo(12, 3)
        ..relativeCubicTo(-3, 5, -5, 8, -5, 11)
        ..arcToPoint(const Offset(17, 14), radius: const Radius.circular(5))
        ..relativeCubicTo(0, -3, -2, -6, -5, -11)
        ..close();
      c.drawPath(path, p);
    },
    semanticLabel: 'Pee',
  );

  /// 嘔吐アイコン
  static final LineIconData vomit = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // 上のカーブ
      final Path top = Path()
        ..moveTo(7, 10)
        ..relativeCubicTo(0, -3, 2, -5, 5, -5)
        ..relativeCubicTo(0, 0, 5, 2, 5, 5);
      c.drawPath(top, p);
      // 下のカーブ
      final Path bottom = Path()
        ..moveTo(7, 10)
        ..relativeLineTo(0, 2)
        ..relativeCubicTo(0, 2, 2, 4, 5, 4)
        ..relativeCubicTo(0, 0, 5, -2, 5, -4)
        ..relativeLineTo(0, -2);
      c.drawPath(bottom, p);
      // ドリップ
      c.drawLine(const Offset(9, 19), const Offset(10, 21), p);
      c.drawLine(const Offset(12, 18), const Offset(13, 21), p);
      c.drawLine(const Offset(15, 19), const Offset(16, 21), p);
    },
    semanticLabel: 'Vomit',
  );

  /// 薬アイコン (カプセル)
  static final LineIconData med = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // 回転30度のカプセル
      c.save();
      c.translate(12, 12);
      c.rotate(-30 * 3.14159 / 180);
      c.translate(-12, -12);

      // カプセル形 rect 4,9,16,6 rx=3
      final RRect capsule = RRect.fromRectAndRadius(
        const Rect.fromLTWH(4, 9, 16, 6),
        const Radius.circular(3),
      );
      c.drawRRect(capsule, p);
      // 中央分割線
      c.drawLine(const Offset(9, 7), const Offset(15, 17), p);

      c.restore();
    },
    semanticLabel: 'Medication',
  );

  /// 盾アイコン (予防 — build 72)
  /// M12 3 L20 6 V12 c0 5 -3.5 8 -8 9 c-4.5 -1 -8 -4 -8 -9 V6 z
  /// 内側にチェックを重ねて「守られている」ことを示す。
  static final LineIconData prevention = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      final Path shield = Path()
        ..moveTo(12, 3)
        ..lineTo(20, 6)
        ..lineTo(20, 12)
        ..relativeCubicTo(0, 5, -3.5, 8, -8, 9)
        ..relativeCubicTo(-4.5, -1, -8, -4, -8, -9)
        ..lineTo(4, 6)
        ..close();
      c.drawPath(shield, p);

      final Path check = Path()
        ..moveTo(9, 12)
        ..lineTo(11.2, 14.2)
        ..lineTo(15.5, 9.8);
      c.drawPath(check, p);
    },
    semanticLabel: 'Prevention',
  );

  // ===== UI icons =====

  /// 検索アイコン
  static final LineIconData search = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      c.drawCircle(const Offset(11, 11), 7, p);
      c.drawLine(const Offset(16, 16), const Offset(21, 21), p);
    },
    semanticLabel: 'Search',
  );

  /// 設定歯車
  static final LineIconData settings = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // 単純化: 中央の円 + 周囲のスラッシュ8本
      c.drawCircle(const Offset(12, 12), 3, p);
      // 8本の放射スラッシュを簡易的に
      for (int i = 0; i < 8; i++) {
        final double angle = i * (3.14159 * 2 / 8);
        c.save();
        c.translate(12, 12);
        c.rotate(angle);
        c.drawLine(const Offset(0, -8), const Offset(0, -6), p);
        c.restore();
      }
    },
    semanticLabel: 'Settings',
  );

  /// 右矢印
  static final LineIconData arrowRight = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      c.drawLine(const Offset(5, 12), const Offset(19, 12), p);
      final Path tip = Path()
        ..moveTo(13, 6)
        ..lineTo(19, 12)
        ..lineTo(13, 18);
      c.drawPath(tip, p);
    },
    semanticLabel: 'Next',
  );

  /// 左シェブロン (戻る、月送り)
  static final LineIconData chevronLeft = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      final Path path = Path()
        ..moveTo(15, 6)
        ..lineTo(9, 12)
        ..lineTo(15, 18);
      c.drawPath(path, p);
    },
    semanticLabel: 'Previous',
  );

  /// 右シェブロン
  static final LineIconData chevronRight = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      final Path path = Path()
        ..moveTo(9, 6)
        ..lineTo(15, 12)
        ..lineTo(9, 18);
      c.drawPath(path, p);
    },
    semanticLabel: 'Next',
  );

  /// 電話アイコン
  static final LineIconData phone = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // 受話器の形
      final Path path = Path()
        ..moveTo(22, 16.92)
        ..relativeLineTo(0, 3)
        ..arcToPoint(const Offset(19.82, 21.92), radius: const Radius.circular(2))
        ..relativeCubicTo(-3, 0, -6.5, -1, -8.63, -3.07)
        ..relativeCubicTo(-2, -2, -4, -4, -6, -6)
        ..relativeCubicTo(-2, -3, -3, -6, -3.07, -8.67)
        ..arcToPoint(const Offset(4.11, 2), radius: const Radius.circular(2))
        ..relativeLineTo(3, 0)
        ..arcToPoint(const Offset(9.11, 3.72), radius: const Radius.circular(2))
        ..relativeCubicTo(0, 1, 0.3, 2, 0.7, 2.81)
        ..arcToPoint(const Offset(9.36, 8.64), radius: const Radius.circular(2))
        ..lineTo(8.09, 9.91)
        ..relativeArcToPoint(const Offset(6, 6), radius: const Radius.circular(16))
        ..relativeLineTo(1.27, -1.27)
        ..arcToPoint(const Offset(17.47, 14.18), radius: const Radius.circular(2))
        ..relativeCubicTo(0.91, 0.4, 1.85, 0.6, 2.81, 0.7)
        ..arcToPoint(const Offset(22, 16.92), radius: const Radius.circular(2));
      c.drawPath(path, p);
    },
    semanticLabel: 'Call',
  );

  /// カメラアイコン
  static final LineIconData camera = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // 本体
      c.drawRect(const Rect.fromLTWH(3, 7, 18, 13), p);
      // フラッシュ部
      final Path flash = Path()
        ..moveTo(9, 7)
        ..lineTo(10.5, 4)
        ..lineTo(13.5, 4)
        ..lineTo(15, 7);
      c.drawPath(flash, p);
      // レンズ
      c.drawCircle(const Offset(12, 13), 3.5, p);
    },
    semanticLabel: 'Camera',
  );

  /// 送信(紙飛行機 - 矢印で代用)
  static final LineIconData send = LineIconData(
    paint: arrowRight.paint, // 同じデザインで流用
    semanticLabel: 'Send',
  );

  /// サムズアップ (フィードバック )
  static final LineIconData thumbUp = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      // 単純化シルエット
      final Path path = Path()
        ..moveTo(7, 22)
        ..lineTo(7, 11)
        ..lineTo(12, 4)
        ..relativeCubicTo(1, 0, 2, 1, 2, 2)
        ..relativeLineTo(0, 5)
        ..relativeLineTo(6, 0)
        ..relativeCubicTo(1, 0, 2, 1, 2, 2)
        ..relativeLineTo(-2, 7)
        ..relativeCubicTo(0, 1, -1, 2, -2, 2)
        ..lineTo(7, 22)
        ..close();
      c.drawPath(path, p);
    },
    semanticLabel: 'Helpful',
  );

  /// サムズダウン
  static final LineIconData thumbDown = LineIconData(
    paint: (Canvas c, Size s, Paint p) {
      final Path path = Path()
        ..moveTo(7, 2)
        ..lineTo(7, 13)
        ..lineTo(12, 20)
        ..relativeCubicTo(1, 0, 2, -1, 2, -2)
        ..relativeLineTo(0, -5)
        ..relativeLineTo(6, 0)
        ..relativeCubicTo(1, 0, 2, -1, 2, -2)
        ..relativeLineTo(-2, -7)
        ..relativeCubicTo(0, -1, -1, -2, -2, -2)
        ..lineTo(7, 2)
        ..close();
      c.drawPath(path, p);
    },
    semanticLabel: 'Not helpful',
  );
}
