// ============================================================================
// petlo - Drift Type Converters
// ============================================================================
//
// driftテーブルでDart側のenum/型をDB側の型に変換するヘルパー。
//
// 設計方針:
//   - enum はすべて String (name) で保存
//   - DateTime は UTC ミリ秒 INTEGER で保存(タイムゾーン処理は表示時に行う)
//   - List/Map は JSON 文字列で保存
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import 'database_enums.dart';

// ============================================================================
// Enum Converters
// ============================================================================

/// 任意のenumをDB上のString(name)と変換する汎用Converter。
///
/// 使い方:
/// ```dart
/// TextColumn get sex => text().map(const AppEnumConverter(PetSex.values))();
/// ```
///
/// drift 公式の `EnumNameConverter` と名前が衝突するため、
/// petlo では `AppEnumConverter` という名前で提供する。
class AppEnumConverter<T extends Enum> extends TypeConverter<T, String>
    with JsonTypeConverter<T, String> {
  const AppEnumConverter(this._values);

  final List<T> _values;

  @override
  T fromSql(String fromDb) {
    return _values.firstWhere(
      (T v) => v.name == fromDb,
      orElse: () => throw FormatException('Unknown enum value: $fromDb'),
    );
  }

  @override
  String toSql(T value) => value.name;

  @override
  T fromJson(String json) => fromSql(json);

  @override
  String toJson(T value) => toSql(value);
}

/// nullable版
class NullableAppEnumConverter<T extends Enum> extends TypeConverter<T?, String?>
    with JsonTypeConverter<T?, String?> {
  const NullableAppEnumConverter(this._values);

  final List<T> _values;

  @override
  T? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    return _values.firstWhere(
      (T v) => v.name == fromDb,
      orElse: () => throw FormatException('Unknown enum value: $fromDb'),
    );
  }

  @override
  String? toSql(T? value) => value?.name;

  @override
  T? fromJson(String? json) => fromSql(json);

  @override
  String? toJson(T? value) => toSql(value);
}

// ============================================================================
// JSON Converter (List/Map)
// ============================================================================

/// List<String>をJSON文字列で保存する。
/// 用途: アレルギー一覧、持病一覧など
class StringListConverter extends TypeConverter<List<String>, String>
    with JsonTypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return <String>[];
    final List<dynamic> decoded = jsonDecode(fromDb) as List<dynamic>;
    return decoded.cast<String>();
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);

  @override
  List<String> fromJson(String json) => fromSql(json);

  @override
  String toJson(List<String> value) => toSql(value);
}

/// nullable版
class NullableStringListConverter extends TypeConverter<List<String>?, String?>
    with JsonTypeConverter<List<String>?, String?> {
  const NullableStringListConverter();

  @override
  List<String>? fromSql(String? fromDb) {
    if (fromDb == null || fromDb.isEmpty) return null;
    final List<dynamic> decoded = jsonDecode(fromDb) as List<dynamic>;
    return decoded.cast<String>();
  }

  @override
  String? toSql(List<String>? value) => value == null ? null : jsonEncode(value);

  @override
  List<String>? fromJson(String? json) => fromSql(json);

  @override
  String? toJson(List<String>? value) => toSql(value);
}

/// Map<String, dynamic>をJSON文字列で保存する。
/// 用途: AIメッセージのメタ情報、各種設定など
class JsonMapConverter extends TypeConverter<Map<String, dynamic>, String>
    with JsonTypeConverter<Map<String, dynamic>, String> {
  const JsonMapConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    if (fromDb.isEmpty) return <String, dynamic>{};
    return jsonDecode(fromDb) as Map<String, dynamic>;
  }

  @override
  String toSql(Map<String, dynamic> value) => jsonEncode(value);

  @override
  Map<String, dynamic> fromJson(String json) => fromSql(json);

  @override
  String toJson(Map<String, dynamic> value) => toSql(value);
}

// ============================================================================
// Specialized: 曜日選択 (週次リマインダー用)
// ============================================================================

/// 曜日のbitフラグセット ⇔ Set<int>
/// 0=日曜, 1=月曜 ... 6=土曜
/// 例: {1, 3, 5} → 月水金 → 0b0101010 = 42
class WeekdaysBitsetConverter extends TypeConverter<Set<int>, int>
    with JsonTypeConverter<Set<int>, int> {
  const WeekdaysBitsetConverter();

  @override
  Set<int> fromSql(int fromDb) {
    final Set<int> result = <int>{};
    for (int i = 0; i < 7; i++) {
      if ((fromDb & (1 << i)) != 0) {
        result.add(i);
      }
    }
    return result;
  }

  @override
  int toSql(Set<int> value) {
    int bits = 0;
    for (final int day in value) {
      if (day < 0 || day > 6) {
        throw ArgumentError('Weekday must be 0-6, got $day');
      }
      bits |= 1 << day;
    }
    return bits;
  }

  @override
  Set<int> fromJson(int json) => fromSql(json);

  @override
  int toJson(Set<int> value) => toSql(value);
}

// ============================================================================
// 時刻リスト (1日複数回リマインダー)
// ============================================================================

/// 1日の中の複数時刻 (HH:mm 形式) を保存する。
/// 用途: 朝7:00, 夜21:00 のような複数回投薬リマインダー
/// 形式: ["07:00", "21:00"]
class TimeOfDayListConverter extends TypeConverter<List<String>, String>
    with JsonTypeConverter<List<String>, String> {
  const TimeOfDayListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return <String>[];
    return (jsonDecode(fromDb) as List<dynamic>).cast<String>();
  }

  @override
  String toSql(List<String> value) {
    // バリデーション: HH:mm形式
    for (final String t in value) {
      if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(t)) {
        throw ArgumentError('Time must be in HH:mm format, got $t');
      }
    }
    return jsonEncode(value);
  }

  @override
  List<String> fromJson(String json) => fromSql(json);

  @override
  String toJson(List<String> value) => toSql(value);
}
