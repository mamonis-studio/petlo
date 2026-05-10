// ============================================================================
// petlo - Pet Context Builder
// ============================================================================
//
// AI 相談時にサーバーへ送る AiPetContextDto を、現在のペットと最近の記録から
// 組み立てるヘルパー。
//
// rev3 F-18: AI相談チャット (過去7日詳細 + 30日サマリ + セッション履歴)
//
// 設計:
//   - 直近7日の Meal/Poop/Pee/Vomit/Weight/Visit/Vaccination/Diary/Medication を集めて
//     date 別 type 別の自然言語1行に変換
//   - 30日サマリーは件数ベース ("Meals: 84, Stools: 22, ...")
//   - 体重・体温の最新値も summary に含める
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_pet_context.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_enums.dart';
import 'diaries_providers.dart';
import 'meals_providers.dart';
import 'pees_providers.dart';
import 'pets_providers.dart';
import 'poops_providers.dart';
import 'temperatures_providers.dart';
import 'vaccinations_providers.dart';
import 'visits_providers.dart';
import 'vomits_providers.dart';
import 'weights_providers.dart';

abstract final class PetContextBuilder {
  /// 現在ペットを起点にコンテキストを組み立てる。
  /// `pet` が未選択 / 取得中なら null。
  ///
  /// 呼び出し元は WidgetRef (UI 側) でも Ref (Notifier 側) でも構わない。
  static Future<AiPetContextDto?> buildForCurrentPet(Ref ref) async {
    final PetEntity? pet =
        await ref.read(currentPetProvider.future);
    if (pet == null) return null;

    // ===== 7日 / 30日 のレンジ =====
    final DateTime now = DateTime.now();
    final DateTime sevenDaysAgo = now.subtract(const Duration(days: 7));
    final DateTime thirtyDaysAgo = now.subtract(const Duration(days: 30));

    // ===== 各記録を取得 =====
    final List<MealEntity> meals = await ref
        .read(recentMealsForHomeProvider.future)
        .catchError((_) => <MealEntity>[]);
    final List<PoopEntity> poops = await ref
        .read(recentPoopsForHomeProvider.future)
        .catchError((_) => <PoopEntity>[]);
    final List<PeeEntity> pees = await ref
        .read(recentPeesForHomeProvider.future)
        .catchError((_) => <PeeEntity>[]);
    final List<VomitEntity> vomits = await ref
        .read(recentVomitsForHomeProvider.future)
        .catchError((_) => <VomitEntity>[]);
    final List<DiaryEntity> diaries = await ref
        .read(recentDiariesForHomeProvider.future)
        .catchError((_) => <DiaryEntity>[]);
    final List<VisitEntity> visits = await ref
        .read(currentPetVisitsProvider.future)
        .catchError((_) => <VisitEntity>[]);
    final List<VaccinationEntity> vaccinations = await ref
        .read(currentPetVaccinationsProvider.future)
        .catchError((_) => <VaccinationEntity>[]);
    final WeightEntity? latestWeight = await ref
        .read(currentPetLatestWeightProvider.future)
        .catchError((_) => null);
    final TemperatureEntity? latestTemp = await ref
        .read(currentPetLatestTemperatureProvider.future)
        .catchError((_) => null);

    // ===== 7日以内の記録を AiRecentRecordDto に変換 =====
    final List<AiRecentRecordDto> recent7d = <AiRecentRecordDto>[];

    for (final MealEntity m in meals) {
      if (m.eatenAt < sevenDaysAgo.millisecondsSinceEpoch) continue;
      recent7d.add(AiRecentRecordDto(
        date: _ymd(DateTime.fromMillisecondsSinceEpoch(m.eatenAt)),
        type: 'meal',
        content: _summarizeMeal(m),
      ));
    }
    for (final PoopEntity p in poops) {
      if (p.pooedAt < sevenDaysAgo.millisecondsSinceEpoch) continue;
      recent7d.add(AiRecentRecordDto(
        date: _ymd(DateTime.fromMillisecondsSinceEpoch(p.pooedAt)),
        type: 'poop',
        content: '${p.form.name} · ${p.color.name}',
      ));
    }
    for (final PeeEntity p in pees) {
      if (p.peedAt < sevenDaysAgo.millisecondsSinceEpoch) continue;
      recent7d.add(AiRecentRecordDto(
        date: _ymd(DateTime.fromMillisecondsSinceEpoch(p.peedAt)),
        type: 'pee',
        content: '${p.color.name} ${p.count}x',
      ));
    }
    for (final VomitEntity v in vomits) {
      if (v.vomitedAt < sevenDaysAgo.millisecondsSinceEpoch) continue;
      final String c = v.color == VomitColor.other
          ? (v.colorOtherText ?? 'other')
          : v.color.name;
      recent7d.add(AiRecentRecordDto(
        date: _ymd(DateTime.fromMillisecondsSinceEpoch(v.vomitedAt)),
        type: 'vomit',
        content: '$c ${v.count}x',
      ));
    }
    for (final DiaryEntity d in diaries) {
      if (d.eventAt < sevenDaysAgo.millisecondsSinceEpoch) continue;
      recent7d.add(AiRecentRecordDto(
        date: _ymd(DateTime.fromMillisecondsSinceEpoch(d.eventAt)),
        type: 'diary',
        content: _summarizeDiary(d),
      ));
    }
    for (final VisitEntity v in visits) {
      if (v.visitedAt < sevenDaysAgo.millisecondsSinceEpoch) continue;
      recent7d.add(AiRecentRecordDto(
        date: _ymd(DateTime.fromMillisecondsSinceEpoch(v.visitedAt)),
        type: 'visit',
        content: v.reason,
      ));
    }
    if (latestWeight != null &&
        latestWeight.measuredAt >=
            sevenDaysAgo.millisecondsSinceEpoch) {
      recent7d.add(AiRecentRecordDto(
        date: _ymd(
            DateTime.fromMillisecondsSinceEpoch(latestWeight.measuredAt)),
        type: 'weight',
        content: '${(latestWeight.weightG / 1000).toStringAsFixed(2)} kg',
      ));
    }

    // 古い順にソート (時系列が読みやすい)
    recent7d.sort((a, b) => a.date.compareTo(b.date));

    // ===== 30日サマリ生成 =====
    final String summary30d = _build30dSummary(
      pet: pet,
      meals: meals,
      poops: poops,
      pees: pees,
      vomits: vomits,
      visits: visits,
      vaccinations: vaccinations,
      latestWeight: latestWeight,
      latestTemp: latestTemp,
      thirtyDaysAgo: thirtyDaysAgo,
    );

    // ===== Pet 情報を組み立て =====
    final double? ageYears = pet.birthday == null
        ? null
        : _yearsBetween(
            DateTime.fromMillisecondsSinceEpoch(pet.birthday!), now);

    final double? idealWeightKg = pet.idealWeightMinG == null
        ? null
        : (pet.idealWeightMinG! / 1000.0);

    return AiPetContextDto(
      name: pet.name,
      type: pet.type == PetType.dog ? 'dog' : 'cat',
      breed: pet.breed,
      ageYears: ageYears,
      idealWeightKg: idealWeightKg,
      summary30d: summary30d,
      recent7dRecords: recent7d,
    );
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  static String _ymd(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
  }

  static double _yearsBetween(DateTime birth, DateTime now) {
    final Duration diff = now.difference(birth);
    return (diff.inDays / 365.25 * 10).round() / 10.0; // 0.1 年単位
  }

  static String _summarizeMeal(MealEntity m) {
    final String name = m.foodNameFreeText ?? 'meal';
    if (m.amountG != null) return '$name ${m.amountG}g';
    return name;
  }

  static String _summarizeDiary(DiaryEntity d) {
    final String t = d.title?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final String first = d.body.trim().split('\n').first;
    return first.length > 60 ? '${first.substring(0, 60)}...' : first;
  }

  static String _build30dSummary({
    required PetEntity pet,
    required List<MealEntity> meals,
    required List<PoopEntity> poops,
    required List<PeeEntity> pees,
    required List<VomitEntity> vomits,
    required List<VisitEntity> visits,
    required List<VaccinationEntity> vaccinations,
    required WeightEntity? latestWeight,
    required TemperatureEntity? latestTemp,
    required DateTime thirtyDaysAgo,
  }) {
    final int from = thirtyDaysAgo.millisecondsSinceEpoch;
    final int mealCount = meals.where((m) => m.eatenAt >= from).length;
    final int poopCount = poops.where((p) => p.pooedAt >= from).length;
    final int peeCount = pees.where((p) => p.peedAt >= from).length;
    final int vomitCount = vomits.where((v) => v.vomitedAt >= from).length;
    final int visitCount = visits.where((v) => v.visitedAt >= from).length;
    final int vaxCount =
        vaccinations.where((v) => v.administeredAt >= from).length;

    final List<String> parts = <String>[];
    parts.add(
        'Records (last 30d): meals=$mealCount, stools=$poopCount, pees=$peeCount, vomits=$vomitCount, visits=$visitCount, vaccinations=$vaxCount');

    if (latestWeight != null) {
      final double kg = latestWeight.weightG / 1000.0;
      parts.add('Latest weight: ${kg.toStringAsFixed(2)} kg');
    }
    if (latestTemp != null) {
      final double c = latestTemp.tempCelsiusX10 / 10.0;
      parts.add('Latest temp: ${c.toStringAsFixed(1)} °C');
    }

    return parts.join('. ');
  }
}
