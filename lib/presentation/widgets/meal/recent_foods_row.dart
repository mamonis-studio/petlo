// ============================================================================
// petlo - RecentFoodsRow
// ============================================================================
//
// rev3 F-01: 直近3銘柄ボタン。食事記録画面の上部に表示。
//
// 構造:
//   ┌─────────────────────────────────┐
//   │  RECENT                         │  ← eyebrow
//   ├─────────────────────────────────┤
//   │ [Royal Canin] [Hill's] [Other]  │  ← chips、最大3個
//   └─────────────────────────────────┘
//
// 選択された銘柄は親側のフィールドに自動入力 (foodId + 名前 + 量)
// 銘柄なしの初回時は何も表示しない (helper hint だけ)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../data/local/app_database.dart';
import '../../providers/foods_providers.dart';

class RecentFoodsRow extends ConsumerWidget {
  const RecentFoodsRow({
    required this.selectedFoodId,
    required this.onFoodSelected,
    super.key,
  });

  /// 現在選択中の foodId (ハイライト表示用)
  final int? selectedFoodId;

  /// チップタップ時のコールバック
  /// 親はこのFoodEntityを使ってフィールドを埋める
  final ValueChanged<FoodEntity> onFoodSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FoodEntity>> recentAsync =
        ref.watch(recentFoodsProvider);

    return recentAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (Object e, StackTrace st) => const SizedBox.shrink(),
      data: (List<FoodEntity> foods) {
        if (foods.isEmpty) {
          // 初回: 何も表示しない (フリー入力で銘柄を作ると次から表示される)
          return const SizedBox.shrink();
        }
        return _Row(
          foods: foods,
          selectedFoodId: selectedFoodId,
          onFoodSelected: onFoodSelected,
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.foods,
    required this.selectedFoodId,
    required this.onFoodSelected,
  });

  final List<FoodEntity> foods;
  final int? selectedFoodId;
  final ValueChanged<FoodEntity> onFoodSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(AppLocalizations.of(context).common_recent),
        const SizedBox(height: AppDimensions.gapSmall),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final FoodEntity f in foods)
              _FoodChip(
                food: f,
                isSelected: selectedFoodId == f.id,
                onTap: () => onFoodSelected(f),
              ),
          ],
        ),
      ],
    );
  }
}

class _FoodChip extends StatelessWidget {
  const _FoodChip({
    required this.food,
    required this.isSelected,
    required this.onTap,
  });

  final FoodEntity food;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final String detail = <String>[
      if (food.brand != null && food.brand!.isNotEmpty) food.brand!,
      if (food.defaultAmountG != null) '${food.defaultAmountG}g',
    ].join(' · ');

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Recent food: ${food.name}${detail.isNotEmpty ? ", $detail" : ""}',
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.fg : colors.bg,
            border: Border.all(color: colors.fg, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                food.name,
                style: typo.bodyMedium.copyWith(
                  color: isSelected ? colors.bg : colors.fg,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (detail.isNotEmpty) ...<Widget>[
                const SizedBox(height: 1),
                Text(
                  detail,
                  style: typo.metaSmall.copyWith(
                    color: isSelected ? colors.bg.withValues(alpha: 0.7) : colors.fgMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
