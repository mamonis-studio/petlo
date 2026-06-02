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
import 'package:petlo/core/utils/logger.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  // build 61: CurrentGroupIdNotifier / CurrentPetIdNotifier の build() は
  // SharedPreferencesAsync を非同期 read する + 例外時に PetloLogger を触る。
  // テスト前に in-memory async platform をセットし、PetloLogger も initialize。
  setUpAll(() async {
    await PetloLogger.initialize();
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

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

    // build 27 で currentRoleProvider は drift `_currentGroupEntityProvider`
    // 経由になり、Group scope の挙動を単体テストするには drift DB の bind が
    // 必要になった。本ファイルは Pure Provider テストなので、Group scope での
    // viewer フォールバックは override テスト + Derived providers のテストで
    // 代替する (旧「Group scope defaults to viewer」テスト 1 件は廃止)。

    // build 27: currentRoleProvider は drift から自動派生する Provider に
    // 変わり、`.notifier.update(...)` は廃止された。テストで任意の role を
    // シミュレートする場合は ProviderContainer の overrides を使う。
    test('override yields requested role', () {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          currentRoleProvider.overrideWith((_) => MemberPermission.editor),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(currentRoleProvider), MemberPermission.editor);
    });
  });

  group('Derived providers', () {
    // build 27 以降は currentRoleProvider を override して role を注入する。
    ProviderContainer makeWithRole(MemberPermission role) {
      return ProviderContainer(
        overrides: <Override>[
          currentRoleProvider.overrideWith((_) => role),
        ],
      );
    }

    test('canEditProvider true when owner', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      // Personal 初期 = owner
      expect(container.read(canEditProvider), isTrue);
    });

    test('canEditProvider true when editor', () {
      final ProviderContainer container =
          makeWithRole(MemberPermission.editor);
      addTearDown(container.dispose);
      expect(container.read(canEditProvider), isTrue);
    });

    test('canEditProvider false when viewer', () {
      final ProviderContainer container =
          makeWithRole(MemberPermission.viewer);
      addTearDown(container.dispose);
      expect(container.read(canEditProvider), isFalse);
    });

    test('isOwnerProvider only true for owner', () {
      // Personal = owner
      final ProviderContainer ownerC = ProviderContainer();
      addTearDown(ownerC.dispose);
      expect(ownerC.read(isOwnerProvider), isTrue);

      // Editor → false
      final ProviderContainer editorC =
          makeWithRole(MemberPermission.editor);
      addTearDown(editorC.dispose);
      expect(editorC.read(isOwnerProvider), isFalse);
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
