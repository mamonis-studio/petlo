// ============================================================================
// petlo - Pro Status Model
// ============================================================================
//
// ユーザーの Pro 契約状態。
//
// 状態遷移:
//   free → active (購入)
//   active → grace (期限切れ、14日猶予中)
//   grace → free (猶予期限切れ)
//   active → cancelled (解約済み、有効期限まで利用可)
//   cancelled → free (有効期限切れ)
//
// rev5.5: Pro解約後30日カウントダウンバナー (F-80)
//
// ============================================================================

import 'package:flutter/foundation.dart';

enum ProTier {
  /// 未契約
  free,

  /// 月額
  monthly,

  /// 年額
  yearly;

  String get name {
    switch (this) {
      case ProTier.free:
        return 'free';
      case ProTier.monthly:
        return 'monthly';
      case ProTier.yearly:
        return 'yearly';
    }
  }

  static ProTier fromString(String? s) {
    switch (s) {
      case 'monthly':
        return ProTier.monthly;
      case 'yearly':
        return ProTier.yearly;
      case 'free':
      default:
        return ProTier.free;
    }
  }
}

enum ProState {
  /// Pro 機能が完全に使える
  active,

  /// 期限切れだが14日の猶予中(グレースピリオド)
  grace,

  /// 解約済みだが有効期限まで利用可
  cancelled,

  /// 完全に Free
  free;

  String get name {
    switch (this) {
      case ProState.active:
        return 'active';
      case ProState.grace:
        return 'grace';
      case ProState.cancelled:
        return 'cancelled';
      case ProState.free:
        return 'free';
    }
  }

  static ProState fromString(String? s) {
    switch (s) {
      case 'active':
        return ProState.active;
      case 'grace':
        return ProState.grace;
      case 'cancelled':
        return ProState.cancelled;
      case 'free':
      default:
        return ProState.free;
    }
  }

  /// Pro機能が利用可能か (active / grace / cancelled の有効期限内)
  bool get isProAvailable {
    return this == ProState.active ||
        this == ProState.grace ||
        this == ProState.cancelled;
  }
}

@immutable
class ProStatus {
  const ProStatus({
    required this.tier,
    required this.state,
    this.expiresAt,
    this.trialEndsAt,
  });

  final ProTier tier;
  final ProState state;
  final DateTime? expiresAt;
  final DateTime? trialEndsAt;

  /// 完全な無料状態
  static const ProStatus free =
      ProStatus(tier: ProTier.free, state: ProState.free);

  /// Pro機能が利用可能か
  bool get isPro => state.isProAvailable;

  /// トライアル期間中か
  bool get isInTrial {
    if (trialEndsAt == null) return false;
    return DateTime.now().isBefore(trialEndsAt!);
  }

  /// 期限切れまでの残り日数 (cancelled / grace 状態用)
  int? get daysRemaining {
    if (expiresAt == null) return null;
    final Duration d = expiresAt!.difference(DateTime.now());
    if (d.isNegative) return 0;
    return d.inDays;
  }

  Map<String, String?> toMap() {
    return <String, String?>{
      'tier': tier.name,
      'state': state.name,
      'expiresAt': expiresAt?.toIso8601String(),
      'trialEndsAt': trialEndsAt?.toIso8601String(),
    };
  }

  static ProStatus fromMap(Map<String, String?> map) {
    return ProStatus(
      tier: ProTier.fromString(map['tier']),
      state: ProState.fromString(map['state']),
      expiresAt: map['expiresAt'] == null
          ? null
          : DateTime.tryParse(map['expiresAt']!),
      trialEndsAt: map['trialEndsAt'] == null
          ? null
          : DateTime.tryParse(map['trialEndsAt']!),
    );
  }
}
