// ============================================================================
// petlo - Life Tab Screen
// ============================================================================
//
// 日常記録(食事・排泄系・嘔吐)の一覧画面。
//
// 構成:
//   - ヒーロー (Daily life タイトル)
//   - 種別フィルタチップ (All / Meal / Stool / Pee / Vomit)
//   - 該当する記録のタイムラインリスト
//
// 既存の Provider を使ってクライアント側でマージ + フィルタ。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../providers/meals_providers.dart';
import '../../providers/pees_providers.dart';
import '../../providers/poops_providers.dart';
import '../../providers/scope_providers.dart';
import '../../providers/vomits_providers.dart';
import '../../providers/tab_provider.dart';
import '../../widgets/pet_selector/auto_select_first_pet.dart';
import '../../widgets/petlo_scaffold.dart';
import '../meal/meal_record_screen.dart';
import '../pee/pee_record_screen.dart';
import '../poop/poop_record_screen.dart';
import '../vomit/vomit_record_screen.dart';

enum _LifeFilter { all, meal, stool, pee, vomit }

final NotifierProvider<_LifeFilterNotifier, _LifeFilter> _lifeFilterProvider =
    NotifierProvider<_LifeFilterNotifier, _LifeFilter>(
        _LifeFilterNotifier.new);

class _LifeFilterNotifier extends Notifier<_LifeFilter> {
  @override
  _LifeFilter build() => _LifeFilter.all;
  void select(_LifeFilter f) => state = f;
}

// ============================================================================
// 一覧データ取得用 Provider (Life用、最新50件まで)
// ============================================================================
final StreamProvider<List<MealEntity>> _lifeMealsProvider =
    StreamProvider<List<MealEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<MealEntity>>.value(<MealEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) return Stream<List<MealEntity>>.value(<MealEntity>[]);
    return ref.watch(mealsRepositoryProvider).watchForPet(petId, limit: 50);
  },
);

final StreamProvider<List<PoopEntity>> _lifePoopsProvider =
    StreamProvider<List<PoopEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<PoopEntity>>.value(<PoopEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) return Stream<List<PoopEntity>>.value(<PoopEntity>[]);
    return ref.watch(poopsRepositoryProvider).watchForPet(petId, limit: 50);
  },
);

final StreamProvider<List<PeeEntity>> _lifePeesProvider =
    StreamProvider<List<PeeEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<PeeEntity>>.value(<PeeEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) return Stream<List<PeeEntity>>.value(<PeeEntity>[]);
    return ref.watch(peesRepositoryProvider).watchForPet(petId, limit: 50);
  },
);

final StreamProvider<List<VomitEntity>> _lifeVomitsProvider =
    StreamProvider<List<VomitEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<VomitEntity>>.value(<VomitEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) return Stream<List<VomitEntity>>.value(<VomitEntity>[]);
    return ref.watch(vomitsRepositoryProvider).watchForPet(petId, limit: 50);
  },
);

// ============================================================================
// LifeTabScreen
// ============================================================================
class LifeTabScreen extends ConsumerWidget {
  const LifeTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTypography typo = AppTypography.of(context);
    final AppColors colors = AppColors.of(context);
    final String? currentPetId = ref.watch(currentPetIdProvider);
    final bool hasPet = currentPetId != null && currentPetId != kAllPetsId;
    final _LifeFilter filter = ref.watch(_lifeFilterProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);

    autoSelectFirstPetIfAllSelected(ref, forTab: AppTab.life);

    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return PetloScaffold(
      showTabBar: false,
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
            SectionLabel(
              l10n.tab_eyebrow_life,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
            ),

            if (!hasPet)
              _SelectPetEmptyState(colors: colors, typo: typo)
            else ...<Widget>[
              _FilterChips(
                current: filter,
                onChanged: (f) =>
                    ref.read(_lifeFilterProvider.notifier).select(f),
                l10n: l10n,
              ),
              const SizedBox(height: 24),
              _FilteredList(filter: filter),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SelectPetEmptyState - ペット未選択時の表示
// ============================================================================
class _SelectPetEmptyState extends StatelessWidget {
  const _SelectPetEmptyState({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(
        AppLocalizations.of(context).tab_select_pet_life,
        style: typo.bodyMedium.copyWith(color: colors.fgMuted, height: 1.6),
      ),
    );
  }
}

// ============================================================================
// FilterChips
// ============================================================================
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.current,
    required this.onChanged,
    required this.l10n,
  });

  final _LifeFilter current;
  final ValueChanged<_LifeFilter> onChanged;
  final AppLocalizations l10n;

  String _label(_LifeFilter f) {
    switch (f) {
      case _LifeFilter.all:
        return l10n.record_kind_all;
      case _LifeFilter.meal:
        return l10n.record_kind_meal;
      case _LifeFilter.stool:
        return l10n.record_kind_stool;
      case _LifeFilter.pee:
        return l10n.record_kind_pee;
      case _LifeFilter.vomit:
        return l10n.record_kind_vomit;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final _LifeFilter f in _LifeFilter.values)
          InkWell(
            onTap: () => onChanged(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: current == f ? colors.fg : colors.bg,
                border: Border.all(color: colors.fg, width: 1),
              ),
              child: Text(
                _label(f),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  fontWeight: current == f
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: current == f ? colors.bg : colors.fg,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// FilteredList - 5種をマージしてフィルタかけて時系列表示
// ============================================================================
class _FilteredList extends ConsumerWidget {
  const _FilteredList({required this.filter});

  final _LifeFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final List<_LifeRow> items = <_LifeRow>[];

    if (filter == _LifeFilter.all || filter == _LifeFilter.meal) {
      items.addAll(ref.watch(_lifeMealsProvider).maybeWhen(
            data: (List<MealEntity> list) =>
                list.map((m) => _LifeRow.meal(m)),
            orElse: () => <_LifeRow>[],
          ));
    }
    if (filter == _LifeFilter.all || filter == _LifeFilter.stool) {
      items.addAll(ref.watch(_lifePoopsProvider).maybeWhen(
            data: (List<PoopEntity> list) =>
                list.map((p) => _LifeRow.poop(p)),
            orElse: () => <_LifeRow>[],
          ));
    }
    if (filter == _LifeFilter.all || filter == _LifeFilter.pee) {
      items.addAll(ref.watch(_lifePeesProvider).maybeWhen(
            data: (List<PeeEntity> list) =>
                list.map((p) => _LifeRow.pee(p)),
            orElse: () => <_LifeRow>[],
          ));
    }
    if (filter == _LifeFilter.all || filter == _LifeFilter.vomit) {
      items.addAll(ref.watch(_lifeVomitsProvider).maybeWhen(
            data: (List<VomitEntity> list) =>
                list.map((v) => _LifeRow.vomit(v)),
            orElse: () => <_LifeRow>[],
          ));
    }

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          l10n.record_list_empty,
          style: typo.bodyMedium.copyWith(color: colors.fgMuted),
        ),
      );
    }

    // 日付ごとにグループ化
    final Map<String, List<_LifeRow>> byDate = <String, List<_LifeRow>>{};
    for (final _LifeRow r in items) {
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(r.timestamp);
      final String key =
          '${t.year}-${t.month.toString().padLeft(2, "0")}-${t.day.toString().padLeft(2, "0")}';
      (byDate[key] ??= <_LifeRow>[]).add(r);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final String dateKey in byDate.keys) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              _humanizeDate(dateKey, l10n),
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                color: colors.fgMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final _LifeRow r in byDate[dateKey]!) _RowTile(row: r),
        ],
      ],
    );
  }

  String _humanizeDate(String key, AppLocalizations l10n) {
    final DateTime now = DateTime.now();
    final String today =
        '${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}';
    final DateTime yest = now.subtract(const Duration(days: 1));
    final String yKey =
        '${yest.year}-${yest.month.toString().padLeft(2, "0")}-${yest.day.toString().padLeft(2, "0")}';
    if (key == today) return l10n.record_today_label;
    if (key == yKey) return l10n.record_yesterday_label;
    return key;
  }
}

// ============================================================================
// 内部用 sealed
// ============================================================================
sealed class _LifeRow {
  _LifeRow(this.timestamp);

  factory _LifeRow.meal(MealEntity m) = _LifeMealRow;
  factory _LifeRow.poop(PoopEntity p) = _LifePoopRow;
  factory _LifeRow.pee(PeeEntity p) = _LifePeeRow;
  factory _LifeRow.vomit(VomitEntity v) = _LifeVomitRow;

  final int timestamp;

  String kind(AppLocalizations l10n);
  String summary(AppLocalizations l10n);
  void onTap(BuildContext context);
}

class _LifeMealRow extends _LifeRow {
  _LifeMealRow(this.entity) : super(entity.eatenAt);
  final MealEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_meal;
  @override
  String summary(AppLocalizations l10n) {
    final String name = entity.foodNameFreeText ?? l10n.record_kind_unspecified;
    return entity.amountG != null ? '$name · ${entity.amountG}g' : name;
  }

  @override
  void onTap(BuildContext c) =>
      MealRecordScreen.push(c, editingMealId: entity.id);
}

class _LifePoopRow extends _LifeRow {
  _LifePoopRow(this.entity) : super(entity.pooedAt);
  final PoopEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_stool;
  @override
  String summary(AppLocalizations l10n) =>
      '${_lifePoopFormLabel(l10n, entity.form)} · ${_lifePoopColorLabel(l10n, entity.color)}';
  @override
  void onTap(BuildContext c) =>
      PoopRecordScreen.push(c, editingPoopId: entity.id);
}

class _LifePeeRow extends _LifeRow {
  _LifePeeRow(this.entity) : super(entity.peedAt);
  final PeeEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_pee;
  @override
  String summary(AppLocalizations l10n) =>
      '${_lifePeeColorLabel(l10n, entity.color)} · ${entity.count}×';
  @override
  void onTap(BuildContext c) =>
      PeeRecordScreen.push(c, editingPeeId: entity.id);
}

class _LifeVomitRow extends _LifeRow {
  _LifeVomitRow(this.entity) : super(entity.vomitedAt);
  final VomitEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_vomit;
  @override
  String summary(AppLocalizations l10n) {
    final String c = entity.color == VomitColor.other
        ? (entity.colorOtherText ?? l10n.vomit_color_other)
        : _lifeVomitColorLabel(l10n, entity.color);
    return '$c · ${entity.count}×';
  }

  @override
  void onTap(BuildContext c) =>
      VomitRecordScreen.push(c, editingVomitId: entity.id);
}

String _lifePoopFormLabel(AppLocalizations l10n, PoopForm f) {
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

String _lifePoopColorLabel(AppLocalizations l10n, PoopColor c) {
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

String _lifePeeColorLabel(AppLocalizations l10n, PeeColor c) {
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

String _lifeVomitColorLabel(AppLocalizations l10n, VomitColor c) {
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

// ============================================================================
// 行表示
// ============================================================================
class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});
  final _LifeRow row;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final DateTime t = DateTime.fromMillisecondsSinceEpoch(row.timestamp);
    final String time =
        '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';

    return InkWell(
      onTap: () => row.onTap(context),
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
                row.kind(l10n),
                style: typo.metaSmall.copyWith(color: colors.fg),
              ),
            ),
            Expanded(
              child: Text(
                row.summary(l10n),
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
