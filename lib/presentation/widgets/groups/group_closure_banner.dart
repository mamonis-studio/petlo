// ============================================================================
// petlo - Group Closure Banner (F-80)
// ============================================================================
//
// オーナーが Pro を解約した時、グループ全メンバーに表示する警告バナー。
//
// rev5.5 §4.15:
//   - 0-30日(pendingDeletion): 警告バナー、機能フル動作、CTA = Owner has to renew
//   - 30-60日(frozen): 閲覧のみ、強い警告、データエクスポート推奨
//   - 60-90日(deletionScheduled): 最終警告
//   - 90日後: 物理削除(サーバー側)
//
// このバナーは GroupDetailScreen と Home/Life/Health/Plans タブの上部に表示する。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';

class GroupClosureBanner extends StatelessWidget {
  const GroupClosureBanner({required this.group, super.key});

  final GroupEntity group;

  /// 表示すべきか
  static bool shouldShow(GroupEntity g) {
    return g.status == GroupStatus.pendingDeletion ||
        g.status == GroupStatus.frozen ||
        g.status == GroupStatus.deletionScheduled;
  }

  /// 解約からの経過日数
  int? get _daysSinceClosure {
    if (group.pendingDeletionAt == null) return null;
    final DateTime closureAt =
        DateTime.fromMillisecondsSinceEpoch(group.pendingDeletionAt!);
    return DateTime.now().difference(closureAt).inDays;
  }

  /// 削除までの残り日数 (90日カウントダウン)
  int? get _daysUntilDeletion {
    final int? since = _daysSinceClosure;
    if (since == null) return null;
    final int remaining = 90 - since;
    return remaining < 0 ? 0 : remaining;
  }

  /// 削除予定日 (formatted)
  String? _deletionDateLabel(String localeTag) {
    if (group.pendingDeletionAt == null) return null;
    final DateTime closureAt =
        DateTime.fromMillisecondsSinceEpoch(group.pendingDeletionAt!);
    final DateTime deletion = closureAt.add(const Duration(days: 90));
    return formatFullDate(deletion, localeTag);
  }

  ({String header, String title, String body, Color color})
      _statusContent(AppColors colors, String localeTag,
          AppLocalizations l10n) {
    final int? days = _daysUntilDeletion;
    final String dateLabel =
        _deletionDateLabel(localeTag) ?? l10n.group_closure_date_fallback;

    return switch (group.status) {
      GroupStatus.pendingDeletion => (
          header: 'GROUP CLOSING',
          title: days == null
              ? '${group.name} will close soon.'
              : '${group.name} will close\nin $days days.',
          body: l10n.group_closure_pending_body(dateLabel),
          color: colors.accentWarn,
        ),
      GroupStatus.frozen => (
          header: 'GROUP FROZEN',
          title: '${group.name} is frozen.',
          body: l10n.group_closure_frozen_body(dateLabel),
          color: colors.accentDanger,
        ),
      GroupStatus.deletionScheduled => (
          header: 'FINAL WARNING',
          title: '${group.name} will be\ndeleted soon.',
          body: l10n.group_closure_final_body(dateLabel),
          color: colors.accentDanger,
        ),
      // shouldShow で除外済みなので到達しないが、防御的に
      GroupStatus.active => (
          header: '',
          title: '',
          body: '',
          color: colors.fg,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldShow(group)) return const SizedBox.shrink();
    final AppColors colors = AppColors.of(context);
    final content = _statusContent(
      colors,
      Localizations.localeOf(context).toLanguageTag(),
      AppLocalizations.of(context),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border.all(color: content.color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ヘッダー
          Row(
            children: <Widget>[
              CustomPaint(
                size: const Size(14, 14),
                painter: _WarningPainter(color: content.color),
              ),
              const SizedBox(width: 8),
              Text(
                content.header,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 9,
                  letterSpacing: 9 * 0.2,
                  color: content.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // メイン Fraunces italic
          Text(
            content.title,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 24,
              letterSpacing: -24 * 0.03,
              height: 1.15,
              color: colors.fg,
            ),
          ),
          const SizedBox(height: 12),

          // 説明文
          Text(
            content.body,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              color: colors.fgMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// _WarningPainter — 線画の警告アイコン (絵文字回避)
// ============================================================================
class _WarningPainter extends CustomPainter {
  _WarningPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 三角形
    final Path triangle = Path()
      ..moveTo(size.width * 0.5, size.height * 0.1)
      ..lineTo(size.width * 0.95, size.height * 0.9)
      ..lineTo(size.width * 0.05, size.height * 0.9)
      ..close();
    canvas.drawPath(triangle, p);

    // 中央の縦線
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.4),
      Offset(size.width * 0.5, size.height * 0.65),
      p,
    );

    // ドット
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.78),
      0.8,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _WarningPainter old) =>
      old.color != color;
}
