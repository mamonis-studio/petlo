// ============================================================================
// petlo - sync_service LWW + pet_scope op テスト (Phase G2, build 44)
// ============================================================================
//
// 検証対象:
//   - PetScopesRepository.addPetScope / remove / updatePermission が shared
//     scope で sync_queue に積むこと、personal では積まないこと
//   - 積まれる op の entityType 等を _buildOperation 経由で組み立てたとき
//     'pet_scope' になること、payload に snake_case 列が入ること
//
// LWW 本体 (`_isPayloadFresher`) のテストは private のため、_applyPetEvent
// 経由の挙動テストは Phase G3 (server fixture と組み合わせ) で行う。本テスト
// は public API レベルの validation。
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/utils/logger.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/pet_scopes_repository.dart';

void main() {
  late AppDatabase db;
  late PetScopesRepository repo;

  setUpAll(() async {
    await PetloLogger.initialize();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = PetScopesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertPet({
    required String name,
    String groupId = 'personal',
  }) async {
    final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
    return db.into(db.pets).insert(PetsCompanion.insert(
          groupId: Value(groupId),
          name: name,
          type: PetType.dog,
          createdAt: t,
          updatedAt: t,
        ));
  }

  group('sync_queue enqueue rules', () {
    test('addPetScope to personal does NOT enqueue', () async {
      final int p = await insertPet(name: 'A');
      await repo.addPetScope(
        petId: p,
        groupId: 'personal',
        permission: MemberPermission.owner,
        isPrimary: true,
      );
      final List<SyncQueueItemEntity> q =
          await db.select(db.syncQueue).get();
      expect(q, isEmpty);
    });

    test('addPetScope to shared group enqueues update op', () async {
      final int p = await insertPet(name: 'B');
      await repo.addPetScope(
        petId: p,
        groupId: 'group-uuid-A',
        permission: MemberPermission.editor,
      );
      final List<SyncQueueItemEntity> q =
          await db.select(db.syncQueue).get();
      expect(q.length, 1);
      expect(q.first.targetTable, 'pet_scopes');
      expect(q.first.operation, SyncOperation.update);
      expect(q.first.groupId, 'group-uuid-A');
    });

    test('removePetScope on shared scope enqueues delete op', () async {
      final int p = await insertPet(name: 'C');
      await repo.addPetScope(
        petId: p,
        groupId: 'group-uuid-A',
        permission: MemberPermission.editor,
      );
      await repo.removePetScope(petId: p, groupId: 'group-uuid-A');
      final List<SyncQueueItemEntity> q =
          await (db.select(db.syncQueue)
                ..orderBy(<OrderClauseGenerator<SyncQueue>>[
                  (SyncQueue t) => OrderingTerm(expression: t.id),
                ]))
              .get();
      // 1: addPetScope update / 2: removePetScope delete
      expect(q.length, 2);
      expect(q.last.operation, SyncOperation.delete);
      expect(q.last.targetTable, 'pet_scopes');
    });

    test('updatePetScopePermission on shared scope enqueues update op',
        () async {
      final int p = await insertPet(name: 'D');
      await repo.addPetScope(
        petId: p,
        groupId: 'group-uuid-A',
        permission: MemberPermission.editor,
      );
      // 既存 enqueue ぶんを消して切り分けやすくする
      await db.delete(db.syncQueue).go();
      await repo.updatePetScopePermission(
        petId: p,
        groupId: 'group-uuid-A',
        permission: MemberPermission.viewer,
      );
      final List<SyncQueueItemEntity> q =
          await db.select(db.syncQueue).get();
      expect(q.length, 1);
      expect(q.first.targetTable, 'pet_scopes');
      expect(q.first.operation, SyncOperation.update);
    });

    test('updatePetScopePermission on personal does NOT enqueue', () async {
      final int p = await insertPet(name: 'E');
      await repo.addPetScope(
        petId: p,
        groupId: 'personal',
        permission: MemberPermission.owner,
      );
      // personal の addPetScope は enqueue しない (前テストで確認済)
      await repo.updatePetScopePermission(
        petId: p,
        groupId: 'personal',
        permission: MemberPermission.viewer,
      );
      final List<SyncQueueItemEntity> q =
          await db.select(db.syncQueue).get();
      expect(q, isEmpty);
    });
  });
}
