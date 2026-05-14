// ============================================================================
// petlo - PetloTabBar
// ============================================================================
//
// ボトムナビゲーションバー。5タブ。
//
// デザイン:
//   - 上部に 1px ライン
//   - bg は colors.bg、選択中は fg(黒)、未選択は fgFaint
//   - アイコンは線画 1.5px stroke (CustomPaint)
//   - ラベルは JetBrainsMono 9pt UPPER + letter-spacing
//   - 選択中はラベル太字
//   - 各タブ高さ 56dp + SafeArea
//   - rev3 §4.7 タップ領域 48dp 以上確保
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/tab_provider.dart';

class PetloTabBar extends StatelessWidget {
  const PetloTabBar({
    required this.currentTab,
    required this.onTabSelected,
    super.key,
  });

  final AppTab currentTab;
  final ValueChanged<AppTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(
          top: BorderSide(color: colors.line, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              for (final AppTab tab in AppTab.values)
                Expanded(
                  child: _TabItem(
                    tab: tab,
                    isSelected: currentTab == tab,
                    onTap: () => onTabSelected(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  final AppTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color color = isSelected ? colors.fg : colors.fgFaint;

    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = switch (tab) {
      AppTab.home => l10n.tab_home,
      AppTab.life => l10n.tab_life,
      AppTab.health => l10n.tab_health,
      AppTab.plans => l10n.tab_plans,
      AppTab.ai => l10n.tab_ai,
    };

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: colors.bgSoft,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(
                painter: _TabIconPainter(tab: tab, color: color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                color: color,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 線画アイコン (CustomPainter で 1.4px stroke 統一)
// ============================================================================
class _TabIconPainter extends CustomPainter {
  _TabIconPainter({required this.tab, required this.color});

  final AppTab tab;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double w = size.width;
    final double h = size.height;

    switch (tab) {
      case AppTab.home:
        // 屋根+本体
        final Path p = Path()
          ..moveTo(w * 0.15, h * 0.55)
          ..lineTo(w * 0.5, h * 0.2)
          ..lineTo(w * 0.85, h * 0.55)
          ..moveTo(w * 0.25, h * 0.5)
          ..lineTo(w * 0.25, h * 0.85)
          ..lineTo(w * 0.75, h * 0.85)
          ..lineTo(w * 0.75, h * 0.5);
        canvas.drawPath(p, stroke);
        // ドア
        canvas.drawRect(
          Rect.fromLTWH(w * 0.42, h * 0.6, w * 0.16, h * 0.25),
          stroke,
        );

      case AppTab.life:
        // 葉っぱ + 茎(日常・暮らしのアイコン)
        final Path leaf = Path()
          ..moveTo(w * 0.5, h * 0.85)
          ..quadraticBezierTo(w * 0.15, h * 0.6, w * 0.3, h * 0.2)
          ..quadraticBezierTo(w * 0.7, h * 0.3, w * 0.5, h * 0.85);
        canvas.drawPath(leaf, stroke);
        // 葉脈
        canvas.drawLine(
          Offset(w * 0.5, h * 0.85),
          Offset(w * 0.42, h * 0.4),
          stroke,
        );

      case AppTab.health:
        // ハート(やや幾何学的、医療/健康)
        final Path heart = Path()
          ..moveTo(w * 0.5, h * 0.85)
          ..cubicTo(
            w * 0.05, h * 0.55,
            w * 0.15, h * 0.15,
            w * 0.5, h * 0.45,
          )
          ..cubicTo(
            w * 0.85, h * 0.15,
            w * 0.95, h * 0.55,
            w * 0.5, h * 0.85,
          );
        canvas.drawPath(heart, stroke);

      case AppTab.plans:
        // カレンダー枠
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.18, h * 0.25, w * 0.64, h * 0.6),
            const Radius.circular(2),
          ),
          stroke,
        );
        // 上のリング2つ
        canvas.drawLine(
          Offset(w * 0.32, h * 0.18),
          Offset(w * 0.32, h * 0.32),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.68, h * 0.18),
          Offset(w * 0.68, h * 0.32),
          stroke,
        );
        // 横線
        canvas.drawLine(
          Offset(w * 0.18, h * 0.45),
          Offset(w * 0.82, h * 0.45),
          stroke,
        );

      case AppTab.ai:
        // チャットバブル(角丸長方形 + 三角の尾)
        final RRect bubble = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.18, h * 0.2, w * 0.64, h * 0.5),
          const Radius.circular(4),
        );
        canvas.drawRRect(bubble, stroke);
        // バブルの尾
        final Path tail = Path()
          ..moveTo(w * 0.36, h * 0.7)
          ..lineTo(w * 0.34, h * 0.85)
          ..lineTo(w * 0.5, h * 0.7);
        canvas.drawPath(tail, stroke);
        // 中の3ドット(thinking 風)
        final Paint dot = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(w * 0.36, h * 0.45), 1.4, dot);
        canvas.drawCircle(Offset(w * 0.5, h * 0.45), 1.4, dot);
        canvas.drawCircle(Offset(w * 0.64, h * 0.45), 1.4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _TabIconPainter old) =>
      old.tab != tab || old.color != color;
}
