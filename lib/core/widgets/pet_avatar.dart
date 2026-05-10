// ============================================================================
// petlo - PetAvatar
// ============================================================================
//
// ペットのプロフィール写真を円形で表示する。
//
// 使用箇所:
//   - ペットセレクターバー (28px)
//   - ホーム画面ヒーロー (96px)
//   - メモリアル (140px)
//   - メンバー一覧 (36px)
//
// 写真がない場合のfallback:
//   - ペット名のイニシャル1文字 (Fraunces italic)
//   - 背景はbgSoft
//
// rev3: 写真は相対パス、絶対パスは保存しない
//   → 表示時は path_provider のApplication Documents に基づいて解決
//
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class PetAvatar extends StatelessWidget {
  const PetAvatar({
    required this.size,
    this.relativePhotoPath,
    this.fallbackInitial,
    this.borderColor,
    this.grayscale = false,
    super.key,
  });

  final double size;

  /// アプリ Documents ディレクトリからの相対パス
  /// (例: "pets/42/profile.jpg")
  final String? relativePhotoPath;

  /// 写真がない場合に表示するイニシャル (1文字推奨)
  /// 例: "T" (Taro), "ハ" (ハナ)
  final String? fallbackInitial;

  /// 円の縁取り色 (省略時はAppColors.line)
  final Color? borderColor;

  /// グレースケール表示 (非選択ペット用、rev5.1)
  final bool grayscale;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color border = borderColor ?? colors.line;

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.bgSoft,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 1),
        ),
        child: _buildContent(context, colors),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppColors colors) {
    if (relativePhotoPath != null && relativePhotoPath!.isNotEmpty) {
      return _PhotoLoader(
        relativePath: relativePhotoPath!,
        grayscale: grayscale,
        fallback: _initialFallback(colors),
      );
    }
    return _initialFallback(colors);
  }

  Widget _initialFallback(AppColors colors) {
    final String letter = (fallbackInitial ?? '?').characters.firstOrNull ?? '?';
    return Center(
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w400,
          fontSize: size * 0.45,
          color: colors.fgMuted,
        ),
      ),
    );
  }
}

// ============================================================================
// Private: 相対パス → 絶対パス解決 + Image.file 表示
// ============================================================================
class _PhotoLoader extends StatefulWidget {
  const _PhotoLoader({
    required this.relativePath,
    required this.grayscale,
    required this.fallback,
  });

  final String relativePath;
  final bool grayscale;
  final Widget fallback;

  @override
  State<_PhotoLoader> createState() => _PhotoLoaderState();
}

class _PhotoLoaderState extends State<_PhotoLoader> {
  Future<File?>? _fileF;

  @override
  void initState() {
    super.initState();
    _fileF = _resolveFile(widget.relativePath);
  }

  @override
  void didUpdateWidget(covariant _PhotoLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath) {
      _fileF = _resolveFile(widget.relativePath);
    }
  }

  Future<File?> _resolveFile(String relativePath) async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final File file = File(p.join(dir.path, relativePath));
      if (await file.exists()) return file;
    } catch (_) {
      // 失敗時は fallback
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _fileF,
      builder: (BuildContext context, AsyncSnapshot<File?> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final File? file = snap.data;
        if (file == null) return widget.fallback;

        final Widget img = Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
              widget.fallback,
        );

        if (widget.grayscale) {
          return ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0,      0,      0,      1, 0,
            ]),
            child: img,
          );
        }
        return img;
      },
    );
  }
}

// ============================================================================
// Convenience: standard avatar sizes
// ============================================================================

extension AppDimensionsAvatar on AppDimensions {
  /// セレクター用 (28px)
  static double get avatarSelector => AppDimensions.avatarSelector;

  /// ヒーロー用 (96px)
  static double get avatarHero => AppDimensions.avatarHero;
}
