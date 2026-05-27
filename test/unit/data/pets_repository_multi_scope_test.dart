// ============================================================================
// petlo - pets_repository × pet_scopes JOIN クエリのテスト (Phase G2)
// ============================================================================
//
// 検証対象:
//   - watchActivePetsInScope / watchPartedPetsInScope が pet_scopes 経由の
//     JOIN 読み取りで正しく動くこと
//   - createPet が primary pet_scope を自動作成すること
//   - hasPetWithName が pet_scopes 経由でスコープ内一致を判定すること
//   - subscriber 視点 (他人のペットが共有された状態) でペットが見えること
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

  // build 49: movePetToGroup の削除に伴い setUpAll(PetloLogger.initialize)
  // も不要になったが、scopes 系の async コードでも logger を間接呼びする
  // 可能性があるため安全側で残す。
  setUpAll(() async {
    await PetloLogger.initialize();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    pets = PetsRepository(db);
    scopes = PetScopesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('createPet auto-creates primary pet_scope', () {
    test('personal scope', () async {
      final int petId = await pets.createPet(
        groupId: 'personal',
        name: 'Taro',
        type: PetType.dog,
      );
      final List<PetScopeEntity> ss = await scopes.getPetScopes(petId);
      expect(ss.length, 1);
      expect(ss.first.groupId, 'personal');
      expect(ss.first.permission, MemberPermission.owner);
      expect(ss.first.isPrimary, isTrue);
    });

    test('group scope', () async {
      final int petId = await pets.createPet(
        groupId: 'group-uuid-A',
        name: 'Hana',
        type: PetType.cat,
      );
      final PetScopeEntity? primary = await scopes.findPrimaryScope(petId);
      expect(primary!.groupId, 'group-uuid-A');
    });
  });

  group('watchActivePetsInScope (JOIN via pet_scopes)', () {
    test('returns pets whose pet_scope.group_id matches', () async {
      await pets.createPet(
          groupId: 'personal', name: 'A', type: PetType.dog);
      await pets.createPet(
          groupId: 'group-x', name: 'B', type: PetType.dog);

      final List<PetEntity> inPersonal =
          await pets.watchActivePetsInScope('personal').first;
      expect(inPersonal.map((p) => p.name), ['A']);

      final List<PetEntity> inGroupX =
          await pets.watchActivePetsInScope('group-x').first;
      expect(inGroupX.map((p) => p.name), ['B']);
    });

    test('subscriber view: pet visible if pet_scope row exists for that group',
        () async {
      // Owner perspective: pet lives in Personal
      final int taroId = await pets.createPet(
          groupId: 'personal', name: 'Taro', type: PetType.dog);

      // Subscriber's view: not visible yet from group-A
      List<PetEntity> inA = await pets.watchActivePetsInScope('group-A').first;
      expect(inA, isEmpty);

      // ペットを group-A に共有 (primary を変えずに subscriber 行を追加)
      await scopes.addPetScope(
        petId: taroId,
        groupId: 'group-A',
        permission: MemberPermission.editor,
      );

      inA = await pets.watchActivePetsInScope('group-A').first;
      expect(inA.length, 1);
      expect(inA.first.id, taroId);
      // pets.group_id 自体は 'personal' のまま (Hybrid: 物理本籍維持)
      expect(inA.first.groupId, 'personal');
    });

    test('soft-deleted pet_scope hides the pet from that scope', () async {
      final int petId = await pets.createPet(
          groupId: 'personal', name: 'Mike', type: PetType.cat);
      await scopes.addPetScope(
        petId: petId,
        groupId: 'group-A',
        permission: MemberPermission.editor,
      );
      // この時点で group-A から見える
      expect(
        (await pets.watchActivePetsInScope('group-A').first).length,
        1,
      );

      // 共有解除 (論理削除)
      await scopes.removePetScope(petId: petId, groupId: 'group-A');
      expect(
        (await pets.watchActivePetsInScope('group-A').first),
        isEmpty,
      );
      // Personal (primary) からは引き続き見える
      expect(
        (await pets.watchActivePetsInScope('personal').first).length,
        1,
      );
    });

    test('parted pets are excluded from active query but in parted query',
        () async {
      final int petId = await pets.createPet(
          groupId: 'personal', name: 'Senior', type: PetType.dog);
      // 直接 partedAt をセット
      await db.customStatement(
        'UPDATE pets SET parted_at = ? WHERE id = ?',
        <Object?>[DateTime.now().millisecondsSinceEpoch, petId],
      );
      expect(await pets.watchActivePetsInScope('personal').first, isEmpty);
      expect(
        (await pets.watchPartedPetsInScope('personal').first).length,
        1,
      );
    });
  });

  // build 49 (C3): movePetToGroup を物理削除したのでテスト group を削除。
  // ペット所属の移動は addPetScope / removePetScope の組み合わせで行う想定で、
  // それらの単体検証は sync_lww_test 等でカバー済み。

  group('hasPetWithName respects pet_scopes', () {
    test('same name same scope returns true', () async {
      await pets.createPet(
          groupId: 'personal', name: 'Taro', type: PetType.dog);
      expect(
        await pets.hasPetWithName(groupId: 'personal', name: 'Taro'),
        isTrue,
      );
    });

    test('same name different scope returns false', () async {
      await pets.createPet(
          groupId: 'personal', name: 'Taro', type: PetType.dog);
      expect(
        await pets.hasPetWithName(groupId: 'group-X', name: 'Taro'),
        isFalse,
      );
    });

    test('shared pet name conflict detected in subscriber scope', () async {
      final int t1 = await pets.createPet(
          groupId: 'personal', name: 'Taro', type: PetType.dog);
      // group-A に共有
      await scopes.addPetScope(
        petId: t1,
        groupId: 'group-A',
        permission: MemberPermission.editor,
      );
      // group-A 内で同名チェック → true (共有された Taro がカウントされる)
      expect(
        await pets.hasPetWithName(groupId: 'group-A', name: 'Taro'),
        isTrue,
      );
    });
  });
}
