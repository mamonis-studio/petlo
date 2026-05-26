// ============================================================================
// petlo - Pet Share Picker (Phase G4b, build 46 全面リライト)
// ============================================================================
//
// 1 ペットを **複数グループ** に共有 / 共有解除 / 権限変更する modal。
//
// 旧 (build 20-45) は「Personal pet をこの group に転送する」single-select
// picker だった。multi-scope モデルでは「pet ごとに共有先 N グループを管理」
// する per-pet 操作になるため UI も per-pet 視点に作り変えた。
//
// 表示構造:
//   [ハンドル]
//   § 共有先
//   {pet name} (eyebrow)
//   ───────────
//   [Personal]  (primary バッジ、操作不可)
//   [Group A]   editor/viewer ドロップダウン + 「共有を解除」
//   [Group B]   未共有 → 「共有を追加」ボタン
//   [Group C]   ...
//   ───────────
//   [複数のグループに共有するには Pro プランが必要です。] (非 Pro user only)
//
// 設計判断:
//   - 書き込み経路は `PetScopesRepository.addPetScope` / `removePetScope`
//     / `updatePetScopePermission` (offline-first、sync_queue 経由でサーバ
//     伝播)。`PetShareApiService` REST は refresh ops 専用予約 (G4b では
//     未消費、将来「強制リフレッシュ」ボタン等に転用)。
//   - primary scope 行はラベル + バッジのみで操作 disabled (誤操作防止)。
//   - 共有解除前に `pet_share_unshare_confirm_*` で確認。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/groups_providers.dart';
import '../../providers/pet_scopes_providers.dart';
import '../../providers/pets_providers.dart';
import '../../providers/pro_status_provider.dart';
import '../../providers/scope_providers.dart';

class PetSharePicker {
  PetSharePicker._();

  /// per-pet 共有先管理を開く (Phase G4b 主用途)。
  static Future<void> showForPet(BuildContext context, int petId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
      ),
      builder: (_) => _PetSharePickerSheet(petId: petId),
    );
  }

  /// 旧 home empty state 用エントリ (build 20〜45)。Personal の最初のペットを
  /// 暗黙選択して [showForPet] に転送する。複数 Personal pet がいる場合は
  /// 簡易セレクタを挟む。multi-scope モデルへの過渡期用。
  static Future<void> show(
    BuildContext context, {
    required String targetGroupId,
  }) async {
    if (targetGroupId == kPersonalGroupId) return;
    final ProviderContainer container = ProviderScope.containerOf(context);
    final List<PetEntity> personalPets = await container
        .read(petsRepositoryProvider)
        .watchActivePetsInScope(kPersonalGroupId)
        .first;
    if (!context.mounted) return;
    if (personalPets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pet_share_picker_empty),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final int? petId = personalPets.length == 1
        ? personalPets.first.id
        : await _quickPickPersonalPet(context, personalPets);
    if (petId == null || !context.mounted) return;
    return showForPet(context, petId);
  }

  static Future<int?> _quickPickPersonalPet(
    BuildContext context,
    List<PetEntity> pets,
  ) async {
    final AppColors colors = AppColors.of(context);
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: colors.bg,
      builder: (BuildContext sheetContext) {
        final AppLocalizations l10n = AppLocalizations.of(sheetContext);
        final AppTypography typo = AppTypography.of(sheetContext);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 16),
                    color: colors.line,
                  ),
                ),
                SectionLabel(
                  l10n.pet_share_picker_title,
                  size: EyebrowSize.large,
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                ),
                Text(
                  l10n.pet_share_picker_body,
                  style: typo.bodySmall
                      .copyWith(color: colors.fgMuted, height: 1.5),
                ),
                const SizedBox(height: 16),
                for (final PetEntity p in pets)
                  InkWell(
                    onTap: () => Navigator.of(sheetContext).pop(p.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        border:
                            Border(bottom: BorderSide(color: colors.line)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              p.name,
                              style:
                                  typo.bodyLarge.copyWith(color: colors.fg),
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 20, color: colors.fgMuted),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// メイン modal: per-pet 共有先管理
// ============================================================================
class _PetSharePickerSheet extends ConsumerWidget {
  const _PetSharePickerSheet({required this.petId});

  final int petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final AsyncValue<PetEntity?> petAsync =
        ref.watch(_petByIdProvider(petId));
    final AsyncValue<List<PetScopeEntity>> scopesAsync =
        ref.watch(petScopesForPetProvider(petId));
    final AsyncValue<List<GroupEntity>> groupsAsync =
        ref.watch(userGroupsProvider);
    final bool isPro = ref.watch(isProProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 3,
                margin: const EdgeInsets.only(bottom: 16),
                color: colors.line,
              ),
            ),
            SectionLabel(
              l10n.pet_share_section_title,
              size: EyebrowSize.large,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
            ),
            petAsync.maybeWhen(
              data: (PetEntity? p) => Text(
                p?.name ?? '',
                style: typo.bodyMedium.copyWith(color: colors.fgMuted),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: SingleChildScrollView(
                child: _buildBody(
                  scopesAsync: scopesAsync,
                  groupsAsync: groupsAsync,
                  colors: colors,
                  typo: typo,
                  l10n: l10n,
                ),
              ),
            ),
            if (!isPro) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                l10n.pet_share_pro_required_hint,
                style: typo.bodySmall
                    .copyWith(color: colors.fgFaint, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody({
    required AsyncValue<List<PetScopeEntity>> scopesAsync,
    required AsyncValue<List<GroupEntity>> groupsAsync,
    required AppColors colors,
    required AppTypography typo,
    required AppLocalizations l10n,
  }) {
    if (scopesAsync.isLoading || groupsAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
      );
    }
    final List<PetScopeEntity> scopes = scopesAsync.maybeWhen(
      data: (List<PetScopeEntity> s) => s,
      orElse: () => const <PetScopeEntity>[],
    );
    final List<GroupEntity> groups = groupsAsync.maybeWhen(
      data: (List<GroupEntity> g) => g,
      orElse: () => const <GroupEntity>[],
    );

    final List<_RowSpec> rows = <_RowSpec>[
      _RowSpec(
        kind: _RowKind.personal,
        groupId: kPersonalGroupId,
        label: 'Personal',
        existingScope: _findScope(scopes, kPersonalGroupId),
      ),
      for (final GroupEntity g in groups)
        _RowSpec(
          kind: _RowKind.group,
          groupId: g.remoteId,
          label: g.name,
          existingScope: _findScope(scopes, g.remoteId),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final _RowSpec r in rows)
          _ScopeRow(
            petId: petId,
            spec: r,
            colors: colors,
            typo: typo,
            l10n: l10n,
          ),
      ],
    );
  }

  PetScopeEntity? _findScope(List<PetScopeEntity> scopes, String groupId) {
    for (final PetScopeEntity s in scopes) {
      if (s.groupId == groupId && s.deletedAt == null) return s;
    }
    return null;
  }
}

// ============================================================================
// Row spec
// ============================================================================
enum _RowKind { personal, group }

class _RowSpec {
  const _RowSpec({
    required this.kind,
    required this.groupId,
    required this.label,
    required this.existingScope,
  });

  final _RowKind kind;
  final String groupId;
  final String label;
  final PetScopeEntity? existingScope;

  bool get isShared => existingScope != null;
  bool get isPrimary => existingScope?.isPrimary == true;
}

// ============================================================================
// _ScopeRow: 1 グループ分の表示 + アクション
// ============================================================================
class _ScopeRow extends ConsumerWidget {
  const _ScopeRow({
    required this.petId,
    required this.spec,
    required this.colors,
    required this.typo,
    required this.l10n,
  });

  final int petId;
  final _RowSpec spec;
  final AppColors colors;
  final AppTypography typo;
  final AppLocalizations l10n;

  String _permissionLabel(MemberPermission p) {
    switch (p) {
      case MemberPermission.owner:
        return l10n.pet_share_permission_owner;
      case MemberPermission.editor:
        return l10n.pet_share_permission_editor;
      case MemberPermission.viewer:
        return l10n.pet_share_permission_viewer;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isShared = spec.isShared;
    final bool isPrimary = spec.isPrimary;
    final MemberPermission? perm = spec.existingScope?.permission;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        spec.label,
                        style: typo.bodyLarge.copyWith(color: colors.fg),
                      ),
                    ),
                    if (isPrimary) ...<Widget>[
                      const SizedBox(width: 8),
                      _Badge(
                        text: l10n.pet_share_primary_badge,
                        colors: colors,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (isShared)
                  _PermissionDropdown(
                    petId: petId,
                    groupId: spec.groupId,
                    current: perm!,
                    enabled: !isPrimary,
                    colors: colors,
                    typo: typo,
                    labelFor: _permissionLabel,
                  )
                else
                  Text(
                    '—',
                    style: typo.bodySmall
                        .copyWith(color: colors.fgFaint, height: 1.5),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isPrimary)
            const SizedBox(width: 80)
          else if (isShared)
            _UnshareButton(
              petId: petId,
              groupId: spec.groupId,
              groupLabel: spec.label,
              colors: colors,
              typo: typo,
              l10n: l10n,
            )
          else
            _ShareButton(
              petId: petId,
              groupId: spec.groupId,
              colors: colors,
              typo: typo,
              l10n: l10n,
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.colors});
  final String text;
  final AppColors colors;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.fgMuted, width: 1),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 8,
          letterSpacing: 8 * 0.18,
          color: colors.fgMuted,
        ),
      ),
    );
  }
}

class _PermissionDropdown extends ConsumerWidget {
  const _PermissionDropdown({
    required this.petId,
    required this.groupId,
    required this.current,
    required this.enabled,
    required this.colors,
    required this.typo,
    required this.labelFor,
  });

  final int petId;
  final String groupId;
  final MemberPermission current;
  final bool enabled;
  final AppColors colors;
  final AppTypography typo;
  final String Function(MemberPermission) labelFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) {
      return Text(
        labelFor(current),
        style: typo.bodySmall.copyWith(color: colors.fgMuted, height: 1.5),
      );
    }
    // primary 以外で owner を選ばせるとロジック上「primary 2 つ」の状態に
    // なるため owner は除外する。
    final List<MemberPermission> options = <MemberPermission>[
      MemberPermission.editor,
      MemberPermission.viewer,
    ];
    return DropdownButton<MemberPermission>(
      value: options.contains(current) ? current : MemberPermission.editor,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: typo.bodySmall.copyWith(color: colors.fg),
      items: <DropdownMenuItem<MemberPermission>>[
        for (final MemberPermission p in options)
          DropdownMenuItem<MemberPermission>(
            value: p,
            child: Text(labelFor(p)),
          ),
      ],
      onChanged: (MemberPermission? next) async {
        if (next == null || next == current) return;
        try {
          await ref
              .read(petScopesRepositoryProvider)
              .updatePetScopePermission(
                petId: petId,
                groupId: groupId,
                permission: next,
              );
        } catch (e, st) {
          PetloLogger.instance.w('updatePetScopePermission failed',
              error: e, stackTrace: st);
        }
      },
    );
  }
}

class _ShareButton extends ConsumerStatefulWidget {
  const _ShareButton({
    required this.petId,
    required this.groupId,
    required this.colors,
    required this.typo,
    required this.l10n,
  });

  final int petId;
  final String groupId;
  final AppColors colors;
  final AppTypography typo;
  final AppLocalizations l10n;

  @override
  ConsumerState<_ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends ConsumerState<_ShareButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await ref.read(petScopesRepositoryProvider).addPetScope(
                      petId: widget.petId,
                      groupId: widget.groupId,
                      permission: MemberPermission.editor,
                    );
              } catch (e, st) {
                PetloLogger.instance
                    .w('addPetScope failed', error: e, stackTrace: st);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: widget.colors.fg, width: 1),
        ),
        child: Text(
          widget.l10n.pet_share_add_action,
          style: widget.typo.bodySmall.copyWith(
            color: widget.colors.fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _UnshareButton extends ConsumerStatefulWidget {
  const _UnshareButton({
    required this.petId,
    required this.groupId,
    required this.groupLabel,
    required this.colors,
    required this.typo,
    required this.l10n,
  });

  final int petId;
  final String groupId;
  final String groupLabel;
  final AppColors colors;
  final AppTypography typo;
  final AppLocalizations l10n;

  @override
  ConsumerState<_UnshareButton> createState() => _UnshareButtonState();
}

class _UnshareButtonState extends ConsumerState<_UnshareButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _busy ? null : _confirm,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: widget.colors.fgMuted, width: 1),
        ),
        child: Text(
          widget.l10n.pet_share_unshare_action,
          style: widget.typo.bodySmall.copyWith(color: widget.colors.fgMuted),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    final PetEntity? pet =
        await ref.read(petsRepositoryProvider).getPet(widget.petId);
    if (!mounted) return;
    final String petName = pet?.name ?? '';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final AppLocalizations dl10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(dl10n.pet_share_unshare_confirm_title),
          content: Text(
            dl10n.pet_share_unshare_confirm_body(petName, widget.groupLabel),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dl10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dl10n.pet_share_unshare_action),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(petScopesRepositoryProvider).removePetScope(
            petId: widget.petId,
            groupId: widget.groupId,
          );
    } catch (e, st) {
      PetloLogger.instance
          .w('removePetScope failed', error: e, stackTrace: st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ============================================================================
// このペットの最新状態だけを watch する一時 provider
// ============================================================================
final StreamProviderFamily<PetEntity?, int> _petByIdProvider =
    StreamProvider.family<PetEntity?, int>(
  (Ref ref, int petId) =>
      ref.watch(petsRepositoryProvider).watchPet(petId),
);
