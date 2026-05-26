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
import '../../../l10n/generated/app_localizations.dart';
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
    final AppLocalizations l10n = AppLocalizations.of(context);

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
            SectionLabel(
              l10n.pet_share_picker_title,
              size: EyebrowSize.large,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
            ),
            Text(
              l10n.pet_share_picker_body,
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
                    l10n.pet_share_picker_load_error(e.toString()),
                    style: typo.bodySmall.copyWith(color: colors.accentDanger),
                  ),
                ),
                data: (List<PetEntity> list) {
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        l10n.pet_share_picker_empty,
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
            AppLocalizations.of(dialogContext).pet_share_picker_confirm_title),
        content: Text(AppLocalizations.of(dialogContext)
            .pet_share_picker_confirm_body(pet.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(dialogContext).common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(dialogContext)
                .pet_share_picker_confirm_action),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    try {
      // ignore: deprecated_member_use_from_same_package
      // build 45: movePetToGroup deprecated. G4b で multi-select 共有 UI に
      // 改修すると同時に PetScopesRepository.addPetScope 経由に切替予定。
      final int n = await ref
          .read(petsRepositoryProvider)
          .movePetToGroup(pet.id, targetGroupId);
      navigator.pop(); // close sheet
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.pet_share_picker_success(pet.name, n)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.pet_share_picker_failure(e.toString())),
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
    final AppLocalizations l10n = AppLocalizations.of(context);
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
                    pet.breed ??
                        (pet.type.name == 'dog'
                            ? l10n.pet_species_dog_short
                            : l10n.pet_species_cat_short),
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
