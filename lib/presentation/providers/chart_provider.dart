// ============================================================================
// petlo - Chart Provider
// ============================================================================
//
// 体重・体温の推移グラフ用 Provider (期間切替対応)。
//
// rev3 F-06/F-07: 体重・体温の推移グラフ
//
// 設計:
//   - ChartRange family parameter で期間指定
//   - all の場合は petId だけで watchForPet(全件)を購読
//   - それ以外は watchInRange(from, now)
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/models/chart_range.dart';
import 'scope_providers.dart';
import 'temperatures_providers.dart';
import 'weights_providers.dart';

/// 体重履歴(指定期間、古い順 / グラフ用)
final StreamProviderFamily<List<WeightEntity>, ChartRange>
    weightChartProvider =
    StreamProviderFamily<List<WeightEntity>, ChartRange>(
  (Ref ref, ChartRange range) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<WeightEntity>>.value(<WeightEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<WeightEntity>>.value(<WeightEntity>[]);
    }

    final repo = ref.watch(weightsRepositoryProvider);

    final DateTime? from = range.fromDate();
    if (from == null) {
      // ALL: 全件 (古い順は呼び出し側で sort)
      return repo.watchForPet(petId).map(
            (List<WeightEntity> list) => List<WeightEntity>.from(list)
              ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt)),
          );
    }

    final int fromMsec = from.toUtc().millisecondsSinceEpoch;
    final int toMsec = DateTime.now().toUtc().millisecondsSinceEpoch;
    return repo.watchInRange(
        petId: petId, fromMsec: fromMsec, toMsec: toMsec);
  },
);

/// 体温履歴(指定期間、古い順 / グラフ用)
final StreamProviderFamily<List<TemperatureEntity>, ChartRange>
    temperatureChartProvider =
    StreamProviderFamily<List<TemperatureEntity>, ChartRange>(
  (Ref ref, ChartRange range) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<TemperatureEntity>>.value(<TemperatureEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<TemperatureEntity>>.value(<TemperatureEntity>[]);
    }

    final repo = ref.watch(temperaturesRepositoryProvider);

    final DateTime? from = range.fromDate();
    if (from == null) {
      return repo.watchForPet(petId).map(
            (List<TemperatureEntity> list) =>
                List<TemperatureEntity>.from(list)
                  ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt)),
          );
    }

    final int fromMsec = from.toUtc().millisecondsSinceEpoch;
    final int toMsec = DateTime.now().toUtc().millisecondsSinceEpoch;
    return repo.watchInRange(
        petId: petId, fromMsec: fromMsec, toMsec: toMsec);
  },
);
