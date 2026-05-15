// ============================================================================
// petlo - AI Chat Controller
// ============================================================================
//
// メッセージ送信のフロー:
//   1. 入力バリデート (PromptValidator)
//   2. 現在ペットのコンテキスト構築 (PetContextBuilder)
//   3. ローカルDBに user メッセージを楽観的に挿入 (即UI反映)
//   4. AiService.sendMessage() を呼び出し
//   5. assistant メッセージをDBに insert
//   6. セッションがなければ新規作成 (サーバーが返す message_id を使う)
//
// State: AsyncValue<AiChatState>
//   - isSending: 送信中(thinkingドット表示)
//   - errorMessage: エラー表示用
//   - currentSessionId: 今のセッション (継続中はそのまま、なければ新規作成)
//
// ============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/ai_image_preprocessor.dart';
import '../../../core/ai/ai_pet_context.dart';
import '../../../core/ai/ai_service.dart';
import '../../../core/ai/ai_service_exceptions.dart';
import '../../../core/ai/prompt_validator.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../providers/ai_chat_providers.dart';
import '../../providers/ai_service_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/pet_context_builder.dart';
import '../../providers/pro_status_provider.dart';
import '../../providers/scope_providers.dart';

@immutable
class AiChatState {
  const AiChatState({
    this.currentSessionId,
    this.petId,
    this.isSending = false,
    this.errorMessage,
    this.lastErrorReason,
  });

  final String? currentSessionId;
  final int? petId;
  final bool isSending;
  final String? errorMessage;
  final AiChatErrorReason? lastErrorReason;

  AiChatState copyWith({
    Object? currentSessionId = _sentinel,
    Object? petId = _sentinel,
    bool? isSending,
    Object? errorMessage = _sentinel,
    Object? lastErrorReason = _sentinel,
  }) {
    return AiChatState(
      currentSessionId: currentSessionId == _sentinel
          ? this.currentSessionId
          : currentSessionId as String?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      isSending: isSending ?? this.isSending,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
      lastErrorReason: lastErrorReason == _sentinel
          ? this.lastErrorReason
          : lastErrorReason as AiChatErrorReason?,
    );
  }

  static const Object _sentinel = Object();
}

enum AiChatErrorReason {
  validation,
  offline,
  network,
  proRequired,
  quotaExceeded,
  serverError,
  unknown,
  noPet,
}

// ============================================================================
// Provider
// ============================================================================
final NotifierProvider<AiChatController, AiChatState>
    aiChatControllerProvider =
    NotifierProvider<AiChatController, AiChatState>(
  AiChatController.new,
);

class AiChatController extends Notifier<AiChatState> {
  static const Uuid _uuid = Uuid();

  @override
  AiChatState build() {
    return const AiChatState();
  }

  /// 画面表示時にアクティブセッションを初期化
  Future<void> initializeForPet(int petId) async {
    try {
      final repo = ref.read(aiChatRepositoryProvider);
      final AiSessionEntity? active =
          await repo.getActiveSessionForPet(petId);
      state = state.copyWith(
        petId: petId,
        currentSessionId: active?.remoteId,
        errorMessage: null,
        lastErrorReason: null,
      );
    } catch (e, st) {
      PetloLogger.instance.w('initializeForPet failed',
          error: e, stackTrace: st);
    }
  }

  /// メッセージクリア (画面を開き直したい時用、エラーだけリセット)
  void clearError() {
    state = state.copyWith(
      errorMessage: null,
      lastErrorReason: null,
    );
  }

  /// メッセージ送信メイン
  /// build 15: optional [image] を受け取り、リサイズ + Base64 + ローカル保存して送信。
  Future<bool> sendMessage(String input, {File? image}) async {
    if (state.isSending) return false;

    // ===== 1. オフラインチェック =====
    final bool online = ref.read(canUseAiProvider);
    if (!online) {
      state = state.copyWith(
        errorMessage: 'オフラインです。接続を確認してください',
        lastErrorReason: AiChatErrorReason.offline,
      );
      return false;
    }

    // ===== 1.5 Pro 必須チェック =====
    final bool isPro = ref.read(isProProvider);
    if (!isPro) {
      state = state.copyWith(
        errorMessage: 'AI相談は Pro プラン限定です',
        lastErrorReason: AiChatErrorReason.proRequired,
      );
      return false;
    }

    // ===== 1.6 月内利用回数チェック (Pro 月100回) =====
    try {
      final int used =
          await ref.read(currentMonthAiUsageProvider.future);
      if (used >= AppConstants.proAiChatPerMonth) {
        state = state.copyWith(
          errorMessage:
              '今月の利用回数(${AppConstants.proAiChatPerMonth}回)を超えました',
          lastErrorReason: AiChatErrorReason.quotaExceeded,
        );
        return false;
      }
    } catch (e, st) {
      // カウント取得失敗時は通すべきか弾くべきか — 通す方針
      // (ローカルDB障害でユーザー体験を害さない)
      PetloLogger.instance.d(
          'currentMonthAiUsage check failed (allowing send): $e');
    }

    // ===== 2. ペット選択チェック =====
    if (state.petId == null) {
      state = state.copyWith(
        errorMessage: 'ペットを選択してください',
        lastErrorReason: AiChatErrorReason.noPet,
      );
      return false;
    }

    // ===== 3. 入力バリデート =====
    final PromptValidationResult vr = PromptValidator.validate(input);
    if (vr is PromptValidationError) {
      state = state.copyWith(
        errorMessage: vr.message,
        lastErrorReason: AiChatErrorReason.validation,
      );
      return false;
    }
    final String sanitized = (vr as PromptValidationOk).sanitized;

    state = state.copyWith(
      isSending: true,
      errorMessage: null,
      lastErrorReason: null,
    );

    // ===== 4. ペットコンテキスト構築 =====
    AiPetContextDto? petContext;
    try {
      petContext = await PetContextBuilder.buildForCurrentPet(ref);
    } catch (e, st) {
      PetloLogger.instance
          .w('buildForCurrentPet failed', error: e, stackTrace: st);
    }
    if (petContext == null) {
      state = state.copyWith(
        isSending: false,
        errorMessage: 'ペット情報を取得できませんでした',
        lastErrorReason: AiChatErrorReason.noPet,
      );
      return false;
    }

    // ===== 5. セッション確保 =====
    final repo = ref.read(aiChatRepositoryProvider);
    String sessionId = state.currentSessionId ?? _uuid.v4();
    if (state.currentSessionId == null) {
      try {
        await repo.createSession(
          remoteId: sessionId,
          petId: state.petId!,
          groupId: ref.read(currentGroupIdProvider),
        );
        state = state.copyWith(currentSessionId: sessionId);
      } catch (e, st) {
        PetloLogger.instance
            .w('createSession failed', error: e, stackTrace: st);
        // セッション作成に失敗しても送信は試みる(端末ローカルに残らないだけ)
      }
    } else {
      // 継続中: 活動時刻を更新
      await repo.touchSession(sessionId);
    }

    // ===== 5.5 添付画像の前処理 (build 15) =====
    final String userMessageRemoteId = _uuid.v4();
    String? imageBase64;
    String? imageMediaType;
    String? imagePath;
    if (image != null) {
      final processed = await AiImagePreprocessor.processForChat(
        image,
        userMessageRemoteId,
      );
      if (processed != null) {
        imageBase64 = processed.base64;
        imageMediaType = processed.mediaType;
        imagePath = processed.localPath;
      }
    }

    // ===== 6. 楽観的にユーザーメッセージを DB に書き込み =====
    try {
      await repo.addMessage(
        sessionId: sessionId,
        petId: state.petId!,
        role: AiMessageRole.user,
        content: sanitized,
        remoteId: userMessageRemoteId,
        syncStatus: SyncStatus.pending,
        imagePath: imagePath,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('addMessage(user) failed', error: e, stackTrace: st);
      // DB 書き込み失敗でも送信は試みる
    }

    // ===== 7. AI に送信 =====
    final AiService service = ref.read(aiServiceProvider);
    try {
      final AiChatResult result = await service.sendMessage(
        message: sanitized,
        petContext: petContext,
        messageId: userMessageRemoteId,
        imageBase64: imageBase64,
        imageMediaType: imageMediaType,
      );

      // ===== 8. assistant メッセージを DB に保存 =====
      await repo.addMessage(
        sessionId: sessionId,
        petId: state.petId!,
        role: AiMessageRole.assistant,
        content: result.message,
        remoteId: result.messageId,
        syncStatus: SyncStatus.synced,
      );

      state = state.copyWith(isSending: false);
      return true;
    } on AiBadRequestException catch (e) {
      state = state.copyWith(
        isSending: false,
        errorMessage: e.message,
        lastErrorReason: AiChatErrorReason.validation,
      );
      return false;
    } on AiUnauthorizedException catch (e) {
      state = state.copyWith(
        isSending: false,
        errorMessage: e.message,
        lastErrorReason: AiChatErrorReason.unknown,
      );
      return false;
    } on AiProRequiredException catch (e) {
      state = state.copyWith(
        isSending: false,
        errorMessage: e.message,
        lastErrorReason: AiChatErrorReason.proRequired,
      );
      return false;
    } on AiQuotaExceededException catch (e) {
      state = state.copyWith(
        isSending: false,
        errorMessage: e.message,
        lastErrorReason: AiChatErrorReason.quotaExceeded,
      );
      return false;
    } on AiNetworkException {
      state = state.copyWith(
        isSending: false,
        errorMessage: 'ネットワークエラーです。再試行してください',
        lastErrorReason: AiChatErrorReason.network,
      );
      return false;
    } on AiServerException catch (e) {
      state = state.copyWith(
        isSending: false,
        errorMessage: e.message,
        lastErrorReason: AiChatErrorReason.serverError,
      );
      return false;
    } on AiServiceException catch (e) {
      state = state.copyWith(
        isSending: false,
        errorMessage: e.message,
        lastErrorReason: AiChatErrorReason.unknown,
      );
      return false;
    } catch (e, st) {
      PetloLogger.instance
          .w('AI send unexpected error', error: e, stackTrace: st);
      state = state.copyWith(
        isSending: false,
        errorMessage: '予期しないエラーが発生しました',
        lastErrorReason: AiChatErrorReason.unknown,
      );
      return false;
    }
  }

  /// レーティング更新 (👍/👎)
  Future<void> setRating(int messageId, AiFeedback rating) async {
    try {
      await ref
          .read(aiChatRepositoryProvider)
          .setRating(messageId: messageId, rating: rating);
    } catch (e, st) {
      PetloLogger.instance
          .w('setRating failed', error: e, stackTrace: st);
    }
  }
}
