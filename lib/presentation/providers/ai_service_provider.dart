// ============================================================================
// petlo - AI Service Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_service.dart';
import 'connectivity_provider.dart';

// ============================================================================
// Service singleton
// ============================================================================
final Provider<AiService> aiServiceProvider = Provider<AiService>(
  (Ref ref) => AiService(),
);

// ============================================================================
// AI 機能が今使えるか
// オンラインかつ Pro なら true (今は Pro判定無いので一旦 online のみ)
// rev5.5 F-23c: オフライン時の AI ボタン薄化に使う
// ============================================================================
final Provider<bool> canUseAiProvider = Provider<bool>(
  (Ref ref) {
    final AsyncValue<bool> online = ref.watch(isOnlineProvider);
    return online.maybeWhen(
      data: (bool v) => v,
      orElse: () => false,
    );
  },
);
