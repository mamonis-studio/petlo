// ============================================================================
// petlo - AI Chat Screen
// ============================================================================
//
// AI 相談チャット画面。More タブから push される。
//
// レイアウト:
//   - AppBar: PET CONSULT (中央)
//   - メッセージリスト (ChronologicalListView、新着で auto-scroll)
//   - 送信中: thinking ドット
//   - 入力ボックス (500字カウンター、送信ボタン)
//   - エラーバナー (上部にfloating)
//
// rev3 F-18, rev5.5 F-23a/b/c
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/prompt_validator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../providers/ai_chat_providers.dart';
import '../../providers/ai_service_provider.dart';
import '../../providers/scope_providers.dart';
import '../paywall/paywall_screen.dart';
import 'ai_chat_controller.dart';
import 'widgets/chat_system_message.dart';
import 'widgets/message_bubble.dart';
import 'widgets/thinking_dots.dart';

/// proRequired / quotaExceeded のエラーで Paywall ボタンを出すか判定
bool _shouldShowPaywall(AiChatErrorReason? reason) {
  return reason == AiChatErrorReason.proRequired ||
      reason == AiChatErrorReason.quotaExceeded;
}

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const AiChatScreen(),
      ),
    );
  }

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  late final TextEditingController _inputC;
  late final ScrollController _scrollC;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _inputC = TextEditingController();
    _scrollC = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeInit());
  }

  void _maybeInit() {
    if (_initialized) return;
    final String? petIdStr = ref.read(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) return;
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) return;
    _initialized = true;
    ref.read(aiChatControllerProvider.notifier).initializeForPet(petId);
  }

  @override
  void dispose() {
    _inputC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollC.hasClients) return;
    _scrollC.animateTo(
      _scrollC.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _onSend() async {
    final String text = _inputC.text;
    if (text.trim().isEmpty) return;
    final bool ok =
        await ref.read(aiChatControllerProvider.notifier).sendMessage(text);
    if (ok) {
      _inputC.clear();
      // メッセージ反映後にスクロール (1フレーム待つ)
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AiChatState chatState = ref.watch(aiChatControllerProvider);
    final bool canUseAi = ref.watch(canUseAiProvider);

    final String? sessionId = chatState.currentSessionId;
    final AsyncValue<List<AiChatMessageEntity>> messagesAsync =
        sessionId == null
            ? const AsyncValue<List<AiChatMessageEntity>>.data(<AiChatMessageEntity>[])
            : ref.watch(messagesForSessionProvider(sessionId));

    // メッセージ数の変化で auto-scroll
    ref.listen<AsyncValue<List<AiChatMessageEntity>>>(
      sessionId == null
          ? messagesForSessionProvider('__none__')
          : messagesForSessionProvider(sessionId),
      (AsyncValue<List<AiChatMessageEntity>>? prev,
          AsyncValue<List<AiChatMessageEntity>> next) {
        next.whenData((List<AiChatMessageEntity> list) {
          if (list.isNotEmpty) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _scrollToBottom());
          }
        });
      },
    );

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          AppLocalizations.of(context).ai_chat_app_bar,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.fg),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // ===== メッセージ領域 =====
            Expanded(
              child: messagesAsync.when(
                data: (List<AiChatMessageEntity> list) {
                  if (list.isEmpty &&
                      !chatState.isSending &&
                      chatState.lastErrorReason == null) {
                    return _EmptyState(colors: colors, typo: typo);
                  }
                  // 送信中 + 末尾エラーシステムメッセージ用に件数調整
                  final int trailing =
                      (chatState.isSending ? 1 : 0) +
                          (chatState.lastErrorReason != null ? 1 : 0);
                  return ListView.builder(
                    controller: _scrollC,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    itemCount: list.length + trailing,
                    itemBuilder: (BuildContext c, int i) {
                      if (i < list.length) {
                        final AiChatMessageEntity m = list[i];
                        return MessageBubble(
                          message: m,
                          onRate: m.role == AiMessageRole.assistant
                              ? (AiFeedback r) => ref
                                  .read(aiChatControllerProvider.notifier)
                                  .setRating(m.id, r)
                              : null,
                        );
                      }
                      final int tailIdx = i - list.length;
                      if (chatState.isSending && tailIdx == 0) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: ThinkingDots(),
                        );
                      }
                      // エラー時のシステムメッセージ
                      final AiChatErrorReason reason =
                          chatState.lastErrorReason!;
                      final bool showPaywallAction =
                          _shouldShowPaywall(reason);
                      return ChatSystemMessage(
                        message: systemMessageForReason(
                          AppLocalizations.of(context),
                          reason,
                        ),
                        actionLabel: showPaywallAction
                            ? AppLocalizations.of(context)
                                .more_pro_view_plans
                            : null,
                        onAction: showPaywallAction
                            ? () => PaywallScreen.push(context)
                            : null,
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
                error: (Object e, _) => Center(
                  child: Text(
                    AppLocalizations.of(context).common_load_failed,
                    style: typo.bodySmall.copyWith(color: colors.fgMuted),
                  ),
                ),
              ),
            ),

            // ===== 入力エリア =====
            _InputArea(
              controller: _inputC,
              onSend: _onSend,
              isSending: chatState.isSending,
              canUseAi: canUseAi,
              colors: colors,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// EmptyState
// ============================================================================
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          EyebrowText(AppLocalizations.of(context).section_ask_anything),
          const SizedBox(height: 8),
          Text(
            'Pet consult,\non call.',
            style: typo.heroName.copyWith(height: 0.95),
          ),
          const SizedBox(height: 16),
          Text(
            'うちの子の様子で気になることを\nAIに相談してみてください。\n\n直近7日の記録 + 30日サマリーを文脈として、\n獣医師に行く前のセルフチェックの参考に。',
            style: typo.bodyMedium.copyWith(
              color: colors.fgMuted,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: colors.line, width: 1),
            ),
            child: Text(
              'NOTE\n気になる症状は獣医師にご相談ください。\nAIの返答は参考情報であり、診断ではありません。',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 10 * 0.1,
                height: 1.6,
                color: colors.fgMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// InputArea - 入力ボックス + 500字カウンター + 送信ボタン
// ============================================================================
class _InputArea extends StatefulWidget {
  const _InputArea({
    required this.controller,
    required this.onSend,
    required this.isSending,
    required this.canUseAi,
    required this.colors,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isSending;
  final bool canUseAi;
  final AppColors colors;

  @override
  State<_InputArea> createState() => _InputAreaState();
}

class _InputAreaState extends State<_InputArea> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final AppColors colors = widget.colors;
    final PromptLengthInfo info =
        PromptLengthInfo(widget.controller.text);
    final bool canSend = !widget.isSending &&
        widget.canUseAi &&
        widget.controller.text.trim().isNotEmpty &&
        !info.isOver;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line, width: 1)),
        color: colors.bg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // オフラインバナー (F-23c)
          if (!widget.canUseAi)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'OFFLINE — メッセージは送信できません',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 9,
                  letterSpacing: 9 * 0.18,
                  color: colors.fgMuted,
                ),
              ),
            ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  enabled: widget.canUseAi && !widget.isSending,
                  maxLines: 5,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    height: 1.5,
                    color: colors.fg,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.canUseAi
                        ? 'うちの子のことを聞く...'
                        : 'オフライン中',
                    hintStyle: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      color: colors.fgFaint,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: info.isOver
                            ? colors.accentDanger
                            : colors.line,
                      ),
                      borderRadius: BorderRadius.zero,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: info.isOver
                            ? colors.accentDanger
                            : colors.line,
                      ),
                      borderRadius: BorderRadius.zero,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: info.isOver
                            ? colors.accentDanger
                            : colors.fg,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(
                enabled: canSend,
                onTap: widget.onSend,
                colors: colors,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 文字数カウンター
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${info.current} / ${info.max}',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 9,
                letterSpacing: 9 * 0.15,
                color: info.isOver
                    ? colors.accentDanger
                    : (info.isNearLimit
                        ? colors.accentWarn
                        : colors.fgFaint),
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.onTap,
    required this.colors,
  });

  final bool enabled;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Send',
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? colors.fg : colors.bgSoft,
            border: Border.all(
              color: enabled ? colors.fg : colors.line,
              width: 1,
            ),
          ),
          child: CustomPaint(
            size: const Size(18, 18),
            painter: _SendArrowPainter(
              color: enabled ? colors.bg : colors.fgFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _SendArrowPainter extends CustomPainter {
  _SendArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double w = size.width;
    final double h = size.height;
    final Path p = Path()
      // 横棒
      ..moveTo(w * 0.15, h * 0.5)
      ..lineTo(w * 0.82, h * 0.5)
      // 矢じり
      ..moveTo(w * 0.55, h * 0.22)
      ..lineTo(w * 0.85, h * 0.5)
      ..lineTo(w * 0.55, h * 0.78);
    canvas.drawPath(p, stroke);
  }

  @override
  bool shouldRepaint(covariant _SendArrowPainter old) => old.color != color;
}
