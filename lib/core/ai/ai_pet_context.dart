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
