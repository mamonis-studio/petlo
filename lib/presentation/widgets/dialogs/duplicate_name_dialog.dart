// ============================================================================
// petlo - DuplicateNameDialog
// ============================================================================
//
// rev5.5 §4.17 同名ペット警告ダイアログ。
//
// 想定シーン:
//   - グループに既に「Taro」がいる
//   - ユーザーが新規登録で「Taro」と入力
//   - Save押下時にこのダイアログを表示
//
// メッセージ:
//   "This group already has a pet named "Taro".
//    You'll have two pets with the same name.
//    They will be treated as separate pets."
//
// ボタン:
//   - "Got it, continue" — そのまま登録続行
//   - "Cancel" — 戻って名前変更
//
// rev5.5: v1.0では「2匹を同一ペットに統合」機能はない、ただ警告して進む。
// (将来的にv1.1で統合UIを作る、22項目のID置換チェックリスト参照)
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// 同名ペット警告ダイアログを表示。
///
/// 戻り値:
///   - true: ユーザーが続行を選択 → 登録を続けて
///   - false / null: キャンセル → 登録を中断
Future<bool?> showDuplicateNameDialog({
  required BuildContext context,
  required String petName,
  required String groupDisplayName,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => _DuplicateNameDialog(
      petName: petName,
      groupDisplayName: groupDisplayName,
    ),
  );
}

class _DuplicateNameDialog extends StatelessWidget {
  const _DuplicateNameDialog({
    required this.petName,
    required this.groupDisplayName,
  });

  final String petName;
  final String groupDisplayName;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return Dialog(
      backgroundColor: colors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Eyebrow
            Text(
              'NAME CONFLICT',
              style: typo.metaSmall.copyWith(color: colors.accentWarn),
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              'Two pets, same name?',
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontStyle: FontStyle.italic,
                fontSize: 28,
                height: 1.05,
                letterSpacing: -28 * 0.03,
                color: colors.fg,
              ),
            ),
            const SizedBox(height: 16),

            // Body
            Text(
              '$groupDisplayName already has a pet named "$petName".',
              style: typo.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'You can keep both. They\'ll be treated as separate pets — separate records, separate everything.',
              style: typo.bodyMedium.copyWith(color: colors.fgMuted),
            ),
            const SizedBox(height: 28),

            // Buttons
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.line),
                      foregroundColor: colors.fg,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      'CANCEL',
                      style: typo.button.copyWith(color: colors.fg),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.fg,
                      foregroundColor: colors.bg,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      'GOT IT, CONTINUE',
                      style: typo.button.copyWith(color: colors.bg),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
