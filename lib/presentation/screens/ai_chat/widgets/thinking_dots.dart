// ============================================================================
// petlo - ThinkingDots
// ============================================================================
//
// "thinking · · ·" のドットアニメ。AI応答待ちで表示。
//
// rev5.5 F-23b: AI応答中ドットアニメ
//
// 仕様:
//   - 3つのドットを順番に明滅させる
//   - 各ドット 600ms 周期で淡く→濃く→淡く
//   - 100ms ずつ位相をずらす
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class ThinkingDots extends StatefulWidget {
  const ThinkingDots({this.label = 'thinking', super.key});

  final String label;

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              widget.label,
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontStyle: FontStyle.italic,
                fontSize: 16,
                color: colors.fgMuted,
              ),
            ),
            const SizedBox(width: 6),
            for (int i = 0; i < 3; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 4),
              _Dot(
                phase: (_ctrl.value + i * 0.15) % 1.0,
                color: colors.fgMuted,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.phase, required this.color});

  final double phase; // 0.0 - 1.0
  final Color color;

  @override
  Widget build(BuildContext context) {
    // sin で滑らかに 0.2 → 1.0 → 0.2
    // phase=0 → 0.2 (淡), 0.5 → 1.0 (濃), 1.0 → 0.2 (淡)
    final double t = phase * 2 - 1; // -1 ~ 1
    final double bell = 1 - (t * t); // 0 ~ 1
    final double opacity = 0.2 + bell * 0.8;

    return Opacity(
      opacity: opacity,
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
