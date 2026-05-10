// ============================================================================
// petlo - Unit Converters
// ============================================================================
//
// 体重・体温の単位変換ユーティリティ。
//
// 内部表現:
//   - 体重: グラム単位の int (例: 5.2kg → 5200)
//   - 体温: 摂氏×10 の int (例: 38.5°C → 385)
//
// UI での表示:
//   - 体重: kg(国際) / lb(米国) を切替
//   - 体温: °C(国際) / °F(米国) を切替
//
// ============================================================================

import '../../data/local/database_enums.dart';

abstract final class WeightConverter {
  WeightConverter._();

  /// グラム → 表示用文字列
  static String formatG({required int weightG, required WeightUnit unit}) {
    switch (unit) {
      case WeightUnit.kg:
        // 5200 → "5.2"
        final double kg = weightG / 1000.0;
        if (kg < 10) {
          return kg.toStringAsFixed(2); // 10kg未満は小数2桁(動物の細かい変化)
        }
        return kg.toStringAsFixed(1);
      case WeightUnit.lb:
        // 5200g → 11.46lb
        final double lb = weightG / 453.592;
        return lb.toStringAsFixed(1);
    }
  }

  /// 表示用入力 → グラム (失敗時は null)
  static int? parseToG({required String input, required WeightUnit unit}) {
    final double? n = double.tryParse(input.replaceAll(',', '.'));
    if (n == null || n <= 0) return null;
    switch (unit) {
      case WeightUnit.kg:
        return (n * 1000).round();
      case WeightUnit.lb:
        return (n * 453.592).round();
    }
  }

  /// 単位ラベル
  static String label(WeightUnit unit) {
    switch (unit) {
      case WeightUnit.kg:
        return 'kg';
      case WeightUnit.lb:
        return 'lb';
    }
  }
}

abstract final class TemperatureConverter {
  TemperatureConverter._();

  /// 摂氏×10 → 表示用文字列
  static String formatX10({
    required int tempCelsiusX10,
    required TemperatureUnit unit,
  }) {
    switch (unit) {
      case TemperatureUnit.celsius:
        // 385 → "38.5"
        return (tempCelsiusX10 / 10).toStringAsFixed(1);
      case TemperatureUnit.fahrenheit:
        // C → F: F = C * 9/5 + 32
        final double c = tempCelsiusX10 / 10.0;
        final double f = c * 9 / 5 + 32;
        return f.toStringAsFixed(1);
    }
  }

  /// 表示用入力 → 摂氏×10 (失敗時は null)
  static int? parseToCelsiusX10({
    required String input,
    required TemperatureUnit unit,
  }) {
    final double? n = double.tryParse(input.replaceAll(',', '.'));
    if (n == null) return null;
    switch (unit) {
      case TemperatureUnit.celsius:
        return (n * 10).round();
      case TemperatureUnit.fahrenheit:
        // F → C: C = (F - 32) * 5/9
        final double c = (n - 32) * 5 / 9;
        return (c * 10).round();
    }
  }

  static String label(TemperatureUnit unit) {
    switch (unit) {
      case TemperatureUnit.celsius:
        return '°C';
      case TemperatureUnit.fahrenheit:
        return '°F';
    }
  }

  /// 体温の正常範囲を判定
  static TemperatureStatus statusFor({
    required int tempCelsiusX10,
    required PetType petType,
  }) {
    // 犬: 37.5-39.0°C, 猫: 38.0-39.5°C
    final (int min, int max) = petType == PetType.dog
        ? (375, 390)
        : (380, 395);

    if (tempCelsiusX10 < min - 10) return TemperatureStatus.urgentLow; // 1°C以上低い
    if (tempCelsiusX10 > max + 10) return TemperatureStatus.urgentHigh; // 1°C以上高い
    if (tempCelsiusX10 < min) return TemperatureStatus.cautionLow;
    if (tempCelsiusX10 > max) return TemperatureStatus.cautionHigh;
    return TemperatureStatus.normal;
  }
}

enum TemperatureStatus {
  normal,
  cautionLow,
  cautionHigh,
  urgentLow,
  urgentHigh,
}
