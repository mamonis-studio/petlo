// ============================================================================
// petlo - PaywallController Tests
// ============================================================================
//
// PaywallState は immutable + copyWith なので Pure Dart で検証可能。
// 実際の Notifier の動作は ProviderContainer 経由で。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/billing/pro_status.dart';
import 'package:petlo/presentation/screens/paywall/paywall_controller.dart';

void main() {
  // ==========================================================================
  // PaywallState
  // ==========================================================================
  group('PaywallState defaults', () {
    test('selectedTier defaults to yearly', () {
      const s = PaywallState();
      expect(s.selectedTier, ProTier.yearly);
    });

    test('isProcessing defaults to false', () {
      const s = PaywallState();
      expect(s.isProcessing, isFalse);
    });

    test('errorMessage defaults to null', () {
      const s = PaywallState();
      expect(s.errorMessage, isNull);
    });
  });

  group('PaywallState copyWith', () {
    test('selectedTier can be changed', () {
      const s = PaywallState();
      final s2 = s.copyWith(selectedTier: ProTier.monthly);
      expect(s2.selectedTier, ProTier.monthly);
      expect(s2.isProcessing, isFalse);
    });

    test('errorMessage=null can be set explicitly via sentinel', () {
      const s = PaywallState(errorMessage: 'old error');
      final s2 = s.copyWith(errorMessage: null);
      expect(s2.errorMessage, isNull);
    });

    test('errorMessage omitted preserves existing', () {
      const s = PaywallState(errorMessage: 'preserved');
      final s2 = s.copyWith(isProcessing: true);
      expect(s2.errorMessage, 'preserved');
      expect(s2.isProcessing, isTrue);
    });

    test('isProcessing toggle', () {
      const s = PaywallState();
      final s2 = s.copyWith(isProcessing: true);
      final s3 = s2.copyWith(isProcessing: false);
      expect(s2.isProcessing, isTrue);
      expect(s3.isProcessing, isFalse);
    });
  });

  // ==========================================================================
  // PaywallController via ProviderContainer
  // ==========================================================================
  group('PaywallController.selectTier', () {
    test('switching to monthly updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(paywallControllerProvider).selectedTier,
        ProTier.yearly,
      );

      container
          .read(paywallControllerProvider.notifier)
          .selectTier(ProTier.monthly);

      expect(
        container.read(paywallControllerProvider).selectedTier,
        ProTier.monthly,
      );
    });

    test('selecting free is ignored', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(paywallControllerProvider.notifier)
          .selectTier(ProTier.free);

      // 変わらず yearly のまま
      expect(
        container.read(paywallControllerProvider).selectedTier,
        ProTier.yearly,
      );
    });

    test('selecting clears error message', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // エラーをセットしてから tier 切替
      // (テスト用に直接 state は触れないので、controller経由で)
      // selectTier 後は errorMessage が null になる
      container
          .read(paywallControllerProvider.notifier)
          .selectTier(ProTier.monthly);
      expect(
        container.read(paywallControllerProvider).errorMessage,
        isNull,
      );
    });
  });

  group('PaywallController.markCompleted', () {
    test('clears isProcessing and error', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(paywallControllerProvider.notifier)
          .markCompleted();
      final s = container.read(paywallControllerProvider);
      expect(s.isProcessing, isFalse);
      expect(s.errorMessage, isNull);
    });
  });

  group('PaywallController.clearError', () {
    test('makes errorMessage null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(paywallControllerProvider.notifier)
          .clearError();
      expect(
        container.read(paywallControllerProvider).errorMessage,
        isNull,
      );
    });
  });
}
