// ============================================================================
// petlo - AI Tab Screen (build 13)
// ============================================================================
//
// 5番目のタブ「AI相談」。
//   - 無料ユーザー: Pro 訴求のヒーロー + 機能リスト + CTA → Paywall
//   - Pro ユーザー: 同じヒーロー + CTA → AiChatScreen を push
//
// 設計判断: タブをタップした瞬間に AiChatScreen を直接置換する案も検討したが、
// IndexedStack で他タブと並列に存在するため、CTA ボタンで明示的に push する
// 形に統一(画面遷移の予測可能性を重視)。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/pro_status_provider.dart';
import '../../widgets/petlo_scaffold.dart';
import '../paywall/paywall_screen.dart';
import 'ai_chat_screen.dart';

class AiTabScreen extends ConsumerWidget {
  const AiTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isPro = ref.watch(isProProvider);

    final double bottomInset = MediaQuery.of(context).padding.bottom;

    return PetloScaffold(
      showTabBar: false,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          28,
          16,
          28,
          28 + bottomInset + kBottomNavigationBarHeight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // build 16: § ヘッダーを large に変更し、白文字の大型ヒーロー
            // (ai_tab_hero) は削除。説明テキストへ直接続けて落ち着いた構成にする。
            SectionLabel(
              l10n.tab_eyebrow_ai,
              size: EyebrowSize.large,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
            ),

            // ===== 説明 =====
            Text(
              l10n.ai_tab_body,
              style: typo.bodyMedium.copyWith(
                color: colors.fg,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 32),

            // ===== 機能リスト =====
            _Feature(label: l10n.ai_tab_feature_consult),
            _Feature(label: l10n.ai_tab_feature_symptom),
            _Feature(label: l10n.ai_tab_feature_photo),
            _Feature(label: l10n.ai_tab_feature_disclaimer),
            const SizedBox(height: 40),

            // ===== CTA =====
            if (isPro)
              PrimaryButton(
                label: l10n.ai_tab_cta_open,
                onPressed: () => AiChatScreen.push(context),
              )
            else ...<Widget>[
              PrimaryButton(
                label: l10n.ai_tab_cta_upgrade,
                onPressed: () => PaywallScreen.push(context),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.ai_tab_pro_note,
                style: typo.bodySmall.copyWith(color: colors.fgMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(top: 9, right: 12),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: colors.fg,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              label,
              style: typo.bodyMedium.copyWith(
                color: colors.fg,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
