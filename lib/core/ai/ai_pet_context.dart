// ============================================================================
// petlo - AI Pet Context
// ============================================================================
//
// AI 相談時にサーバーへ送るペットコンテキスト。
// API側 (petlo-api/src/types.ts) の PetContext と同じ構造。
//
// ============================================================================

import 'package:flutter/foundation.dart';

@immutable
class AiPetContextDto {
  const AiPetContextDto({
    required this.name,
    required this.type,
    this.breed,
    this.ageYears,
    this.idealWeightKg,
    required this.summary30d,
    required this.recent7dRecords,
    this.preventions = const <AiPreventionDto>[],
  });

  final String name;
  /// 'dog' or 'cat'
  final String type;
  final String? breed;
  final double? ageYears;
  final double? idealWeightKg;

  /// 過去30日サマリー(自然言語1〜2行)
  final String summary30d;

  /// 直近7日の構造化記録
  final List<AiRecentRecordDto> recent7dRecords;

  /// 進行中の予防コース (build 73)。今シーズンのぶんのみ。
  final List<AiPreventionDto> preventions;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'pet': <String, dynamic>{
          'name': name,
          'type': type,
          if (breed != null) 'breed': breed,
          if (ageYears != null) 'age_years': ageYears,
          if (idealWeightKg != null) 'ideal_weight_kg': idealWeightKg,
        },
        'summary_30d': summary30d,
        'recent_7d_records':
            recent7dRecords.map((r) => r.toJson()).toList(),
        if (preventions.isNotEmpty)
          'preventions': preventions.map((AiPreventionDto p) => p.toJson())
              .toList(),
      };
}

/// 予防コースの要約 (build 73 / v2 §6.2)。
///
/// `medications` を経由せず `prevention_doses` を直接読んだ結果を載せる。
///
/// **事実の列挙に留めること。** 投薬の要否や時期の判断を AI に語らせない
/// (§9.2)。ここに載るのは「記録上こうなっている」という状態だけである。
@immutable
class AiPreventionDto {
  const AiPreventionDto({
    required this.kind,
    required this.year,
    required this.doneCount,
    required this.totalCount,
    required this.hasOverdue,
    required this.tested,
    this.nextDueDate,
  });

  /// 'filaria' / 'flea_tick' / 'combo'
  final String kind;
  final int year;

  /// 投与済みの回数
  final int doneCount;

  /// シーズン全体の回数
  final int totalCount;

  /// 予定日を過ぎた未投与・未スキップの回が存在するか
  final bool hasOverdue;

  /// シーズン前検査の実施記録があるか
  final bool tested;

  /// 次回予定日 (YYYY-MM-DD)。未投与の回が無ければ null
  final String? nextDueDate;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'year': year,
        'done_count': doneCount,
        'total_count': totalCount,
        'has_overdue': hasOverdue,
        'tested': tested,
        if (nextDueDate != null) 'next_due_date': nextDueDate,
      };
}

@immutable
class AiRecentRecordDto {
  const AiRecentRecordDto({
    required this.date,
    required this.type,
    required this.content,
  });

  /// YYYY-MM-DD
  final String date;

  /// 'meal' / 'poop' / 'pee' / 'weight' / 'diary' / 'visit' / 'medication'
  final String type;
  final String content;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': date,
        'type': type,
        'content': content,
      };
}
