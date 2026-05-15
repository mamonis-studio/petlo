// ============================================================================
// petlo - Message Bubble
// ============================================================================
//
// チャットメッセージの表示。
// 役割別レイアウト:
//   - user: 右寄せ、黒背景・白文字、Manrope
//   - assistant: 左寄せ、白背景・黒文字、左に細い縦線、Fraunces混じりの柔らかい質感
//
// rev3 §UI規則: 黒白基調、絵文字なし
//
// ============================================================================

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/local/app_database.dart';
import '../../../../data/local/database_enums.dart';
import '../../gallery/photo_fullscreen_viewer.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    this.onRate,
    super.key,
  });

  final AiChatMessageEntity message;
  final void Function(AiFeedback rating)? onRate;

  bool get _isUser => message.role == AiMessageRole.user;

  @override
  Widget build(BuildContext context) {
    if (_isUser) return _buildUserBubble(context);
    return _buildAssistantBubble(context);
  }

  // ==========================================================================
  // User
  // ==========================================================================
  Widget _buildUserBubble(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(message.sentAt);
    final String time =
        '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';

    final String? imgPath = message.imagePath;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (imgPath != null && imgPath.isNotEmpty) ...<Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.6,
                maxHeight: 240,
              ),
              child: InkWell(
                onTap: () => PhotoFullscreenViewer.push(
                  context,
                  relativePaths: <String>[imgPath],
                ),
                child: _ImageFromDocs(relativePath: imgPath),
              ),
            ),
            const SizedBox(height: 6),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.fg,
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  height: 1.55,
                  color: colors.bg,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9,
              letterSpacing: 9 * 0.15,
              color: colors.fgFaint,
              fontFeatures: const <FontFeature>[
                FontFeature.tabularFigures(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Assistant
  // ==========================================================================
  Widget _buildAssistantBubble(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(message.sentAt);
    final String time =
        '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ヘッダー: PETLO · time
          Row(
            children: <Widget>[
              Text(
                'PETLO',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 9,
                  letterSpacing: 9 * 0.2,
                  color: colors.fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                time,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 9,
                  letterSpacing: 9 * 0.15,
                  color: colors.fgFaint,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 本文 (左に細い縦線、エディトリアル雑誌の引用風)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.92,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 4, 0, 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: colors.fg, width: 1.5),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 15,
                  height: 1.7,
                  color: colors.fg,
                ),
              ),
            ),
          ),

          // 👍/👎 評価ボタン
          if (onRate != null) ...<Widget>[
            const SizedBox(height: 10),
            _RatingButtons(
              current: message.rating,
              onTap: onRate!,
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// _RatingButtons - 👍/👎 (絵文字使わずテキストの GOOD / NEEDS WORK)
// ============================================================================
class _RatingButtons extends StatelessWidget {
  const _RatingButtons({required this.current, required this.onTap});

  final AiFeedback current;
  final void Function(AiFeedback rating) onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Row(
        children: <Widget>[
          _Pill(
            label: 'HELPFUL',
            isActive: current == AiFeedback.thumb_up,
            onTap: () => onTap(current == AiFeedback.thumb_up
                ? AiFeedback.none
                : AiFeedback.thumb_up),
            colors: colors,
          ),
          const SizedBox(width: 6),
          _Pill(
            label: 'NEEDS WORK',
            isActive: current == AiFeedback.thumb_down,
            onTap: () => onTap(current == AiFeedback.thumb_down
                ? AiFeedback.none
                : AiFeedback.thumb_down),
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? colors.fg : colors.bg,
          border: Border.all(
            color: isActive ? colors.fg : colors.line,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 9,
            letterSpacing: 9 * 0.18,
            color: isActive ? colors.bg : colors.fgMuted,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// build 15: チャット添付画像をドキュメント基準の相対パスから読み出す
// ============================================================================
class _ImageFromDocs extends StatefulWidget {
  const _ImageFromDocs({required this.relativePath});

  final String relativePath;

  @override
  State<_ImageFromDocs> createState() => _ImageFromDocsState();
}

class _ImageFromDocsState extends State<_ImageFromDocs> {
  late Future<io.File?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve(widget.relativePath);
  }

  Future<io.File?> _resolve(String rel) async {
    try {
      final io.Directory docs = await getApplicationDocumentsDirectory();
      return io.File(p.join(docs.path, rel));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<io.File?>(
      future: _future,
      builder: (_, AsyncSnapshot<io.File?> snap) {
        final io.File? f = snap.data;
        if (f == null) {
          return const SizedBox(width: 80, height: 80);
        }
        return Image.file(f, fit: BoxFit.cover);
      },
    );
  }
}
