// ============================================================================
// petlo - Decision D 純粋実装 テスト (build 57)
// ============================================================================
//
// 検証対象:
//   1. createPet (groupId=personal) → 1 scope (Personal, primary=true)
//   2. createPet (groupId=family-uuid) → 2 scopes (Personal primary=true +
//      family is_primary=false)
//   3. createPet (shared) は pets と family scope を sync_queue に積む
//      (Personal scope は積まれない)
//   4. backfillPersonalScopes: 既存 pets で Personal scope 不在のものを
//      backfill + 既存 non-Personal primary を降格
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
import 'package:petlo/data/repositories/pets_repository.dart';

void main() {
  late AppDatabase db;
  late PetsRepository pets;
  late PetScopesRepository scopes;

  setUpAll(() async {
    await PetloLogger.initialize();
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    pets = PetsRepository(db);
    scopes = PetScopesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('createPet — Decision D: Personal scope 常在', () {
    test('personal context: 1 scope (Personal, primary)', () async {
      final int petId = await pets.createPet(
        groupId: 'personal',
        name: 'Taro',
        type: PetType.dog,
      );
      final List<PetScopeEntity> ss = await scopes.getPetScopes(petId);
      expect(ss.length, 1);
      expect(ss.first.groupId, 'personal');
      expect(ss.first.isPrimary, isTrue);
      expect(ss.first.permission, MemberPermission.owner);
    });

    test('group context: 2 scopes (Personal primary + group share)',
        () async {
      final int petId = await pets.createPet(
        groupId: 'family-uuid',
        name: 'Mike',
        type: PetType.cat,
      );
      final List<PetScopeEntity> ss = await scopes.getPetScopes(petId);
      expect(ss.length, 2);

      final PetScopeEntity personalScope =
          ss.firstWhere((s) => s.groupId == 'personal');
      expect(personalScope.isPrimary, isTrue);
      expect(personalScope.permission, MemberPermission.owner);

      final PetScopeEntity familyScope =
          ss.firstWhere((s) => s.groupId == 'family-uuid');
      expect(familyScope.isPrimary, isFalse);
      expect(familyScope.permission, MemberPermission.owner);
    });

    test('group context: sync_queue は pets + family scope のみ '
        '(Personal scope は同期されない)', () async {
      final int petId = await pets.createPet(
        groupId: 'family-uuid',
        name: 'Mike',
        type: PetType.cat,
      );
      expect(petId, greaterThan(0));

      final List<SyncQueueItemEntity> queue =
          await db.select(db.syncQueue).get();
      expect(queue.length, 2);

      final SyncQueueItemEntity petOp =
          queue.firstWhere((q) => q.targetTable == 'pets');
      expect(petOp.groupId, 'family-uuid');

      final SyncQueueItemEntity scopeOp =
          queue.firstWhere((q) => q.targetTable == 'pet_scopes');
      expect(scopeOp.groupId, 'family-uuid');

      // Personal scope は積まれていない
      final Iterable<SyncQueueItemEntity> personalOps =
          queue.where((q) => q.groupId == 'personal');
      expect(personalOps, isEmpty);
    });

    test('personal context: sync_queue 空 (push 対象なし)', () async {
      await pets.createPet(
        groupId: 'personal',
        name: 'Taro',
        type: PetType.dog,
      );
      final List<SyncQueueItemEntity> queue =
          await db.select(db.syncQueue).get();
      expect(queue, isEmpty);
    });
  });

  group('backfillPersonalScopes (v9 migration)', () {
    test('既存 pet が Personal scope を取得 + 旧 non-Personal primary を降格',
        () async {
      // 既存データ模倣: pet を直接 INSERT、pet_scopes は family のみ
      // (旧 build 56 以前の状態)
      final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
      final int petId = await db.into(db.pets).insert(PetsCompanion.insert(
            groupId: const Value('family-uuid'),
            name: 'Legacy',
            type: PetType.dog,
            createdAt: t,
            updatedAt: t,
          ));
      await db.into(db.petScopes).insert(PetScopesCompanion.insert(
            petId: petId,
            groupId: 'family-uuid',
            permission: MemberPermission.owner,
            isPrimary: const Value(true),
            sharedAt: t,
            syncStatus: const Value(SyncStatus.synced),
            createdAt: t,
            updatedAt: t,
          ));

      // 事前確認: Personal scope なし
      List<PetScopeEntity> before = await scopes.getPetScopes(petId);
      expect(before.length, 1);
      expect(before.first.groupId, 'family-uuid');
      expect(before.first.isPrimary, isTrue);

      // backfill 実行
      await db.backfillPersonalScopes();

      // 結果: Personal scope が追加され、family は降格
      final List<PetScopeEntity> after = await scopes.getPetScopes(petId);
      expect(after.length, 2);

      final PetScopeEntity personal =
          after.firstWhere((s) => s.groupId == 'personal');
      expect(personal.isPrimary, isTrue);

      final PetScopeEntity family =
          after.firstWhere((s) => s.groupId == 'family-uuid');
      expect(family.isPrimary, isFalse);
    });

    test('既に Personal scope があるなら追加しない (冪等)', () async {
      // 既に正しい Decision D 状態
      final int petId = await pets.createPet(
        groupId: 'personal',
        name: 'Already',
        type: PetType.dog,
      );

      final List<PetScopeEntity> before = await scopes.getPetScopes(petId);
      expect(before.length, 1);

      await db.backfillPersonalScopes();
      await db.backfillPersonalScopes();

      final List<PetScopeEntity> after = await scopes.getPetScopes(petId);
      expect(after.length, 1, reason: 'idempotent — 重複 INSERT しない');
    });

    test('soft-deleted pet は backfill 対象外', () async {
      final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
      final int petId = await db.into(db.pets).insert(PetsCompanion.insert(
            groupId: const Value('personal'),
            name: 'Deleted',
            type: PetType.dog,
            createdAt: t,
            updatedAt: t,
            deletedAt: Value(t),
          ));

      await db.backfillPersonalScopes();

      final List<PetScopeEntity> ss = await scopes.getPetScopes(petId);
      expect(ss, isEmpty);
    });
  });
}
