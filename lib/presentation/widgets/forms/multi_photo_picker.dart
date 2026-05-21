// ============================================================================
// petlo - MultiPhotoPicker
// ============================================================================
//
// 複数写真を選択する部品。通院記録の検査結果・レシート等に使用。
//
// UI:
//   - 既存の写真をサムネイル横並び表示
//   - 各サムネイルに削除(×)ボタン
//   - 末尾に「+」追加ボタン (枚数上限まで活性)
//   - タップで「カメラ/ライブラリ」シート → image_picker
//
// 戻り値:
//   - List<File> (新規選択分は一時ファイル)
//   - List<String?> (各位置の保存済み相対パス、新規分は null)
//
// 親側で「Save時に File があれば PhotoStorage.saveVisitPhoto(index)」する
//
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/pet_avatar.dart';
import '../../../l10n/generated/app_localizations.dart';

/// 1枚分のスロット情報
class PhotoSlot {
  const PhotoSlot({this.file, this.savedRelativePath});

  /// 新規選択した一時ファイル
  final File? file;

  /// 保存済みの相対パス
  final String? savedRelativePath;

  bool get isEmpty => file == null && savedRelativePath == null;
  bool get isNew => file != null && savedRelativePath == null;
  bool get isExisting => savedRelativePath != null;
}

class MultiPhotoPicker extends StatelessWidget {
  const MultiPhotoPicker({
    required this.label,
    required this.slots,
    required this.onSlotsChanged,
    this.maxPhotos = 5,
    super.key,
  });

  final String label;
  final List<PhotoSlot> slots;
  final ValueChanged<List<PhotoSlot>> onSlotsChanged;
  final int maxPhotos;

  bool get _atLimit => slots.length >= maxPhotos;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            EyebrowText(label),
            const Spacer(),
            Text(
              '${slots.length} / $maxPhotos',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 9,
                letterSpacing: 9 * 0.15,
                color: colors.fgMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.gapSmall),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < slots.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PhotoTile(
                    slot: slots[i],
                    onRemove: () => _removeAt(i),
                  ),
                ),
              if (!_atLimit)
                _AddTile(
                  onTap: () => _showPickerSheet(context),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _removeAt(int index) {
    final List<PhotoSlot> next = <PhotoSlot>[
      for (int i = 0; i < slots.length; i++)
        if (i != index) slots[i],
    ];
    onSlotsChanged(next);
  }

  Future<void> _showPickerSheet(BuildContext context) async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => const _PickerSheet(),
    );

    if (source == null) return;

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (picked != null) {
        final List<PhotoSlot> next = <PhotoSlot>[
          ...slots,
          PhotoSlot(file: File(picked.path)),
        ];
        onSlotsChanged(next);
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('Image picker failed', error: e, stackTrace: st);
    }
  }
}

// ============================================================================
// 個別タイル(写真 or 追加ボタン)
// ============================================================================
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.slot, required this.onRemove});

  final PhotoSlot slot;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            border: Border.all(color: colors.fg, width: 1),
          ),
          child: _buildImage(),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: colors.fg,
                shape: BoxShape.circle,
                border: Border.all(color: colors.bg, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.close, size: 14, color: colors.bg),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage() {
    if (slot.file != null) {
      return Image.file(
        slot.file!,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
      );
    }
    if (slot.savedRelativePath != null) {
      // PetAvatar の中身を借りる(同じく相対パス対応)
      return PetAvatar(
        size: 80,
        relativePhotoPath: slot.savedRelativePath,
      );
    }
    return const SizedBox.shrink();
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: colors.fgMuted, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '+',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 28,
                color: colors.fgMuted,
              ),
            ),
            Text(
              'ADD',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 9,
                letterSpacing: 9 * 0.15,
                color: colors.fgMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PickerSheet
// ============================================================================
class _PickerSheet extends StatelessWidget {
  const _PickerSheet();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      color: colors.bg,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 24),
            _SheetRow(
              label: l10n.common_take_photo,
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            Divider(height: 1, color: colors.line),
            _SheetRow(
              label: l10n.common_choose_from_library,
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 16),
            Container(height: 8, color: colors.bgSoft),
            _SheetRow(
              label: l10n.common_cancel,
              muted: true,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 28),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 16,
            color: muted ? colors.fgMuted : colors.fg,
          ),
        ),
      ),
    );
  }
}
