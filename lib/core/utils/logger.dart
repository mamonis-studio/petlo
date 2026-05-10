// ============================================================================
// petlo - Logger
// ============================================================================
//
// アプリ全体で統一されたロガー。
// 開発時は詳細ログ、本番ではエラーのみ。
//
// 使い方:
//   PetloLogger.instance.i('Info message');
//   PetloLogger.instance.w('Warning message');
//   PetloLogger.instance.e('Error', error: e, stackTrace: st);
//
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class PetloLogger {
  PetloLogger._();

  static late final Logger _logger;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _logger = Logger(
      printer: kDebugMode
          ? PrettyPrinter(
              methodCount: 2,
              errorMethodCount: 8,
              lineLength: 120,
              colors: true,
              printEmojis: false,  // rev5: 絵文字使用禁止
              dateTimeFormat: DateTimeFormat.onlyTime,
            )
          : SimplePrinter(
              colors: false,
              printTime: true,
            ),
      level: kDebugMode ? Level.trace : Level.warning,
    );

    _initialized = true;
  }

  static Logger get instance {
    if (!_initialized) {
      throw StateError(
        'PetloLogger.initialize() must be called before accessing instance',
      );
    }
    return _logger;
  }
}
