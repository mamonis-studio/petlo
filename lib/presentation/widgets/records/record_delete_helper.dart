// ============================================================================
// petlo - RecordDeleteHelper
// ============================================================================
//
// 各 record 編集画面で使う共通の削除フロー:
//   - 確認ダイアログ表示
//   - softDelete 実行
//   - 結果に応じて SnackBar + Navigator.pop
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';

class RecordDeleteHelper {
  RecordDeleteHelper._();

  /// 確認ダイアログを表示し、ユーザーが「削除」を選んだら true。
  static Future<bool> confirm(BuildContext context) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final bool? r = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) {
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          title: Text(
            l10n.common_delete_confirm,
            style: typo.bodyLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          content: Text(
            l10n.common_delete_confirm_message,
            style: typo.bodyMedium.copyWith(color: colors.fgMuted),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: Text(
                l10n.common_cancel,
                style: typo.bodyMedium.copyWith(color: colors.fgMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: Text(
                l10n.common_delete,
                style: typo.bodyMedium.copyWith(
                  color: colors.accentDanger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
    return r ?? false;
  }
}
