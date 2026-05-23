// ============================================================================
// petlo - AI Chat 用 画像前処理 (build 15)
// ============================================================================
//
// 画像添付時の前処理パイプライン:
//   1. 長辺 2048px に縮小
//   2. JPEG q80 で圧縮
//   3. PhotoStorage.saveChatImage 経由で端末内に保存
//   4. Base64 文字列を返す(送信用)
//
// build 40: 保存パス組み立てを PhotoStorage に集約。本ファイルは画像処理
// (decode / resize / encode) のみ担当し、ディスク I/O はストレージ層へ委譲。
// 旧 resolveLocal() は未参照だったため削除。表示側 (message_bubble.dart 等) は
// 既に独自に getApplicationDocumentsDirectory を解決している。
//
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../data/storage/photo_storage.dart';
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

      // 保存 (PhotoStorage に集約、build 40)
      final String relativePath = await PhotoStorage().saveChatImage(
        remoteId: storageId,
        jpegBytes: jpegBytes,
      );

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
}
