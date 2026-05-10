// ============================================================================
// petlo - Paywall Screen
// ============================================================================
//
// Pro プランの紹介と購入フロー。
//
// レイアウト (エディトリアル風):
//   - ヒーロー: "petlo Pro." 巨大 Fraunces italic
//   - サブコピー: 機能の本質を1行で
//   - 機能リスト: 無制限記録 / AI / 家族共有 / 全期間グラフ
//   - プラン選択カード x2 (月額 / 年額) — 年額がデフォルト推奨
//   - メイン CTA ボタン "Start 7-day trial"
//   - Restore Purchases / Terms of use / Privacy policy リンク
//
// rev3 + App Store / Play Store 要件:
//   - Restore ボタン必須
//   - Terms / Privacy リンク必須
//   - 自動更新の旨を明示
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/billing/pro_status.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/section_label.dart';
import '../../providers/pro_status_provider.dart';
import '../../providers/purchase_provider.dart';
import 'paywall_controller.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PaywallScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final PaywallState pState = ref.watch(paywallControllerProvider);
    final PaywallController controller =
        ref.read(paywallControllerProvider.notifier);

    // ===== 購入完了で自動 pop =====
    ref.listen(purchaseSuccessStreamProvider, (_, AsyncValue next) {
      next.whenData((_) {
        controller.markCompleted();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).paywall_pro_welcome_snackbar),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pop();
        }
      });
    });

    // ===== 購入エラー時に SnackBar =====
    ref.listen(purchaseErrorStreamProvider, (_, AsyncValue next) {
      next.whenData((dynamic err) {
        controller.markCompleted();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err.message as String),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    });

    // ===== 既に Pro なら表示しない (保険) =====
    final bool isAlreadyPro = ref.watch(isProProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          AppLocalizations.of(context).appbar_petlo_pro,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.close, color: colors.fg),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: isAlreadyPro
            ? _AlreadyProState(colors: colors, typo: typo)
            : _PaywallBody(
                pState: pState,
                controller: controller,
                colors: colors,
                typo: typo,
              ),
      ),
    );
  }
}

// ============================================================================
// 既に Pro 状態
// ============================================================================
class _AlreadyProState extends ConsumerWidget {
  const _AlreadyProState({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProStatus status = ref.watch(proStatusProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          EyebrowText(AppLocalizations.of(context).paywall_pro_active_eyebrow),
          const SizedBox(height: 8),
          Text(
            'You\'re\nin.',
            style: typo.heroName.copyWith(height: 0.95),
          ),
          const SizedBox(height: 24),
          Text(
            'プラン: ${_tierLabel(status.tier)}\n状態: ${_stateLabel(status.state)}',
            style: typo.bodyLarge.copyWith(color: colors.fgMuted),
          ),
          if (status.expiresAt != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '次回更新: ${_formatDate(status.expiresAt!)}',
              style: typo.bodySmall.copyWith(color: colors.fgMuted),
            ),
          ],
        ],
      ),
    );
  }

  String _tierLabel(ProTier t) {
    switch (t) {
      case ProTier.monthly:
        return '月額';
      case ProTier.yearly:
        return '年額';
      case ProTier.free:
        return '—';
    }
  }

  String _stateLabel(ProState s) {
    switch (s) {
      case ProState.active:
        return 'アクティブ';
      case ProState.grace:
        return '猶予期間中';
      case ProState.cancelled:
        return '解約済み(期限まで利用可)';
      case ProState.free:
        return '無料';
    }
  }

  String _formatDate(DateTime d) {
    return '${d.year}年${d.month}月${d.day}日';
  }
}

// ============================================================================
// Paywall本体
// ============================================================================
class _PaywallBody extends StatelessWidget {
  const _PaywallBody({
    required this.pState,
    required this.controller,
    required this.colors,
    required this.typo,
  });

  final PaywallState pState;
  final PaywallController controller;
  final AppColors colors;
  final AppTypography typo;

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).paywall_link_open_failed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to open url', error: e, stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ===== ヒーロー =====
          EyebrowText(AppLocalizations.of(context).paywall_unlock_eyebrow),
          const SizedBox(height: 8),
          Text(
            'petlo\nPro.',
            style: typo.heroName.copyWith(height: 0.92),
          ),
          const SizedBox(height: 16),
          Text(
            '無制限の記録と、AI相談と、家族共有。\nうちの子のすべてを、ちゃんと残す。',
            style: typo.bodyLarge.copyWith(
              color: colors.fgMuted,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 32),

          // ===== 機能リスト =====
          SectionLabel(AppLocalizations.of(context).section_whats_included),
          const SizedBox(height: 12),
          const _FeatureRow(
              title: 'Unlimited records',
              note: 'ご飯・うんち・おしっこ・嘔吐 — 月の上限なし'),
          const _FeatureRow(
              title: 'AI consultations',
              note: '月100回までの相談 + うんち画像診断 月10回'),
          const _FeatureRow(
              title: 'Family sharing',
              note: '最大3グループ × 5人で共有'),
          const _FeatureRow(
              title: 'Full history',
              note: '体重・体温の全期間グラフ、3ヶ月制限なし'),
          const _FeatureRow(
              title: 'Multiple pets',
              note: '何匹でも登録できる'),
          const SizedBox(height: 32),

          // ===== プラン選択 =====
          SectionLabel(AppLocalizations.of(context).section_choose_plan),
          const SizedBox(height: 12),

          _PlanCard(
            tier: ProTier.yearly,
            isSelected: pState.selectedTier == ProTier.yearly,
            badge: 'BEST VALUE',
            onTap: () => controller.selectTier(ProTier.yearly),
            colors: colors,
            typo: typo,
          ),
          const SizedBox(height: 10),
          _PlanCard(
            tier: ProTier.monthly,
            isSelected: pState.selectedTier == ProTier.monthly,
            onTap: () => controller.selectTier(ProTier.monthly),
            colors: colors,
            typo: typo,
          ),
          const SizedBox(height: 24),

          // ===== CTA ボタン =====
          _PrimaryCta(
            label: pState.isProcessing
                ? '処理中...'
                : 'Start 7-day trial',
            enabled: !pState.isProcessing,
            onTap: controller.purchase,
            colors: colors,
          ),
          const SizedBox(height: 12),
          Text(
            'トライアル中はいつでもキャンセル可能。\n期間終了後に自動更新されます。',
            textAlign: TextAlign.center,
            style: typo.bodySmall.copyWith(
              color: colors.fgMuted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),

          // ===== Restore + Legal =====
          Center(
            child: TextButton(
              onPressed: pState.isProcessing
                  ? null
                  : () => controller.restore(),
              child: Text(
                'Restore purchases',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  letterSpacing: 11 * 0.15,
                  color: colors.fg,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _LegalLink(
                label: 'Terms',
                onTap: () =>
                    _openUrl(context, AppConstants.termsOfUseUrl),
                colors: colors,
              ),
              Container(
                width: 1,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: colors.line,
              ),
              _LegalLink(
                label: 'Privacy',
                onTap: () =>
                    _openUrl(context, AppConstants.privacyPolicyUrl),
                colors: colors,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// _FeatureRow - 機能リスト行
// ============================================================================
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 線画チェックマーク
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: CustomPaint(
              size: const Size(14, 14),
              painter: _CheckPainter(color: colors.fg),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: typo.bodyLarge.copyWith(color: colors.fg),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: typo.bodySmall.copyWith(color: colors.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.55)
      ..lineTo(size.width * 0.42, size.height * 0.78)
      ..lineTo(size.width * 0.82, size.height * 0.25);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => old.color != color;
}

// ============================================================================
// _PlanCard - プラン選択カード
// ============================================================================
class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.tier,
    required this.isSelected,
    required this.onTap,
    required this.colors,
    required this.typo,
    this.badge,
  });

  final ProTier tier;
  final bool isSelected;
  final VoidCallback onTap;
  final AppColors colors;
  final AppTypography typo;
  final String? badge;

  String get _productId => switch (tier) {
        ProTier.monthly => AppConstants.iapMonthlyProductId,
        ProTier.yearly => AppConstants.iapYearlyProductId,
        ProTier.free => '',
      };

  String get _periodLabel {
    switch (tier) {
      case ProTier.monthly:
        return 'Monthly';
      case ProTier.yearly:
        return 'Yearly';
      case ProTier.free:
        return '';
    }
  }

  String get _periodSuffix {
    switch (tier) {
      case ProTier.monthly:
        return '/ month';
      case ProTier.yearly:
        return '/ year';
      case ProTier.free:
        return '';
    }
  }

  /// 年額の月割り計算用 (UI表示専用)
  String? _yearlyMonthlyEquivalent(ProductDetails details) {
    if (tier != ProTier.yearly) return null;
    final num? amount = details.rawPrice;
    if (amount == null || amount.isNaN) return null;
    final double perMonth = amount / 12;
    return '約 ${details.currencySymbol}${perMonth.round()} / 月相当';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProductDetails? details =
        ref.watch(purchaseServiceProvider).productFor(_productId);

    // ローカライズされた価格、ない場合はフォールバック
    final String priceLabel = details?.price ??
        (tier == ProTier.monthly ? '¥480' : '¥3,800');
    final String? equiv =
        details == null ? null : _yearlyMonthlyEquivalent(details);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? colors.fg : colors.bg,
          border: Border.all(
            color: colors.fg,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                // ラジオ風マーカー
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? colors.bg : colors.fg,
                      width: 1,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.bg,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _periodLabel,
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 22,
                      color: isSelected ? colors.bg : colors.fg,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? colors.bg : colors.fg,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 8,
                        letterSpacing: 8 * 0.2,
                        color: isSelected ? colors.bg : colors.fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    priceLabel,
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 28,
                      color: isSelected ? colors.bg : colors.fg,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _periodSuffix,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      color: isSelected
                          ? colors.bg.withValues(alpha: 0.7)
                          : colors.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (equiv != null) ...<Widget>[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  equiv,
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 10 * 0.15,
                    color: isSelected
                        ? colors.bg.withValues(alpha: 0.6)
                        : colors.fgFaint,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _PrimaryCta - メインCTA
// ============================================================================
class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? colors.fg : colors.bgSoft,
          border: Border.all(
            color: enabled ? colors.fg : colors.line,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 12,
            letterSpacing: 12 * 0.15,
            color: enabled ? colors.bg : colors.fgFaint,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// _LegalLink - Terms / Privacy リンク
// ============================================================================
class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.label,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.15,
            color: colors.fgMuted,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
