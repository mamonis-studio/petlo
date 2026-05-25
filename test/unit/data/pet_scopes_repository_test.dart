// ============================================================================
// petlo - PetScopesRepository + backfill Tests (Phase G1)
// ============================================================================
//
// 検証対象:
//   1. backfillPetScopesFromPets: 既存 pets が 1:1 で pet_scopes に
//      入ること、既存 scope と被ったら IGNORE で重複しないこと
//   2. PetScopesRepository CRUD: add / remove / update / find / watch
//   3. addPetScope の冪等性 (同 pet × group の二重共有禁止)
//   4. removePetScope は論理削除のみ
//   5. addPetScope は論理削除済み行を再活性化する
//
// テスト戦略:
//   - NativeDatabase.memory() で毎テスト fresh DB を作る
//   - 直接 db.into(db.pets).insert(...) で pets 投入
//   - backfillPetScopesFromPets() を明示的に叩いて結果検証
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/pet_scopes_repository.dart';

void main() {
  late AppDatabase db;
  late PetScopesRepository repo;

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
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return db.into(db.pets).insert(PetsCompanion.insert(
          groupId: Value(groupId),
          name: name,
          type: PetType.dog,
          createdAt: now,
          updatedAt: now,
        ));
  }

  // ==========================================================================
  // backfill
  // ==========================================================================

  group('backfillPetScopesFromPets', () {
    test('empty pets → empty pet_scopes (no-op)', () async {
      await repo.getPetScopes(0); // smoke
      await db.backfillPetScopesFromPets();
      final int count = (await db.select(db.petScopes).get()).length;
      expect(count, 0);
    });

    test('inserts 1 scope row per existing pet', () async {
      final int p1 = await insertPet(name: 'Taro', groupId: 'personal');
      final int p2 =
          await insertPet(name: 'Hana', groupId: 'group-uuid-aaa');

      await db.backfillPetScopesFromPets();

      final List<PetScopeEntity> all = await db.select(db.petScopes).get();
      expect(all.length, 2);

      final PetScopeEntity s1 = all.firstWhere((e) => e.petId == p1);
      expect(s1.groupId, 'personal');
      expect(s1.permission, MemberPermission.owner);
      expect(s1.isPrimary, isTrue);
      expect(s1.deletedAt, isNull);

      final PetScopeEntity s2 = all.firstWhere((e) => e.petId == p2);
      expect(s2.groupId, 'group-uuid-aaa');
      expect(s2.isPrimary, isTrue);
    });

    test('idempotent: running backfill twice does not duplicate', () async {
      await insertPet(name: 'Pochi');
      await db.backfillPetScopesFromPets();
      await db.backfillPetScopesFromPets();
      final int count = (await db.select(db.petScopes).get()).length;
      expect(count, 1);
    });

    test('does not touch existing manually-added scope', () async {
      final int p = await insertPet(name: 'Mike', groupId: 'group-x');
      // 手動で別 permission を入れる
      await repo.addPetScope(
        petId: p,
        groupId: 'group-x',
        permission: MemberPermission.viewer,
        isPrimary: true,
      );
      await db.backfillPetScopesFromPets();
      final List<PetScopeEntity> scopes = await repo.getPetScopes(p);
      expect(scopes.length, 1);
      // backfill が permission を owner に上書きしていないことを確認
      expect(scopes.first.permission, MemberPermission.viewer);
    });
  });

  // ==========================================================================
  // PetScopesRepository CRUD
  // ==========================================================================

  group('PetScopesRepository CRUD', () {
    test('addPetScope inserts and findScope returns it', () async {
      final int p = await insertPet(name: 'A');
      final int id = await repo.addPetScope(
        petId: p,
        groupId: 'group-1',
        permission: MemberPermission.editor,
        isPrimary: false,
        sharedByUserId: 'user-abc',
      );
      expect(id, greaterThan(0));

      final PetScopeEntity? s =
          await repo.findScope(petId: p, groupId: 'group-1');
      expect(s, isNotNull);
      expect(s!.permission, MemberPermission.editor);
      expect(s.sharedByUserId, 'user-abc');
      expect(s.isPrimary, isFalse);
    });

    test('addPetScope is idempotent for live (pet, group) pair', () async {
      final int p = await insertPet(name: 'B');
      final int id1 = await repo.addPetScope(
        petId: p,
        groupId: 'group-1',
        permission: MemberPermission.editor,
      );
      final int id2 = await repo.addPetScope(
        petId: p,
        groupId: 'group-1',
        permission: MemberPermission.viewer, // 変更を試みても上書きしない
      );
      expect(id1, id2);
      final PetScopeEntity? s =
          await repo.findScope(petId: p, groupId: 'group-1');
      expect(s!.permission, MemberPermission.editor); // 最初の値が保持
    });

    test('removePetScope soft-deletes and findScope returns null', () async {
      final int p = await insertPet(name: 'C');
      await repo.addPetScope(
        petId: p,
        groupId: 'group-1',
        permission: MemberPermission.editor,
      );
      final bool ok =
          await repo.removePetScope(petId: p, groupId: 'group-1');
      expect(ok, isTrue);
      expect(await repo.findScope(petId: p, groupId: 'group-1'), isNull);
      // 物理的には残っている
      final List<PetScopeEntity> raw =
          await db.select(db.petScopes).get();
      expect(raw.length, 1);
      expect(raw.first.deletedAt, isNotNull);
    });

    test('addPetScope reactivates a soft-deleted scope', () async {
      final int p = await insertPet(name: 'D');
      await repo.addPetScope(
        petId: p,
        groupId: 'group-1',
        permission: MemberPermission.editor,
      );
      await repo.removePetScope(petId: p, groupId: 'group-1');
      final int reId = await repo.addPetScope(
        petId: p,
        groupId: 'group-1',
        permission: MemberPermission.viewer,
        isPrimary: true,
      );
      final PetScopeEntity? s =
          await repo.findScope(petId: p, groupId: 'group-1');
      expect(s, isNotNull);
      expect(s!.id, reId);
      expect(s.permission, MemberPermission.viewer);
      expect(s.isPrimary, isTrue);
      expect(s.deletedAt, isNull);
      // 物理 row は 1 件のまま (重複していない)
      final int physical = (await db.select(db.petScopes).get()).length;
      expect(physical, 1);
    });

    test('updatePetScopePermission changes permission only', () async {
      final int p = await insertPet(name: 'E');
      await repo.addPetScope(
        petId: p,
        groupId: 'group-1',
        permission: MemberPermission.editor,
      );
      final bool ok = await repo.updatePetScopePermission(
        petId: p,
        groupId: 'group-1',
        permission: MemberPermission.viewer,
      );
      expect(ok, isTrue);
      final PetScopeEntity? s =
          await repo.findScope(petId: p, groupId: 'group-1');
      expect(s!.permission, MemberPermission.viewer);
    });

    test('findPrimaryScope returns the primary one', () async {
      final int p = await insertPet(name: 'F');
      await repo.addPetScope(
        petId: p,
        groupId: 'personal',
        permission: MemberPermission.owner,
        isPrimary: true,
      );
      await repo.addPetScope(
        petId: p,
        groupId: 'group-A',
        permission: MemberPermission.editor,
      );
      final PetScopeEntity? primary = await repo.findPrimaryScope(p);
      expect(primary, isNotNull);
      expect(primary!.groupId, 'personal');
    });

    test('getPetScopes excludes soft-deleted', () async {
      final int p = await insertPet(name: 'G');
      await repo.addPetScope(
        petId: p,
        groupId: 'g1',
        permission: MemberPermission.editor,
      );
      await repo.addPetScope(
        petId: p,
        groupId: 'g2',
        permission: MemberPermission.editor,
      );
      await repo.removePetScope(petId: p, groupId: 'g2');
      final List<PetScopeEntity> live = await repo.getPetScopes(p);
      expect(live.length, 1);
      expect(live.first.groupId, 'g1');
    });

    test('UNIQUE(pet_id, group_id) prevents raw duplicate insert', () async {
      final int p = await insertPet(name: 'H');
      final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db.into(db.petScopes).insert(PetScopesCompanion.insert(
            petId: p,
            groupId: 'g1',
            permission: MemberPermission.editor,
            sharedAt: t,
            createdAt: t,
            updatedAt: t,
          ));
      expect(
        () => db.into(db.petScopes).insert(PetScopesCompanion.insert(
              petId: p,
              groupId: 'g1',
              permission: MemberPermission.viewer,
              sharedAt: t,
              createdAt: t,
              updatedAt: t,
            )),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ==========================================================================
  // CASCADE on pet physical delete (rare path; pets は通常論理削除)
  // ==========================================================================

  test('physical delete of pet cascades to pet_scopes', () async {
    final int p = await insertPet(name: 'I');
    await repo.addPetScope(
      petId: p,
      groupId: 'g1',
      permission: MemberPermission.editor,
    );
    await (db.delete(db.pets)..where(($PetsTable t) => t.id.equals(p))).go();
    final List<PetScopeEntity> remaining = await db.select(db.petScopes).get();
    expect(remaining, isEmpty);
  });
}
