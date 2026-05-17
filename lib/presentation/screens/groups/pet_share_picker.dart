// ============================================================================
// petlo - Pet Share Picker (build 20)
// ============================================================================
//
// 「既存ペットをこのグループに共有する」UI。
//
// 表示:
//   - personal scope の active なペット一覧 (お別れ済み・削除済みは除外)
//   - すでにこのグループ内のペットは出さない (移動先 = 現在のグループ)
//   - 各行をタップ → 確認ダイアログ → PetsRepository.movePetToGroup
//
// 呼び出し場所:
//   - ホームの empty state (グループスコープでペット 0 匹のとき)
//   - 各タブの追加導線 (後追い拡張も可)
//
// 設計判断:
//   - bottom sheet で軽量に出す (新画面 push にしない)
//   - 単発タップで即移動はせず、確認ダイアログを挟む
//   - 移動後は scaffoldMessenger で結果通知 (UI は drift stream で自動更新)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../providers/pets_providers.dart';
import '../../providers/scope_providers.dart';

class PetSharePicker {
  PetSharePicker._();

  /// グループのホームから呼ぶ。
  /// targetGroupId = 現在のグループ remoteId。
  static Future<void> show(
    BuildContext context, {
    required String targetGroupId,
  }) {
    if (targetGroupId == kPersonalGroupId) {
      // personal でこの picker は使わない (= 共有解除 picker を別途用意する)
      return Future<void>.value();
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
      ),
      builder: (_) => _PetSharePickerSheet(targetGroupId: targetGroupId),
    );
  }
}

class _PetSharePickerSheet extends ConsumerWidget {
  const _PetSharePickerSheet({required this.targetGroupId});

  final String targetGroupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    // personal scope の active ペットを 1 回だけ stream で読み取る。
    final AsyncValue<List<PetEntity>> personalPets = ref.watch(
      petsInScopeProvider(kPersonalGroupId),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ハンドル
            Center(
              child: Container(
                width: 36,
                height: 3,
                margin: const EdgeInsets.only(bottom: 16),
                color: colors.line,
              ),
            ),
            const SectionLabel(
              'Share existing pet',
              size: EyebrowSize.large,
              padding: EdgeInsets.fromLTRB(0, 0, 0, 12),
            ),
            Text(
              'Personal で記録していたペットをグループへ移動します。\n'
              '記録もまとめて共有され、メンバー全員から見られるようになります。',
              style: typo.bodySmall.copyWith(color: colors.fgMuted, height: 1.6),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: personalPets.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
                error: (Object e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'ペット一覧の取得に失敗しました\n$e',
                    style: typo.bodySmall.copyWith(color: colors.accentDanger),
                  ),
                ),
                data: (List<PetEntity> list) {
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Personal に共有できるペットがいません。',
                        style: typo.bodyMedium
                            .copyWith(color: colors.fgMuted, height: 1.6),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: colors.line, height: 1),
                    itemBuilder: (BuildContext _, int i) {
                      return _PetRow(
                        pet: list[i],
                        onTap: () => _onPick(context, ref, list[i]),
                        colors: colors,
                        typo: typo,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPick(
      BuildContext context, WidgetRef ref, PetEntity pet) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('このグループへ共有'),
        content: Text(
          '${pet.name} をこのグループに共有しますか?\n\n'
          '記録(食事/排泄/体重ほか)もまとめて移動し、'
          'メンバー全員から閲覧できるようになります。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('共有する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    try {
      final int n = await ref
          .read(petsRepositoryProvider)
          .movePetToGroup(pet.id, targetGroupId);
      navigator.pop(); // close sheet
      messenger.showSnackBar(
        SnackBar(
          content: Text('${pet.name} を共有しました (${n} 件のレコードを移動)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('共有に失敗しました: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _PetRow extends StatelessWidget {
  const _PetRow({
    required this.pet,
    required this.onTap,
    required this.colors,
    required this.typo,
  });

  final PetEntity pet;
  final VoidCallback onTap;
  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    pet.name,
                    style: typo.bodyLarge.copyWith(color: colors.fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pet.breed ?? (pet.type.name == 'dog' ? '犬' : '猫'),
                    style: typo.bodySmall
                        .copyWith(color: colors.fgMuted, height: 1.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.fgMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
