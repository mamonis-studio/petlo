// ============================================================================
// petlo - AI Chat 用 画像前処理 (build 15)
// ============================================================================
//
// 画像添付時の前処理パイプライン:
//   1. 長辺 2048px に縮小
//   2. JPEG q80 で圧縮
//   3. 端末内 app_documents/chat_images/<id>.jpg に保存
//   4. Base64 文字列を返す(送信用)
//
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

class AiImagePreprocessor {
  AiImagePreprocessor._();

  static const int _maxLongEdge = 2048;
  static const int _jpegQuality = 80;

  /// 画像を縮小・圧縮し、ローカル保存 + Base64 文字列を返す。
  /// 失敗時は null。
  static Future<({String base64, String mediaType, String localPath})?>
      processForChat(File source, String storageId) async {
    try {
      final Uint8List bytes = await source.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        PetloLogger.instance.w('decodeImage returned null');
        return null;
      }

      // 長辺 2048px に縮小
      final img.Image resized;
      final int longEdge =
          decoded.width >= decoded.height ? decoded.width : decoded.height;
      if (longEdge > _maxLongEdge) {
        if (decoded.width >= decoded.height) {
          resized = img.copyResize(decoded, width: _maxLongEdge);
        } else {
          resized = img.copyResize(decoded, height: _maxLongEdge);
        }
      } else {
        resized = decoded;
      }

      // JPEG 圧縮
      final List<int> jpegBytes =
          img.encodeJpg(resized, quality: _jpegQuality);

      // 保存
      final Directory docs = await getApplicationDocumentsDirectory();
      final Directory dir =
          Directory(p.join(docs.path, 'chat_images'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final String filename = '$storageId.jpg';
      final File outFile = File(p.join(dir.path, filename));
      await outFile.writeAsBytes(jpegBytes, flush: true);

      // 相対パス(端末識別子に依存せず、ドキュメント基準で再現可能)
      final String relativePath = 'chat_images/$filename';

      return (
        base64: base64Encode(jpegBytes),
        mediaType: 'image/jpeg',
        localPath: relativePath,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('AiImagePreprocessor.processForChat failed', error: e, stackTrace: st);
      return null;
    }
  }

  /// 相対パス → 絶対パス
  static Future<File?> resolveLocal(String relativePath) async {
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      return File(p.join(docs.path, relativePath));
    } catch (_) {
      return null;
    }
  }
}
