// ============================================================================
// petlo - Pet Gallery Screen
// ============================================================================
//
// ペットの全日記から写真だけを抜き出してグリッド表示。
// タップで全画面プレビュー(PhotoFullscreenViewer)。
//
// rev3 §4.7: 相対パス保存 → 表示時にDocuments絶対化
//
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/utils/logger.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../data/local/app_database.dart';
import '../../providers/diaries_providers.dart';
import '../../widgets/empty_state.dart';
import 'photo_fullscreen_viewer.dart';

class PetGalleryScreen extends ConsumerWidget {
  const PetGalleryScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PetGalleryScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AsyncValue<List<DiaryEntity>> diariesAsync =
        ref.watch(currentPetDiariesWithPhotosProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          AppLocalizations.of(context).appbar_gallery,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: diariesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          error: (Object e, StackTrace st) => Center(
            child: Text(
              AppLocalizations.of(context).gallery_load_failed,
              style: TextStyle(color: colors.accentDanger),
            ),
          ),
          data: (List<DiaryEntity> diaries) {
            // 全写真を1次元リストに
            final List<String> allPhotos = <String>[
              for (final DiaryEntity d in diaries)
                ...(d.photoPaths ?? <String>[]),
            ];

            if (allPhotos.isEmpty) {
              return Center(
                child: EmptyState(
                  eyebrow: AppLocalizations.of(context).common_empty,
                  title: AppLocalizations.of(context).gallery_empty_hero,
                  subtitle: AppLocalizations.of(context).gallery_empty_body,
                  titleSize: 32,
                  titleColor: colors.fg,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  paddingHorizontal: AppDimensions.paddingPage,
                  paddingVertical: AppDimensions.paddingPage,
                ),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: allPhotos.length,
              itemBuilder: (BuildContext context, int index) {
                return _GridTile(
                  relativePath: allPhotos[index],
                  onTap: () => PhotoFullscreenViewer.push(
                    context,
                    relativePaths: allPhotos,
                    initialIndex: index,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _GridTile extends StatefulWidget {
  const _GridTile({required this.relativePath, required this.onTap});

  final String relativePath;
  final VoidCallback onTap;

  @override
  State<_GridTile> createState() => _GridTileState();
}

class _GridTileState extends State<_GridTile> {
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
    final AppColors colors = AppColors.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: _missing
            ? Container(
                color: colors.bgSoft,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined,
                    color: colors.fgFaint, size: 24),
              )
            : _file == null
                ? Container(color: colors.bgSoft)
                : Image.file(_file!, fit: BoxFit.cover),
      ),
    );
  }
}
