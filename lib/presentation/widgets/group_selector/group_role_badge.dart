// ============================================================================
// petlo - GroupRoleBadge
// ============================================================================
//
// グループ内の権限を表すバッジ。
//
// rev5.3 §10.11:
//   - Owner: 黒塗り(invert)で最強調
//   - Editor: 標準枠線、文字 fg
//   - Viewer: 薄め(fgMuted)
//   - Local only (Personal): 枠線あり、薄文字
//
// JetBrainsMono uppercase, letter-spaced, very compact (9-10px)
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';

class GroupRoleBadge extends StatelessWidget {
  const GroupRoleBadge.role({
    required MemberPermission permission,
    super.key,
  })  : _kind = _BadgeKind.role,
        _permission = permission;

  /// Personal scope 用 ("Local only")
  const GroupRoleBadge.localOnly({super.key})
      : _kind = _BadgeKind.localOnly,
        _permission = null;

  final _BadgeKind _kind;
  final MemberPermission? _permission;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    switch (_kind) {
      case _BadgeKind.role:
        return _buildRoleBadge(colors);
      case _BadgeKind.localOnly:
        return _buildLocalOnlyBadge(colors, l10n);
    }
  }

  Widget _buildRoleBadge(AppColors colors) {
    final MemberPermission p = _permission!;
    late final String label;
    late final Color bgColor;
    late final Color textColor;
    late final Color borderColor;

    switch (p) {
      case MemberPermission.owner:
        label = 'Owner';
        bgColor = colors.fg;
        textColor = colors.bg;
        borderColor = colors.fg;
      case MemberPermission.editor:
        label = 'Editor';
        bgColor = colors.bg;
        textColor = colors.fg;
        borderColor = colors.line;
      case MemberPermission.viewer:
        label = 'Viewer';
        bgColor = colors.bg;
        textColor = colors.fgMuted;
        borderColor = colors.line;
    }

    return _BadgeShell(
      label: label,
      bgColor: bgColor,
      textColor: textColor,
      borderColor: borderColor,
    );
  }

  Widget _buildLocalOnlyBadge(AppColors colors, AppLocalizations l10n) {
    return _BadgeShell(
      label: l10n.common_local_only,
      bgColor: colors.bg,
      textColor: colors.fgMuted,
      borderColor: colors.line,
    );
  }
}

class _BadgeShell extends StatelessWidget {
  const _BadgeShell({
    required this.label,
    required this.bgColor,
    required this.textColor,
    required this.borderColor,
  });

  final String label;
  final Color bgColor;
  final Color textColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label permission',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontWeight: FontWeight.w500,
            fontSize: 9,
            letterSpacing: 9 * 0.15,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

enum _BadgeKind { role, localOnly }
