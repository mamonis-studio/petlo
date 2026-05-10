// ============================================================================
// petlo - PhotoFullscreenViewer
// ============================================================================
//
// 写真を全画面でプレビュー。横スワイプで前後の写真へ移動可能。
//
// 使い方:
//   PhotoFullscreenViewer.push(context,
//     paths: ['diaries/1/0.jpg', 'diaries/1/1.jpg'],
//     initialIndex: 0,
//   );
//
// 設計:
//   - PageView でスワイプ
//   - InteractiveViewer でピンチズーム対応
//   - タップで暗いオーバーレイの閉じるUI表示/非表示
//
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/logger.dart';

class PhotoFullscreenViewer extends StatefulWidget {
  const PhotoFullscreenViewer({
    required this.relativePaths,
    this.initialIndex = 0,
    super.key,
  });

  final List<String> relativePaths;
  final int initialIndex;

  static Future<void> push(
    BuildContext context, {
    required List<String> relativePaths,
    int initialIndex = 0,
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => PhotoFullscreenViewer(
          relativePaths: relativePaths,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, Animation<double> a, __, Widget child) {
          return FadeTransition(opacity: a, child: child);
        },
      ),
    );
  }

  @override
  State<PhotoFullscreenViewer> createState() => _PhotoFullscreenViewerState();
}

class _PhotoFullscreenViewerState extends State<PhotoFullscreenViewer> {
  late final PageController _pageController;
  int _currentIndex = 0;
  bool _showChrome = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          // ===== 写真スワイプエリア =====
          PageView.builder(
            controller: _pageController,
            itemCount: widget.relativePaths.length,
            onPageChanged: (int i) => setState(() => _currentIndex = i),
            itemBuilder: (BuildContext context, int index) {
              return GestureDetector(
                onTap: () => setState(() => _showChrome = !_showChrome),
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: _PhotoFromRelativePath(
                      relativePath: widget.relativePaths[index],
                    ),
                  ),
                ),
              );
            },
          ),

          // ===== Chrome (ヘッダー) =====
          AnimatedOpacity(
            opacity: _showChrome ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: <Widget>[
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 22),
                      ),
                    ),
                    const Spacer(),
                    if (widget.relativePaths.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${widget.relativePaths.length}',
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 11,
                            letterSpacing: 11 * 0.15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 相対パス → アプリのDocuments配下の絶対パスに解決して画像表示
class _PhotoFromRelativePath extends StatefulWidget {
  const _PhotoFromRelativePath({required this.relativePath});

  final String relativePath;

  @override
  State<_PhotoFromRelativePath> createState() =>
      _PhotoFromRelativePathState();
}

class _PhotoFromRelativePathState extends State<_PhotoFromRelativePath> {
  File? _file;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      final File f = File('${docs.path}/${widget.relativePath}');
      if (await f.exists()) {
        if (mounted) setState(() => _file = f);
      } else {
        if (mounted) setState(() => _missing = true);
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to resolve photo path', error: e, stackTrace: st);
      if (mounted) setState(() => _missing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_missing) {
      return Center(
        child: Text(
          'Photo unavailable',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontFamily: 'Manrope',
            fontSize: 14,
          ),
        ),
      );
    }
    if (_file == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
          ),
        ),
      );
    }
    return Image.file(_file!, fit: BoxFit.contain);
  }
}
