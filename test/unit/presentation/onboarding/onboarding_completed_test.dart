// ============================================================================
// petlo - OnboardingCompletedNotifier Tests
// ============================================================================
//
// SharedPreferences ベースの永続化が絡むので、
// `SharedPreferences.setMockInitialValues({})` で mock してから
// `UserPreferences.instance.initialize()` を呼ぶパターンを使う。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/preferences/user_preferences.dart';
import 'package:petlo/presentation/providers/onboarding_completed_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    // 各テストの前に SharedPreferences をクリーンに
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // UserPreferences はシングルトンなので、毎回 initialize() で再ロード
    await UserPreferences.instance.initialize();
  });

  // ==========================================================================
  // 初期値
  // ==========================================================================
  group('OnboardingCompletedNotifier initial state', () {
    test('defaults to false (not completed) on fresh install', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(onboardingCompletedProvider), isFalse);
    });

    test('reads existing completed=true from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pref.onboarding.completed': true,
      });
      await UserPreferences.instance.initialize();

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(onboardingCompletedProvider), isTrue);
    });

    test('reads existing completed=false from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pref.onboarding.completed': false,
      });
      await UserPreferences.instance.initialize();

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(onboardingCompletedProvider), isFalse);
    });
  });

  // ==========================================================================
  // markCompleted
  // ==========================================================================
  group('markCompleted', () {
    test('sets state to true', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(onboardingCompletedProvider), isFalse);

      await container
          .read(onboardingCompletedProvider.notifier)
          .markCompleted();

      expect(container.read(onboardingCompletedProvider), isTrue);
    });

    test('persists to SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(onboardingCompletedProvider.notifier)
          .markCompleted();

      // 直接 UserPreferences から読み出して確認
      expect(UserPreferences.instance.onboardingCompleted, isTrue);
    });

    test('survives container recreation (永続化確認)', () async {
      // 1つ目の container で完了マーク
      final container1 = ProviderContainer();
      await container1
          .read(onboardingCompletedProvider.notifier)
          .markCompleted();
      container1.dispose();

      // 2つ目の container でも true (新規 build で復元される)
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      expect(container2.read(onboardingCompletedProvider), isTrue);
    });

    test('idempotent — calling twice keeps it true', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(onboardingCompletedProvider.notifier)
          .markCompleted();
      await container
          .read(onboardingCompletedProvider.notifier)
          .markCompleted();

      expect(container.read(onboardingCompletedProvider), isTrue);
    });
  });

  // ==========================================================================
  // reset (デバッグ用)
  // ==========================================================================
  group('reset', () {
    test('sets state back to false', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(onboardingCompletedProvider.notifier)
          .markCompleted();
      expect(container.read(onboardingCompletedProvider), isTrue);

      await container
          .read(onboardingCompletedProvider.notifier)
          .reset();
      expect(container.read(onboardingCompletedProvider), isFalse);
    });

    test('persists false to SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(onboardingCompletedProvider.notifier)
          .markCompleted();
      await container
          .read(onboardingCompletedProvider.notifier)
          .reset();

      expect(UserPreferences.instance.onboardingCompleted, isFalse);
    });

    test('reset survives container recreation', () async {
      final container1 = ProviderContainer();
      await container1
          .read(onboardingCompletedProvider.notifier)
          .markCompleted();
      await container1
          .read(onboardingCompletedProvider.notifier)
          .reset();
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      expect(container2.read(onboardingCompletedProvider), isFalse);
    });
  });

  // ==========================================================================
  // UserPreferences 直接の getter/setter
  // ==========================================================================
  group('UserPreferences.onboardingCompleted', () {
    test('default false on fresh', () {
      expect(UserPreferences.instance.onboardingCompleted, isFalse);
    });

    test('round-trip true', () async {
      await UserPreferences.instance.setOnboardingCompleted(true);
      expect(UserPreferences.instance.onboardingCompleted, isTrue);
    });

    test('round-trip false after true', () async {
      await UserPreferences.instance.setOnboardingCompleted(true);
      await UserPreferences.instance.setOnboardingCompleted(false);
      expect(UserPreferences.instance.onboardingCompleted, isFalse);
    });
  });
}
