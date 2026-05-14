// ============================================================================
// petlo - Chat System Message (build 14)
// ============================================================================
//
// AI チャット内に表示するシステムメッセージ用バブル。
// 左寄せ、bgSoft 背景、ミュート色のテキスト。エラー時の優しいフォールバック
// メッセージを Anthropic 応答の代わりにチャット流れの中に挿入する。
//
// Pro 訴求が必要なエラー(proRequired / quotaExceeded)はバブル右下に
// 小さな「プランを見る」リンクを出す。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../ai_chat_controller.dart';

/// AiChatErrorReason → ローカライズされたシステムメッセージ文。
String systemMessageForReason(
  AppLocalizations l10n,
  AiChatErrorReason reason,
) {
  switch (reason) {
    case AiChatErrorReason.offline:
      return l10n.ai_chat_system_offline;
    case AiChatErrorReason.network:
      return l10n.ai_chat_system_network;
    case AiChatErrorReason.proRequired:
      return l10n.ai_chat_system_pro_required;
    case AiChatErrorReason.quotaExceeded:
      return l10n.ai_chat_system_quota;
    case AiChatErrorReason.noPet:
      return l10n.ai_chat_system_no_pet;
    case AiChatErrorReason.validation:
      return l10n.ai_chat_system_topic;
    case AiChatErrorReason.serverError:
    case AiChatErrorReason.unknown:
      return l10n.ai_chat_system_unknown;
  }
}

class ChatSystemMessage extends StatelessWidget {
  const ChatSystemMessage({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.bgSoft,
                border: Border.all(color: colors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    message,
                    style: typo.bodyMedium.copyWith(
                      color: colors.fg,
                      height: 1.6,
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...<Widget>[
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: onAction,
                      child: Text(
                        actionLabel!,
                        style: typo.bodySmall.copyWith(
                          color: colors.fg,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 右側にスペースを取って吹き出しを左寄せに
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}
