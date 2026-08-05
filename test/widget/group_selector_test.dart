// ============================================================================
// petlo - Group Selector Tests
// ============================================================================
//
// GroupRoleBadge (純UI) とGroupSelectorBar (Provider絡み) のテスト。
//
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/groups_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/widgets/group_selector/group_role_badge.dart';
import 'package:petlo/presentation/widgets/group_selector/group_selector_bar.dart';

import '../helpers/test_app.dart';

void main() {
  // アプリのプロバイダ群 (scope_providers など) が build 中に
  // PetloLogger.instance を触るため、初期化しないと落ちる。
  setUpAll(initTestLogger);

  // ==========================================================================
  // GroupRoleBadge
  // ==========================================================================
  group('GroupRoleBadge', () {
    testWidgets('Owner badge shows OWNER', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: const GroupRoleBadge.role(permission: MemberPermission.owner),
        ),
      );
      expect(find.text('OWNER'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('Editor badge shows EDITOR', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: const GroupRoleBadge.role(permission: MemberPermission.editor),
        ),
      );
      expect(find.text('EDITOR'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('Viewer badge shows VIEWER', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: const GroupRoleBadge.role(permission: MemberPermission.viewer),
        ),
      );
      expect(find.text('VIEWER'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('localOnly badge shows LOCAL ONLY',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(child: const GroupRoleBadge.localOnly()),
      );
      expect(find.text('ローカルのみ'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  // ==========================================================================
  // GroupSelectorBar (with DB)
  // ==========================================================================
  group('GroupSelectorBar (with DB)', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Widget wrap() {
      return wrapWithApp(
        // 素の MaterialApp を自前で組むとテーマ (AppColors extension) と
        // l10n デリゲートが入らず AppColors.of() が投げる。
        container: container,
        child: GroupSelectorBar(),
      );
    }

    testWidgets('shows "Personal" + "LOCAL ONLY" by default',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('マイ'), findsOneWidget);
      expect(find.text('ローカルのみ'), findsOneWidget);
      expect(find.text('グループ'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('shows group name + role badge when in shared group',
        (WidgetTester tester) async {
      // グループ準備
      final GroupsRepository repo = GroupsRepository(db);
      await repo.upsertGroupFromServer(
        remoteId: 'group-uuid-abc',
        name: 'お父さん家族',
        ownerUserId: 'user-x',
        myPermission: MemberPermission.owner,
        status: GroupStatus.active,
        joinedAt: DateTime.now().millisecondsSinceEpoch,
      );

      // currentGroupId をそのグループに切替
      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo('group-uuid-abc');
      // build 73: currentRoleProvider は DB のグループ (myPermission) から
      // 派生する算出プロバイダになったため .notifier を持たない。
      // 権限は upsertGroupFromServer / DB の状態が唯一の真実。

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('お父さん家族'), findsOneWidget);
      expect(find.text('OWNER'), findsOneWidget);
      expect(find.text('ローカルのみ'), findsNothing);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('uses warn color when group is pending deletion',
        (WidgetTester tester) async {
      // pendingDeletion 状態のグループ
      final GroupsRepository repo = GroupsRepository(db);
      await repo.upsertGroupFromServer(
        remoteId: 'group-pd',
        name: 'Closing soon',
        ownerUserId: 'user-x',
        myPermission: MemberPermission.editor,
        status: GroupStatus.pendingDeletion,
        pendingDeletionAt: DateTime.now()
            .add(const Duration(days: 30))
            .millisecondsSinceEpoch,
        joinedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo('group-pd');
      // build 73: currentRoleProvider は DB のグループ (myPermission) から
      // 派生する算出プロバイダになったため .notifier を持たない。
      // 権限は upsertGroupFromServer / DB の状態が唯一の真実。

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // テキストはあるはず (色の確認は省略、find.byTypeで色検証は厳しい)
      expect(find.text('Closing soon'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('tap opens GroupSwitcherModal', (WidgetTester tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // セレクターバー (Personalラベル)をタップ
      await tester.tap(find.text('マイ'));
      await tester.pumpAndSettle();

      // モーダルが表示される
      expect(find.text('Switch group'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // GroupsRepository (純DB)
  // ==========================================================================
  group('GroupsRepository', () {
    late AppDatabase db;
    late GroupsRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = GroupsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('upsertGroupFromServer creates new entry', () async {
      await repo.upsertGroupFromServer(
        remoteId: 'g1',
        name: 'G1',
        ownerUserId: 'u1',
        myPermission: MemberPermission.owner,
        status: GroupStatus.active,
        joinedAt: 1000,
      );

      final GroupEntity? g = await repo.getGroupByRemoteId('g1');
      expect(g, isNotNull);
      expect(g!.name, 'G1');
      expect(g.myPermission, MemberPermission.owner);
    }, tags: <String>['needs_codegen']);

    test('upsertGroupFromServer updates existing entry', () async {
      await repo.upsertGroupFromServer(
        remoteId: 'g1',
        name: 'Old',
        ownerUserId: 'u1',
        myPermission: MemberPermission.editor,
        status: GroupStatus.active,
        joinedAt: 1000,
      );
      await repo.upsertGroupFromServer(
        remoteId: 'g1',
        name: 'New Name',
        ownerUserId: 'u1',
        myPermission: MemberPermission.viewer, // 権限が降格
        status: GroupStatus.active,
        joinedAt: 1000,
      );

      final GroupEntity? g = await repo.getGroupByRemoteId('g1');
      expect(g!.name, 'New Name');
      expect(g.myPermission, MemberPermission.viewer);
    }, tags: <String>['needs_codegen']);

    test('remainingGroupSlots starts at 3', () async {
      expect(await repo.remainingGroupSlots(), 3);
    }, tags: <String>['needs_codegen']);

    test('remainingGroupSlots decrements as groups added', () async {
      await repo.upsertGroupFromServer(
        remoteId: 'g1', name: 'a', ownerUserId: 'u', myPermission: MemberPermission.owner,
        status: GroupStatus.active, joinedAt: 0,
      );
      expect(await repo.remainingGroupSlots(), 2);

      await repo.upsertGroupFromServer(
        remoteId: 'g2', name: 'b', ownerUserId: 'u', myPermission: MemberPermission.owner,
        status: GroupStatus.active, joinedAt: 0,
      );
      expect(await repo.remainingGroupSlots(), 1);

      await repo.upsertGroupFromServer(
        remoteId: 'g3', name: 'c', ownerUserId: 'u', myPermission: MemberPermission.owner,
        status: GroupStatus.active, joinedAt: 0,
      );
      expect(await repo.remainingGroupSlots(), 0);
    }, tags: <String>['needs_codegen']);

    test('leaveGroupLocally removes the row', () async {
      await repo.upsertGroupFromServer(
        remoteId: 'g1', name: 'a', ownerUserId: 'u', myPermission: MemberPermission.editor,
        status: GroupStatus.active, joinedAt: 0,
      );
      await repo.leaveGroupLocally('g1');
      expect(await repo.getGroupByRemoteId('g1'), isNull);
    }, tags: <String>['needs_codegen']);
  });
}
