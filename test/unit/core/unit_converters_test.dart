// ============================================================================
// petlo - Unit Converters Tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/utils/unit_converters.dart';
import 'package:petlo/data/local/database_enums.dart';

void main() {
  group('WeightConverter.formatG', () {
    test('5200g formatted as 5.20 in kg (under 10kg shows 2 decimals)', () {
      expect(
        WeightConverter.formatG(weightG: 5200, unit: WeightUnit.kg),
        '5.20',
      );
    });

    test('15500g formatted as 15.5 in kg (10kg+ shows 1 decimal)', () {
      expect(
        WeightConverter.formatG(weightG: 15500, unit: WeightUnit.kg),
        '15.5',
      );
    });

    test('5200g formatted as 11.5 in lb (rounded)', () {
      expect(
        WeightConverter.formatG(weightG: 5200, unit: WeightUnit.lb),
        '11.5',
      );
    });
  });

  group('WeightConverter.parseToG', () {
    test('"5.2 kg" → 5200g', () {
      expect(
        WeightConverter.parseToG(input: '5.2', unit: WeightUnit.kg),
        5200,
      );
    });

    test('"5,2 kg" comma → 5200g', () {
      expect(
        WeightConverter.parseToG(input: '5,2', unit: WeightUnit.kg),
        5200,
      );
    });

    test('"11.5 lb" → 5216g (rounded)', () {
      expect(
        WeightConverter.parseToG(input: '11.5', unit: WeightUnit.lb),
        5216,
      );
    });

    test('empty string returns null', () {
      expect(
        WeightConverter.parseToG(input: '', unit: WeightUnit.kg),
        isNull,
      );
    });

    test('garbage returns null', () {
      expect(
        WeightConverter.parseToG(input: 'abc', unit: WeightUnit.kg),
        isNull,
      );
    });

    test('zero or negative returns null', () {
      expect(
        WeightConverter.parseToG(input: '0', unit: WeightUnit.kg),
        isNull,
      );
      expect(
        WeightConverter.parseToG(input: '-5', unit: WeightUnit.kg),
        isNull,
      );
    });
  });

  group('TemperatureConverter.formatX10', () {
    test('385 (38.5°C) → "38.5" in celsius', () {
      expect(
        TemperatureConverter.formatX10(
          tempCelsiusX10: 385,
          unit: TemperatureUnit.celsius,
        ),
        '38.5',
      );
    });

    test('385 (38.5°C) → "101.3" in fahrenheit', () {
      // 38.5 * 9/5 + 32 = 101.3
      expect(
        TemperatureConverter.formatX10(
          tempCelsiusX10: 385,
          unit: TemperatureUnit.fahrenheit,
        ),
        '101.3',
      );
    });
  });

  group('TemperatureConverter.parseToCelsiusX10', () {
    test('"38.5°C" → 385', () {
      expect(
        TemperatureConverter.parseToCelsiusX10(
          input: '38.5',
          unit: TemperatureUnit.celsius,
        ),
        385,
      );
    });

    test('"101.3°F" → 385 (rounded)', () {
      // (101.3 - 32) * 5/9 = 38.5
      expect(
        TemperatureConverter.parseToCelsiusX10(
          input: '101.3',
          unit: TemperatureUnit.fahrenheit,
        ),
        385,
      );
    });

    test('empty returns null', () {
      expect(
        TemperatureConverter.parseToCelsiusX10(
          input: '',
          unit: TemperatureUnit.celsius,
        ),
        isNull,
      );
    });
  });

  group('TemperatureConverter.statusFor (dog)', () {
    test('38.0°C is normal for dog', () {
      expect(
        TemperatureConverter.statusFor(
          tempCelsiusX10: 380,
          petType: PetType.dog,
        ),
        TemperatureStatus.normal,
      );
    });

    test('37.0°C is cautionLow for dog (37.5 boundary)', () {
      expect(
        TemperatureConverter.statusFor(
          tempCelsiusX10: 370,
          petType: PetType.dog,
        ),
        TemperatureStatus.cautionLow,
      );
    });

    test('39.5°C is cautionHigh for dog', () {
      expect(
        TemperatureConverter.statusFor(
          tempCelsiusX10: 395,
          petType: PetType.dog,
        ),
        TemperatureStatus.cautionHigh,
      );
    });

    test('40.1°C is urgentHigh for dog (>+1°C above 39.0)', () {
      // build 61: production の境界は「max+10 (= 400) より厳密に大きい」。
      // 40.0°C 丁度では cautionHigh 止まり、40.1°C で urgentHigh。
      expect(
        TemperatureConverter.statusFor(
          tempCelsiusX10: 401,
          petType: PetType.dog,
        ),
        TemperatureStatus.urgentHigh,
      );
    });

    test('36.0°C is urgentLow for dog', () {
      expect(
        TemperatureConverter.statusFor(
          tempCelsiusX10: 360,
          petType: PetType.dog,
        ),
        TemperatureStatus.urgentLow,
      );
    });
  });

  group('TemperatureConverter.statusFor (cat)', () {
    test('38.5°C is normal for cat', () {
      expect(
        TemperatureConverter.statusFor(
          tempCelsiusX10: 385,
          petType: PetType.cat,
        ),
        TemperatureStatus.normal,
      );
    });

    test('37.9°C is cautionLow for cat (38.0 boundary)', () {
      expect(
        TemperatureConverter.statusFor(
          tempCelsiusX10: 379,
          petType: PetType.cat,
        ),
        TemperatureStatus.cautionLow,
      );
    });

    test('39.6°C is cautionHigh for cat (39.5 boundary)', () {
      expect(
        TemperatureConverter.statusFor(
          tempCelsiusX10: 396,
          petType: PetType.cat,
        ),
        TemperatureStatus.cautionHigh,
      );
    });
  });

  group('Roundtrip', () {
    test('weight kg roundtrip preserves value', () {
      final int g = WeightConverter.parseToG(
        input: '5.20',
        unit: WeightUnit.kg,
      )!;
      expect(g, 5200);
      final String back = WeightConverter.formatG(
        weightG: g,
        unit: WeightUnit.kg,
      );
      expect(back, '5.20');
    });

    test('temperature C roundtrip preserves value', () {
      final int x10 = TemperatureConverter.parseToCelsiusX10(
        input: '38.5',
        unit: TemperatureUnit.celsius,
      )!;
      expect(x10, 385);
      final String back = TemperatureConverter.formatX10(
        tempCelsiusX10: x10,
        unit: TemperatureUnit.celsius,
      );
      expect(back, '38.5');
    });
  });
}
