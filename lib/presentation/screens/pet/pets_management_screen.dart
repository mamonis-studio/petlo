// ============================================================================
// petlo - Pets Management Screen (build 58)
// ============================================================================
//
// 設定 > ペット管理 から開く。現在グループ内のペット一覧 (active + parted)
// を表示し、各行タップで PetFormScreen (編集モード) に遷移する。
//
// 設計:
//   - 新規 provider は作らない:
//       active  → currentGroupPetsProvider (既存)
//       parted  → currentGroupPartedPetsProvider (既存)
//   - 各行タップで PetFormScreen.push(context, editingPetId: pet.id)
//   - 1 タップでも編集画面に入ったらヒントを永続消去 (markOpened)
//   - Viewer 権限ユーザでも閲覧は可、ただし行は表示のみ (編集は本人不可)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/pet_avatar.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/pet_edit_hint_provider.dart';
import '../../providers/pets_providers.dart';
import 'pet_form_screen.dart';

class PetsManagementScreen extends ConsumerWidget {
  const PetsManagementScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PetsManagementScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final AsyncValue<List<PetEntity>> activeAsync =
        ref.watch(currentGroupPetsProvider);
    final AsyncValue<List<PetEntity>> partedAsync =
        ref.watch(currentGroupPartedPetsProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          l10n.pets_management_app_bar,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.fg),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionLabel(
                l10n.pets_management_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              ),
              activeAsync.when(
                data: (List<PetEntity> active) =>
                    partedAsync.when(
                  data: (List<PetEntity> parted) => _buildLists(
                    context: context,
                    ref: ref,
                    active: active,
                    parted: parted,
                    l10n: l10n,
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                loading: () => const SizedBox.shrink(),
                error: (Object e, _) => Text('$e'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLists({
    required BuildContext context,
    required WidgetRef ref,
    required List<PetEntity> active,
    required List<PetEntity> parted,
    required AppLocalizations l10n,
  }) {
    if (active.isEmpty && parted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          l10n.pets_management_empty,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 13,
            color: AppColors.of(context).fgMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (active.isNotEmpty) ...<Widget>[
          SectionLabel(l10n.pets_management_section_active),
          const SizedBox(height: 8),
          for (final PetEntity p in active)
            _PetRow(pet: p, grayscale: false, onTap: () => _open(context, ref, p)),
          const SizedBox(height: 32),
        ],
        if (parted.isNotEmpty) ...<Widget>[
          SectionLabel(l10n.pets_management_section_parted),
          const SizedBox(height: 8),
          for (final PetEntity p in parted)
            _PetRow(pet: p, grayscale: true, onTap: () => _open(context, ref, p)),
        ],
      ],
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, PetEntity pet) async {
    await ref.read(hasOpenedPetEditProvider.notifier).markOpened();
    if (!context.mounted) return;
    await PetFormScreen.push(context, editingPetId: pet.id);
  }
}

class _PetRow extends StatelessWidget {
  const _PetRow({
    required this.pet,
    required this.grayscale,
    required this.onTap,
  });

  final PetEntity pet;
  final bool grayscale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            PetAvatar(
              size: 36,
              relativePhotoPath: pet.photoPath,
              fallbackInitial:
                  pet.name.isNotEmpty ? pet.name.characters.first : null,
              grayscale: grayscale,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    pet.name,
                    style: typo.bodyLarge.copyWith(
                      color: grayscale ? colors.fgMuted : colors.fg,
                    ),
                  ),
                  if (pet.breed != null && pet.breed!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        pet.breed!,
                        style: typo.bodySmall.copyWith(color: colors.fgMuted),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: colors.fgMuted),
          ],
        ),
      ),
    );
  }
}
