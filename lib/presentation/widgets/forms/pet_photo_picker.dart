// ============================================================================
// petlo - PetPhotoPicker
// ============================================================================
//
// ペット写真を選択するウィジェット。
//
// UI:
//   - 写真未選択時: 円形のプレースホルダー (+ アイコン)
//   - 写真選択時: 選択済み写真表示 + 右上に "削除" + "変更" ボタン
//
// 選択方式 (タップ時のシート):
//   - ライブラリから選択
//   - カメラで撮影
//   - キャンセル
//
// 保存先:
//   - 一時ファイル(image_pickerの戻り値)
//   - 親側で savePetProfilePhoto() を呼んで永続化する
//   - このウィジェット自体は「選んだだけ」の状態を返す → onPicked(File?) コールバック
//
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/pet_avatar.dart';

class PetPhotoPicker extends StatelessWidget {
  const PetPhotoPicker({
    required this.label,
    required this.onPicked,
    this.currentPhotoFile,
    this.currentRelativePath,
    this.fallbackInitial,
    super.key,
  });

  final String label;

  /// 写真選択(または削除)時のコールバック
  /// 引数: 選んだローカル一時ファイル (削除なら null)
  final ValueChanged<File?> onPicked;

  /// プレビュー用に現在表示する一時ファイル (新規選択直後のプレビュー)
  final File? currentPhotoFile;

  /// 既存ペットの編集時、保存済み相対パスからプレビュー
  final String? currentRelativePath;

  /// fallback時の文字 (例: "T")
  final String? fallbackInitial;

  bool get _hasAny =>
      currentPhotoFile != null ||
      (currentRelativePath != null && currentRelativePath!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(label),
        const SizedBox(height: AppDimensions.gapMedium),

        Center(
          child: Column(
            children: <Widget>[
              // アバター本体
              GestureDetector(
                onTap: () => _showPickerSheet(context),
                child: _buildAvatar(),
              ),
              const SizedBox(height: AppDimensions.gapMedium),

              // アクション
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  TextButton(
                    onPressed: () => _showPickerSheet(context),
                    child: Text(
                      _hasAny ? 'CHANGE' : 'CHOOSE PHOTO',
                      style: typo.metaSmall.copyWith(color: colors.fg),
                    ),
                  ),
                  if (_hasAny) ...<Widget>[
                    Container(
                      width: 1,
                      height: 12,
                      color: colors.line,
                    ),
                    TextButton(
                      onPressed: () => onPicked(null),
                      child: Text(
                        'REMOVE',
                        style: typo.metaSmall.copyWith(color: colors.accentDanger),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar() {
    if (currentPhotoFile != null) {
      // 新規選択直後の一時ファイル
      return ClipOval(
        child: Image.file(
          currentPhotoFile!,
          width: AppDimensions.avatarHero,
          height: AppDimensions.avatarHero,
          fit: BoxFit.cover,
        ),
      );
    }

    // 既存写真 or fallback
    return PetAvatar(
      size: AppDimensions.avatarHero,
      relativePhotoPath: currentRelativePath,
      fallbackInitial: fallbackInitial,
    );
  }

  // ============================================================================
  // Picker sheet
  // ============================================================================

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
        // image_picker側でも軽く圧縮してメモリ節約
        // 本格圧縮はPhotoStorage._compressAndSaveで実施
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (picked == null) return;

      if (!context.mounted) return;
      // build 12: クロップ → アバターは円形表示なので 1:1 で長辺 1024 + 品質 85
      final File? cropped = await _cropToSquare(context, picked.path);
      if (cropped != null) {
        onPicked(cropped);
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('Image picker failed', error: e, stackTrace: st);
      // 親側に通知する仕組みは必要に応じて追加 (現状はサイレント)
    }
  }

  /// 1:1 でクロップして長辺 1024px 上限の JPEG を返す。
  /// キャンセル時は null。
  Future<File?> _cropToSquare(BuildContext context, String path) async {
    final AppColors colors = AppColors.of(context);
    try {
      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
        uiSettings: <PlatformUiSettings>[
          IOSUiSettings(
            title: 'トリミング',
            doneButtonTitle: '確定',
            cancelButtonTitle: 'キャンセル',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
          AndroidUiSettings(
            toolbarTitle: 'トリミング',
            toolbarColor: colors.fg,
            toolbarWidgetColor: colors.bg,
            backgroundColor: colors.bg,
            statusBarColor: colors.fg,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
        ],
      );
      if (cropped == null) return null;
      return File(cropped.path);
    } catch (e, st) {
      PetloLogger.instance
          .w('Image cropper failed', error: e, stackTrace: st);
      // クロップ失敗時は元ファイルをそのまま使う
      return File(path);
    }
  }
}

// ============================================================================
// PickerSheet (内部)
// ============================================================================
class _PickerSheet extends StatelessWidget {
  const _PickerSheet();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return Container(
      color: colors.bg,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 24),
            _SheetRow(
              label: 'Take a photo',
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            Divider(height: 1, color: colors.line),
            _SheetRow(
              label: 'Choose from library',
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 16),
            Container(height: 8, color: colors.bgSoft),
            _SheetRow(
              label: 'Cancel',
              labelStyle: typo.bodyLarge.copyWith(color: colors.fgMuted),
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
    this.labelStyle,
  });

  final String label;
  final VoidCallback onTap;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final AppTypography typo = AppTypography.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 28),
        alignment: Alignment.center,
        child: Text(
          label,
          style: labelStyle ?? typo.bodyLarge,
        ),
      ),
    );
  }
}
