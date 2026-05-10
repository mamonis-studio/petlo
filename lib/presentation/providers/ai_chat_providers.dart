// ============================================================================
// petlo - AI Chat Providers
// ============================================================================
//
// AI相談チャット用 Provider 群。
//
// rev3 F-18 / F-22
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/ai_chat_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

// ============================================================================
// Repository
// ============================================================================
final Provider<AiChatRepository> aiChatRepositoryProvider =
    Provider<AiChatRepository>(
  (Ref ref) => AiChatRepository(ref.watch(appDatabaseProvider)),
);

// ============================================================================
// セッション
// ============================================================================

/// 現在ペットのアクティブセッション (Future、画面表示時に1回引く)
final FutureProviderFamily<AiSessionEntity?, int> activeSessionForPetProvider =
    FutureProviderFamily<AiSessionEntity?, int>(
  (Ref ref, int petId) =>
      ref.watch(aiChatRepositoryProvider).getActiveSessionForPet(petId),
);

// ============================================================================
// メッセージ
// ============================================================================

/// 指定セッションのメッセージ (Stream、ChatScreenで使う)
final StreamProviderFamily<List<AiChatMessageEntity>, String>
    messagesForSessionProvider =
    StreamProviderFamily<List<AiChatMessageEntity>, String>(
  (Ref ref, String sessionId) =>
      ref.watch(aiChatRepositoryProvider).watchMessagesForSession(sessionId),
);

// ============================================================================
// 月内利用回数 (Pro 月100回制限の判定用)
// ============================================================================
final FutureProvider<int> currentMonthAiUsageProvider = FutureProvider<int>(
  (Ref ref) async {
    final String groupId = ref.watch(currentGroupIdProvider);
    final DateTime now = DateTime.now();
    return ref.watch(aiChatRepositoryProvider).countUserMessagesInMonth(
          groupId: groupId,
          year: now.year,
          month: now.month,
        );
  },
);
