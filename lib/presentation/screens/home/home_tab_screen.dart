// ============================================================================
// petlo - Home Tab Screen
// ============================================================================
//
// ホームタブ。ペットの「今日」をひと目で把握する画面。
//
// 構成:
//   - ヒーロー (Today + petlo タイトル)
//   - Quick log (4種): Meal/Stool/Pee/Vomit
//   - Memories: Add diary + Gallery
//   - Recent activity: 5種を時系列ソート(最新10件)
//
// rev5.1 F-00 ペット選択
// rev3 §4.7 アクセシビリティ
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/outlined_action_button.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/diaries_providers.dart';
import '../../providers/meals_providers.dart';
import '../../providers/pees_providers.dart';
import '../../providers/poops_providers.dart';
import '../../providers/scope_providers.dart';
import '../../providers/vomits_providers.dart';
import '../../widgets/petlo_scaffold.dart';
import '../diary/diary_record_screen.dart';
import '../gallery/pet_gallery_screen.dart';
import '../meal/meal_record_screen.dart';
import '../../providers/pets_providers.dart';
import '../../providers/tab_provider.dart';
import '../../widgets/pet_selector/auto_select_first_pet.dart';
import '../pee/pee_record_screen.dart';
import '../pet/pet_form_screen.dart';
import '../poop/poop_record_screen.dart';
import '../vomit/vomit_record_screen.dart';

class HomeTabScreen extends ConsumerWidget {
  const HomeTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? currentPetId = ref.watch(currentPetIdProvider);
    final bool canEdit = ref.watch(canEditProvider);
    final bool hasPet = currentPetId != null && currentPetId != kAllPetsId;
    // ペット 0匹判定: hasNoPetsProvider が AsyncData(true) なら登録 CTA を出す。
    // All Pets 選択中でもペットが存在すれば CTA は出さない。
    final bool noPets = ref.watch(hasNoPetsProvider).maybeWhen(
          data: (bool v) => v,
          orElse: () => false,
        );

    // ホームでは All Pets を出さず、個別ペットを強制選択(他タブと干渉しないよう forTab で gate)
    autoSelectFirstPetIfAllSelected(ref, forTab: AppTab.home);

    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return PetloScaffold(
      showTabBar: false,
      onAddPetTapped: () => PetFormScreen.push(context),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          28,
          16,
          28,
          28 + bottomInset + kBottomNavigationBarHeight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // タブ識別 eyebrow (§ ホーム)
            SectionLabel(
              l10n.tab_eyebrow_home,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
            ),
            if (hasPet && canEdit) ...<Widget>[
              SectionLabel(l10n.home_section_quick_log),
              const SizedBox(height: 12),
              const _QuickLogGrid(),
              const SizedBox(height: 32),
            ],

            if (hasPet) ...<Widget>[
              SectionLabel(l10n.home_section_memories),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  if (canEdit)
                    Expanded(
                      child: OutlinedActionButton(
                        label: l10n.home_action_add_diary,
                        onPressed: () => DiaryRecordScreen.push(context),
                      ),
                    ),
                  if (canEdit) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedActionButton(
                      label: l10n.home_action_gallery,
                      onPressed: () => PetGalleryScreen.push(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],

            if (hasPet) ...<Widget>[
              SectionLabel(l10n.home_section_recent_activity),
              const SizedBox(height: 12),
              const _RecentActivity(),
              const SizedBox(height: 32),
            ],

            // ペットが 1匹以上いて All Pets 選択中なら、CTA ではなく
            // 「ペットを選んでください」ヒントを出す。0匹のときのみ CTA。
            if (noPets)
              _EmptyHomeState(
                colors: colors,
                typo: typo,
                onAddPet: () => PetFormScreen.push(context),
              )
            else if (!hasPet)
              _SelectPetHint(colors: colors, typo: typo),
          ],
        ),
      ),
    );
  }
}

class _SelectPetHint extends StatelessWidget {
  const _SelectPetHint({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(
        AppLocalizations.of(context).tab_select_pet_health,
        style: typo.bodyMedium.copyWith(color: colors.fgMuted, height: 1.6),
      ),
    );
  }
}

class _EmptyHomeState extends StatelessWidget {
  const _EmptyHomeState({
    required this.colors,
    required this.typo,
    required this.onAddPet,
  });

  final AppColors colors;
  final AppTypography typo;
  final VoidCallback onAddPet;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${l10n.home_empty_hero_line1}\n${l10n.home_empty_hero_line2}',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 36,
              letterSpacing: -36 * 0.04,
              height: 0.95,
              color: colors.fg,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.home_empty_body,
            style: typo.bodyMedium.copyWith(color: colors.fgMuted),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: l10n.home_register_pet,
            onPressed: onAddPet,
          ),
        ],
      ),
    );
  }
}

class _QuickLogGrid extends StatelessWidget {
  const _QuickLogGrid();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedActionButton(
                label: l10n.home_quick_label_meal,
                onPressed: () => MealRecordScreen.push(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedActionButton(
                label: l10n.home_quick_label_stool,
                onPressed: () => PoopRecordScreen.push(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedActionButton(
                label: l10n.home_quick_label_pee,
                onPressed: () => PeeRecordScreen.push(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedActionButton(
                label: l10n.home_quick_label_vomit,
                onPressed: () => VomitRecordScreen.push(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final AsyncValue<List<MealEntity>> meals =
        ref.watch(recentMealsForHomeProvider);
    final AsyncValue<List<PoopEntity>> poops =
        ref.watch(recentPoopsForHomeProvider);
    final AsyncValue<List<PeeEntity>> pees =
        ref.watch(recentPeesForHomeProvider);
    final AsyncValue<List<VomitEntity>> vomits =
        ref.watch(recentVomitsForHomeProvider);
    final AsyncValue<List<DiaryEntity>> diaries =
        ref.watch(recentDiariesForHomeProvider);

    final List<HomeActivityItem> items = <HomeActivityItem>[
      ...meals.maybeWhen(
        data: (List<MealEntity> list) =>
            list.map((m) => HomeActivityItem.meal(m)),
        orElse: () => <HomeActivityItem>[],
      ),
      ...poops.maybeWhen(
        data: (List<PoopEntity> list) =>
            list.map((p) => HomeActivityItem.poop(p)),
        orElse: () => <HomeActivityItem>[],
      ),
      ...pees.maybeWhen(
        data: (List<PeeEntity> list) =>
            list.map((p) => HomeActivityItem.pee(p)),
        orElse: () => <HomeActivityItem>[],
      ),
      ...vomits.maybeWhen(
        data: (List<VomitEntity> list) =>
            list.map((v) => HomeActivityItem.vomit(v)),
        orElse: () => <HomeActivityItem>[],
      ),
      ...diaries.maybeWhen(
        data: (List<DiaryEntity> list) =>
            list.map((d) => HomeActivityItem.diary(d)),
        orElse: () => <HomeActivityItem>[],
      ),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (items.isEmpty) {
      return Text(
        AppLocalizations.of(context).record_list_empty,
        style: typo.bodySmall.copyWith(color: colors.fgMuted),
      );
    }

    return Column(
      children: <Widget>[
        for (final HomeActivityItem item in items.take(10))
          _ActivityRow(item: item),
      ],
    );
  }
}

sealed class HomeActivityItem {
  HomeActivityItem(this.timestamp);

  factory HomeActivityItem.meal(MealEntity m) => HomeMealActivity(m);
  factory HomeActivityItem.poop(PoopEntity p) => HomePoopActivity(p);
  factory HomeActivityItem.pee(PeeEntity p) => HomePeeActivity(p);
  factory HomeActivityItem.vomit(VomitEntity v) => HomeVomitActivity(v);
  factory HomeActivityItem.diary(DiaryEntity d) => HomeDiaryActivity(d);

  final int timestamp;

  String kind(AppLocalizations l10n);
  String summary(AppLocalizations l10n);
  void onTap(BuildContext context);
}

class HomeMealActivity extends HomeActivityItem {
  HomeMealActivity(this.entity) : super(entity.eatenAt);
  final MealEntity entity;

  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_meal;
  @override
  String summary(AppLocalizations l10n) {
    final String name = entity.foodNameFreeText ?? l10n.record_kind_unspecified;
    return entity.amountG != null ? '$name · ${entity.amountG}g' : name;
  }

  @override
  void onTap(BuildContext context) =>
      MealRecordScreen.push(context, editingMealId: entity.id);
}

class HomePoopActivity extends HomeActivityItem {
  HomePoopActivity(this.entity) : super(entity.pooedAt);
  final PoopEntity entity;

  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_stool;
  @override
  String summary(AppLocalizations l10n) =>
      '${_poopFormLabel(l10n, entity.form)} · ${_poopColorLabel(l10n, entity.color)}';

  @override
  void onTap(BuildContext context) =>
      PoopRecordScreen.push(context, editingPoopId: entity.id);
}

class HomePeeActivity extends HomeActivityItem {
  HomePeeActivity(this.entity) : super(entity.peedAt);
  final PeeEntity entity;

  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_pee;
  @override
  String summary(AppLocalizations l10n) =>
      '${_peeColorLabel(l10n, entity.color)} · ${entity.count}×';

  @override
  void onTap(BuildContext context) =>
      PeeRecordScreen.push(context, editingPeeId: entity.id);
}

class HomeVomitActivity extends HomeActivityItem {
  HomeVomitActivity(this.entity) : super(entity.vomitedAt);
  final VomitEntity entity;

  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_vomit;
  @override
  String summary(AppLocalizations l10n) {
    final String c = entity.color == VomitColor.other
        ? (entity.colorOtherText ?? l10n.vomit_color_other)
        : _vomitColorLabel(l10n, entity.color);
    return '$c · ${entity.count}×';
  }

  @override
  void onTap(BuildContext context) =>
      VomitRecordScreen.push(context, editingVomitId: entity.id);
}

class HomeDiaryActivity extends HomeActivityItem {
  HomeDiaryActivity(this.entity) : super(entity.eventAt);
  final DiaryEntity entity;

  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_diary;
  @override
  String summary(AppLocalizations l10n) {
    final String t = entity.title?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final String firstLine = entity.body.trim().split('\n').first;
    return firstLine.length > 60
        ? '${firstLine.substring(0, 60)}…'
        : firstLine;
  }

  @override
  void onTap(BuildContext context) =>
      DiaryRecordScreen.push(context, editingDiaryId: entity.id);
}

String _poopFormLabel(AppLocalizations l10n, PoopForm f) {
  switch (f) {
    case PoopForm.hard:
      return l10n.poop_form_hard;
    case PoopForm.lumpy:
      return l10n.poop_form_lumpy;
    case PoopForm.normal:
      return l10n.poop_form_normal;
    case PoopForm.soft:
      return l10n.poop_form_soft;
    case PoopForm.watery:
      return l10n.poop_form_watery;
  }
}

String _poopColorLabel(AppLocalizations l10n, PoopColor c) {
  switch (c) {
    case PoopColor.brown:
      return l10n.poop_color_brown;
    case PoopColor.black:
      return l10n.poop_color_black;
    case PoopColor.red:
      return l10n.poop_color_red;
    case PoopColor.yellow:
      return l10n.poop_color_yellow;
    case PoopColor.pale:
      return l10n.poop_color_pale;
  }
}

String _peeColorLabel(AppLocalizations l10n, PeeColor c) {
  switch (c) {
    case PeeColor.pale_yellow:
      return l10n.pee_color_pale;
    case PeeColor.yellow:
      return l10n.pee_color_yellow;
    case PeeColor.dark_yellow:
      return l10n.pee_color_dark;
    case PeeColor.amber:
      return l10n.pee_color_amber;
    case PeeColor.red:
      return l10n.pee_color_red;
    case PeeColor.cloudy:
      return l10n.pee_color_cloudy;
  }
}

String _vomitColorLabel(AppLocalizations l10n, VomitColor c) {
  switch (c) {
    case VomitColor.clear:
      return l10n.vomit_color_clear;
    case VomitColor.yellow:
      return l10n.vomit_color_yellow;
    case VomitColor.brown:
      return l10n.vomit_color_brown;
    case VomitColor.food:
      return l10n.vomit_color_food;
    case VomitColor.white_foam:
      return l10n.vomit_color_white_foam;
    case VomitColor.red:
      return l10n.vomit_color_red;
    case VomitColor.green:
      return l10n.vomit_color_green;
    case VomitColor.black:
      return l10n.vomit_color_black;
    case VomitColor.other:
      return l10n.vomit_color_other;
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});
  final HomeActivityItem item;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final DateTime t = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
    final String time =
        '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';

    return InkWell(
      onTap: () => item.onTap(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 50,
              child: Text(
                time,
                style: typo.metaSmall.copyWith(
                  color: colors.fgMuted,
                  fontFeatures: <FontFeature>[
                    const FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                item.kind(l10n),
                style: typo.metaSmall.copyWith(color: colors.fg),
              ),
            ),
            Expanded(
              child: Text(
                item.summary(l10n),
                style: typo.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
