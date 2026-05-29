// ============================================================================
// petlo - PetSelectorPill
// ============================================================================
//
// ペットセレクター内の個別ピル。
//
// 4種類:
//   1. PetSelectorPill.pet — 通常のペット
//   2. PetSelectorPill.allPets — "All pets" モード (現在グループ内のホーム画面のみ)
//   3. PetSelectorPill.add — "+" 追加ボタン
//
// アクティブ/非アクティブで:
//   - active: アンダーライン表示、フルカラー
//   - inactive: アンダーラインなし、写真グレースケール、文字fgMuted
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pet_avatar.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';

class PetSelectorPill extends StatelessWidget {
  /// 通常のペット
  const PetSelectorPill.pet({
    required this.name,
    required PetType petType,
    required String breedDisplay,
    required int? petAgeYears,
    required this.isActive,
    required this.onTap,
    this.relativePhotoPath,
    super.key,
  })  : _kind = _PillKind.pet,
        _petType = petType,
        _breedDisplay = breedDisplay,
        _petAgeYears = petAgeYears,
        _petCount = null;

  /// "All pets" モード
  const PetSelectorPill.allPets({
    required int petCount,
    required this.isActive,
    required this.onTap,
    super.key,
  })  : _kind = _PillKind.allPets,
        name = 'All pets',
        relativePhotoPath = null,
        _petType = null,
        _breedDisplay = null,
        _petAgeYears = null,
        _petCount = petCount;

  /// "+" 追加ボタン
  const PetSelectorPill.add({
    required this.onTap,
    super.key,
  })  : _kind = _PillKind.add,
        name = 'Add',
        isActive = false,
        relativePhotoPath = null,
        _petType = null,
        _breedDisplay = null,
        _petAgeYears = null,
        _petCount = null;

  final _PillKind _kind;
  final String name;
  final String? relativePhotoPath;
  final bool isActive;
  final VoidCallback onTap;

  // pet固有
  final PetType? _petType;
  final String? _breedDisplay;
  final int? _petAgeYears;

  // allPets固有
  final int? _petCount;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String label = _semanticsLabel();

    return Semantics(
      label: label,
      selected: isActive,
      button: true,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: colors.bgSoft,
        child: AnimatedContainer(
          duration: AppDurations.petSwitch,
          curve: AppDurations.standardCurve,
          // build 50: padding を 14/12 → 10/8 に縮める。petSelectorHeight=56
          // の中に「avatar 28 + padding 26 + active underline 2 = 56」が
          // ぴったり収まる設計だったが、Fraunces italic 16 の line box が
          // 実描画で数 px 上回ることがあり 3px overflow していた
          // (iPhone 16 Pro Max / iPad Pro 13-inch 双方で再現)。
          // 上下に 7-8px の headroom を確保することで font 描画ぶれを吸収。
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? colors.fg : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildAvatar(colors),
              const SizedBox(width: 10),
              _buildMeta(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(AppColors colors) {
    switch (_kind) {
      case _PillKind.pet:
        return PetAvatar(
          size: AppDimensions.avatarSelector,
          relativePhotoPath: relativePhotoPath,
          fallbackInitial: name.characters.firstOrNull,
          borderColor: isActive ? colors.fg : colors.line,
          grayscale: !isActive,
        );

      case _PillKind.allPets:
        return Container(
          width: AppDimensions.avatarSelector,
          height: AppDimensions.avatarSelector,
          decoration: BoxDecoration(
            color: isActive ? colors.fg : colors.fgMuted,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            'All',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: colors.bg,
            ),
          ),
        );

      case _PillKind.add:
        return Container(
          width: AppDimensions.avatarSelector,
          height: AppDimensions.avatarSelector,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.fgFaint, width: 1, style: BorderStyle.solid),
          ),
          alignment: Alignment.center,
          child: Text(
            '+',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w400,
              fontSize: 18,
              color: colors.fgFaint,
            ),
          ),
        );
    }
  }

  Widget _buildMeta(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final Color nameColor = isActive
        ? colors.fg
        : (_kind == _PillKind.add ? colors.fgFaint : colors.fgMuted);
    final Color subColor =
        isActive ? colors.fgMuted : colors.fgFaint;

    final TextStyle nameStyle = _kind == _PillKind.add
        ? typo.metaSmall.copyWith(color: nameColor)
        : TextStyle(
            fontFamily: 'Fraunces',
            fontStyle: FontStyle.italic,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
            fontSize: 16,
            height: 1.0,
            color: nameColor,
          );

    final String? subText = _subText();

    // Add ピルの表示名は l10n 経由(const 引数の 'Add' を上書き)
    final String displayName = _kind == _PillKind.add
        ? AppLocalizations.of(context).pet_selector_add
        : name;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(displayName, style: nameStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (subText != null) ...<Widget>[
          const SizedBox(height: 1),
          Text(
            subText,
            style: typo.metaSmall.copyWith(color: subColor),
            maxLines: 1,
          ),
        ],
      ],
    );
  }

  String? _subText() {
    switch (_kind) {
      case _PillKind.pet:
        // 例: "柴犬 · 4Y"
        final List<String> parts = <String>[
          if (_breedDisplay != null && _breedDisplay!.isNotEmpty) _breedDisplay!,
          if (_petAgeYears != null) '${_petAgeYears}Y',
        ];
        if (parts.isEmpty) return null;
        return parts.join(' · ');

      case _PillKind.allPets:
        return '${_petCount ?? 0} pets';

      case _PillKind.add:
        return null;
    }
  }

  String _semanticsLabel() {
    switch (_kind) {
      case _PillKind.pet:
        final String state = isActive ? 'selected' : 'not selected';
        final String? sub = _subText();
        return sub == null
            ? '$name, $state. Double tap to switch.'
            : '$name, $sub, $state. Double tap to switch.';
      case _PillKind.allPets:
        final String state = isActive ? 'selected' : 'not selected';
        return 'All pets view, ${_petCount ?? 0} pets, $state. Double tap to view all.';
      case _PillKind.add:
        return 'Add a new pet';
    }
  }
}

enum _PillKind { pet, allPets, add }
