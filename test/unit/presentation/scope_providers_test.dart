// ============================================================================
// petlo - Scope Providers Tests
// ============================================================================
//
// Chunk 5で実装したスコープ系Providerの動作確認。
//
// テスト戦略:
//   - SharedPreferencesAsyncはモックせず、テストでは初期値→操作→確認のシンプル系
//   - DBやRepositoryに依存しないPure Provider部分のみテスト
//   - DB絡みは別ファイル (database_test.dart) で
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';

void main() {
  group('currentGroupIdProvider', () {
    test('initial state is "personal"', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(currentGroupIdProvider), kPersonalGroupId);
    });

    test('switchTo updates state', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      const String testGroupId = 'group-uuid-123';
      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo(testGroupId);

      expect(container.read(currentGroupIdProvider), testGroupId);
    });

    test('switchToPersonal returns to personal', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo('group-1');
      await container.read(currentGroupIdProvider.notifier).switchToPersonal();

      expect(container.read(currentGroupIdProvider), kPersonalGroupId);
    });

    test('isPersonal getter works', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(currentGroupIdProvider.notifier).isPersonal,
        isTrue,
      );
    });
  });

  group('currentPetIdProvider', () {
    test('initial state is null', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(currentPetIdProvider), isNull);
    });

    test('selectPet updates state with stringified id', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(currentPetIdProvider.notifier).selectPet(42);

      expect(container.read(currentPetIdProvider), '42');
    });

    test('selectAll switches to "all" mode', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(currentPetIdProvider.notifier).selectAll();

      expect(container.read(currentPetIdProvider), kAllPetsId);
    });

    test('isAllPetsMode reflects "all" selection', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(currentPetIdProvider.notifier);

      await notifier.selectAll();
      expect(notifier.isAllPetsMode, isTrue);

      await notifier.selectPet(1);
      expect(notifier.isAllPetsMode, isFalse);
    });

    test('singlePetIdOrNull returns int or null', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(currentPetIdProvider.notifier);

      // 未選択
      expect(notifier.singlePetIdOrNull, isNull);

      // 単一選択
      await notifier.selectPet(7);
      expect(notifier.singlePetIdOrNull, 7);

      // All mode
      await notifier.selectAll();
      expect(notifier.singlePetIdOrNull, isNull);

      // クリア
      await notifier.clear();
      expect(notifier.singlePetIdOrNull, isNull);
    });
  });

  group('currentRoleProvider', () {
    test('Personal scope yields owner role', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      // Personal初期状態 → owner
      expect(container.read(currentRoleProvider), MemberPermission.owner);
    });

    test('Group scope defaults to viewer (safe-side, until updated)',
        () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo('shared-group');

      // 共有グループ切替後、明示更新前は viewer (安全側)
      expect(container.read(currentRoleProvider), MemberPermission.viewer);
    });

    test('update() changes role', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo('shared-group');

      container
          .read(currentRoleProvider.notifier)
          .update(MemberPermission.editor);

      expect(container.read(currentRoleProvider), MemberPermission.editor);
    });
  });

  group('Derived providers', () {
    test('canEditProvider true when owner', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(canEditProvider), isTrue);
    });

    test('canEditProvider true when editor', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo('shared-group');
      container
          .read(currentRoleProvider.notifier)
          .update(MemberPermission.editor);

      expect(container.read(canEditProvider), isTrue);
    });

    test('canEditProvider false when viewer', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo('shared-group');
      container
          .read(currentRoleProvider.notifier)
          .update(MemberPermission.viewer);

      expect(container.read(canEditProvider), isFalse);
    });

    test('isOwnerProvider only true for owner', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      // Personal = owner
      expect(container.read(isOwnerProvider), isTrue);

      // Editor → false
      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo('group-x');
      container
          .read(currentRoleProvider.notifier)
          .update(MemberPermission.editor);
      expect(container.read(isOwnerProvider), isFalse);
    });

    test('isPersonalScopeProvider tracks current group', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(isPersonalScopeProvider), isTrue);

      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo('group-1');

      expect(container.read(isPersonalScopeProvider), isFalse);
    });
  });
}
