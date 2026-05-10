// ============================================================================
// petlo - Photo Storage
// ============================================================================
//
// アプリ内の写真ファイルを統一的に管理する。
//
// 設計方針:
//   - 保存パスは Application Documents/{subdir}/{filename}
//   - 戻り値・引数は **相対パス** ("pets/42/profile.jpg" 形式)
//     → rev3: 絶対パスは保存禁止 (iOS sandbox UUID変更対策)
//   - 圧縮: 長辺 1280px、JPEG 85品質、最大 5MB
//   - サブディレクトリ規則:
//       pets/{petId}/profile.jpg
//       meals/{recordId}/photo.jpg
//       diaries/{recordId}/{n}.jpg
//       ai_diagnoses/{recordId}/source.jpg
//
// 圧縮ライブラリは flutter_image_compress を想定 (pubspec.yaml に既存)
// 実際の圧縮実装は Chunk 19 (写真処理パイプライン)、このファイルは
// インターフェース + 単純なファイル I/O のみ。
//
// ============================================================================

import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

class PhotoStorage {
  PhotoStorage();

  /// アプリ専用 Documents ディレクトリのフルパス
  Future<Directory> _appDocs() => getApplicationDocumentsDirectory();

  /// 相対パス → 絶対 File
  /// 例: "pets/42/profile.jpg" → "/var/.../Documents/pets/42/profile.jpg"
  Future<File> resolveFile(String relativePath) async {
    final Directory dir = await _appDocs();
    return File(p.join(dir.path, relativePath));
  }

  /// 相対パスのファイルが存在するか
  Future<bool> exists(String relativePath) async {
    final File file = await resolveFile(relativePath);
    return file.exists();
  }

  // ============================================================================
  // Save
  // ============================================================================

  /// ペットのプロフィール写真を保存。
  /// 既存ファイルがあれば上書き。
  /// 戻り値は相対パス。
  Future<String> savePetProfilePhoto({
    required int petId,
    required File source,
  }) async {
    final String relPath = p.join('pets', '$petId', 'profile.jpg');
    return _compressAndSave(source: source, relativePath: relPath);
  }

  /// 食事記録の写真を保存
  Future<String> saveMealPhoto({
    required int mealId,
    required File source,
  }) async {
    final String relPath = p.join('meals', '$mealId', 'photo.jpg');
    return _compressAndSave(source: source, relativePath: relPath);
  }

  /// うんち写真 (AI画像診断用も兼用)
  Future<String> savePoopPhoto({
    required int poopId,
    required File source,
  }) async {
    final String relPath = p.join('poops', '$poopId', 'photo.jpg');
    return _compressAndSave(source: source, relativePath: relPath);
  }

  /// 嘔吐写真
  Future<String> saveVomitPhoto({
    required int vomitId,
    required File source,
  }) async {
    final String relPath = p.join('vomits', '$vomitId', 'photo.jpg');
    return _compressAndSave(source: source, relativePath: relPath);
  }

  /// 日記の n 番目の写真
  Future<String> saveDiaryPhoto({
    required int diaryId,
    required int index,
    required File source,
  }) async {
    final String relPath = p.join('diaries', '$diaryId', '$index.jpg');
    return _compressAndSave(source: source, relativePath: relPath);
  }

  /// 通院記録の n 番目の写真
  Future<String> saveVisitPhoto({
    required int visitId,
    required int index,
    required File source,
  }) async {
    final String relPath = p.join('visits', '$visitId', '$index.jpg');
    return _compressAndSave(source: source, relativePath: relPath);
  }

  // ============================================================================
  // Delete
  // ============================================================================

  /// 相対パスのファイルを削除 (存在しなくてもエラーにしない)
  Future<void> deleteByRelativePath(String relativePath) async {
    try {
      final File file = await resolveFile(relativePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to delete photo: $relativePath', error: e, stackTrace: st);
    }
  }

  /// ペットIDの全写真ディレクトリを削除 (ペット削除時用)
  Future<void> deletePetPhotos(int petId) async {
    await _deleteDirectory(p.join('pets', '$petId'));
  }

  Future<void> _deleteDirectory(String relativePath) async {
    try {
      final Directory dir = await _appDocs();
      final Directory target = Directory(p.join(dir.path, relativePath));
      if (await target.exists()) {
        await target.delete(recursive: true);
      }
    } catch (e, st) {
      PetloLogger.instance.w('Failed to delete dir: $relativePath',
          error: e, stackTrace: st);
    }
  }

  // ============================================================================
  // Internal: 圧縮 + 保存
  // ============================================================================

  Future<String> _compressAndSave({
    required File source,
    required String relativePath,
  }) async {
    final File destFile = await resolveFile(relativePath);

    // ディレクトリを再帰的に作成
    final Directory parent = destFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    // flutter_image_compress で圧縮
    // 長辺 photoMaxLongSide(1280)、JPEG quality photoJpegQuality(85)
    final result = await FlutterImageCompress.compressAndGetFile(
      source.absolute.path,
      destFile.absolute.path,
      minWidth: AppConstants.photoMaxLongSide,
      minHeight: AppConstants.photoMaxLongSide,
      quality: AppConstants.photoJpegQuality,
      format: CompressFormat.jpeg,
    );

    if (result == null) {
      throw StateError('Image compression failed for ${source.path}');
    }

    // ファイルサイズチェック (上限 5MB、AppConstantsから取得)
    final int sizeBytes = await File(result.path).length();
    final int limit = AppConstants.photoMaxSizeMb * 1024 * 1024;
    if (sizeBytes > limit) {
      // 万一上限を超える場合は再圧縮
      PetloLogger.instance.w(
        'Photo exceeded $limit bytes after first compression: $sizeBytes — retrying with quality 70',
      );
      await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        destFile.absolute.path,
        minWidth: 1024,
        minHeight: 1024,
        quality: 70,
        format: CompressFormat.jpeg,
      );
    }

    PetloLogger.instance.i('Saved photo: $relativePath (${sizeBytes ~/ 1024}KB)');
    return relativePath;
  }
}
