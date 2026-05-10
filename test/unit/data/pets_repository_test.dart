// ============================================================================
// petlo - Pets Repository Tests
// ============================================================================
//
// Personal/Shared スコープでのCRUDと、共通カラム埋め込みの確認。
// このテストは `flutter pub run build_runner build` 実行後に動く。
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/pets_repository.dart';

void main() {
  group('PetsRepository', () {
    late AppDatabase db;
    late PetsRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = PetsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    group('createPet', () {
      test('Personal scope: pet is created with synced status', () async {
        final int petId = await repo.createPet(
          groupId: 'personal',
          name: 'Taro',
          type: PetType.dog,
          breed: 'shiba',
          sex: PetSex.male,
        );

        expect(petId, greaterThan(0));

        final PetEntity? pet = await repo.getPet(petId);
        expect(pet, isNotNull);
        expect(pet!.name, 'Taro');
        expect(pet.groupId, 'personal');
        expect(pet.syncStatus, SyncStatus.synced);
        expect(pet.sortOrder, 0); // 最初のペット
        expect(pet.deletedAt, isNull);
        expect(pet.partedAt, isNull);
      });

      test('Shared scope: pet is created with pending status + sync_queue entry',
          () async {
        const String groupId = 'group-uuid-abc';
        final int petId = await repo.createPet(
          groupId: groupId,
          name: 'Mike',
          type: PetType.cat,
          breed: 'mix',
          sex: PetSex.female,
        );

        final PetEntity? pet = await repo.getPet(petId);
        expect(pet!.syncStatus, SyncStatus.pending);

        // sync_queueに積まれていること
        final List<SyncQueueItemEntity> queue =
            await db.select(db.syncQueue).get();
        expect(queue.length, 1);
        expect(queue.first.tableName, 'pets');
        expect(queue.first.recordId, petId);
        expect(queue.first.operation, SyncOperation.insert);
      });

      test('sortOrder increments for each new pet in same scope', () async {
        final int id1 = await repo.createPet(
          groupId: 'personal',
          name: 'A',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );
        final int id2 = await repo.createPet(
          groupId: 'personal',
          name: 'B',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );
        final int id3 = await repo.createPet(
          groupId: 'personal',
          name: 'C',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );

        final PetEntity? p1 = await repo.getPet(id1);
        final PetEntity? p2 = await repo.getPet(id2);
        final PetEntity? p3 = await repo.getPet(id3);

        expect(p1!.sortOrder, 0);
        expect(p2!.sortOrder, 1);
        expect(p3!.sortOrder, 2);
      });

      test('rejects empty name', () async {
        expect(
          () => repo.createPet(
            groupId: 'personal',
            name: '',
            type: PetType.dog,
            breed: 'b',
            sex: PetSex.male,
          ),
          throwsArgumentError,
        );
      });

      test('rejects too-long name (>50 chars)', () async {
        final String longName = 'X' * 51;
        expect(
          () => repo.createPet(
            groupId: 'personal',
            name: longName,
            type: PetType.dog,
            breed: 'b',
            sex: PetSex.male,
          ),
          throwsArgumentError,
        );
      });
    });

    group('updatePet', () {
      test('only updates specified fields', () async {
        final int petId = await repo.createPet(
          groupId: 'personal',
          name: 'Taro',
          type: PetType.dog,
          breed: 'shiba',
          sex: PetSex.male,
        );

        final PetEntity? before = await repo.getPet(petId);
        final int beforeUpdatedAt = before!.updatedAt;

        // 少し待ってからupdate (updatedAt変化を確認するため)
        await Future<void>.delayed(const Duration(milliseconds: 5));

        final bool ok = await repo.updatePet(
          petId: petId,
          name: 'Taro Renamed',
        );
        expect(ok, isTrue);

        final PetEntity? after = await repo.getPet(petId);
        expect(after!.name, 'Taro Renamed');
        expect(after.breed, 'shiba'); // 触ってない
        expect(after.updatedAt, greaterThan(beforeUpdatedAt));
      });
    });

    group('updateSortOrder', () {
      test('changes only sortOrder, not updatedAt or syncStatus', () async {
        final int petId = await repo.createPet(
          groupId: 'group-uuid-x',
          name: 'Test',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );

        // 1度syncedに戻して、sortOrder変更が syncStatus に影響しないことを確認
        await db.customStatement(
          'UPDATE pets SET sync_status = ? WHERE id = ?',
          <Object>['synced', petId],
        );

        final PetEntity before = (await repo.getPet(petId))!;
        await Future<void>.delayed(const Duration(milliseconds: 5));

        await repo.updateSortOrder(petId, 99);

        final PetEntity after = (await repo.getPet(petId))!;
        expect(after.sortOrder, 99);
        expect(after.updatedAt, before.updatedAt); // 変わらず
        expect(after.syncStatus, SyncStatus.synced); // 変わらず
      });
    });

    group('markAsParted', () {
      test('rejects future date (rev5.4 F-38a)', () async {
        final int petId = await repo.createPet(
          groupId: 'personal',
          name: 'Taro',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );

        final int future = DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch;

        expect(
          () => repo.markAsParted(petId: petId, partedAtMsec: future),
          throwsArgumentError,
        );
      });

      test('accepts past date and sets memorial notify', () async {
        final int petId = await repo.createPet(
          groupId: 'personal',
          name: 'Hana',
          type: PetType.cat,
          breed: 'persian',
          sex: PetSex.female,
        );

        final int past = DateTime.now()
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch;

        final bool ok = await repo.markAsParted(
          petId: petId,
          partedAtMsec: past,
        );
        expect(ok, isTrue);

        final PetEntity? after = await repo.getPet(petId);
        expect(after!.partedAt, past);
        expect(after.memorialNotify, MemorialNotifyFrequency.monthly);
      });
    });

    group('softDeletePet', () {
      test('sets deletedAt and excludes from active list', () async {
        final int petId = await repo.createPet(
          groupId: 'personal',
          name: 'Doomed',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );

        await repo.softDeletePet(petId);

        final PetEntity? pet = await repo.getPet(petId);
        expect(pet, isNotNull);
        expect(pet!.deletedAt, isNotNull);

        // 一覧からは消える
        final List<PetEntity> active =
            await repo.watchActivePetsInScope('personal').first;
        expect(active.where((PetEntity p) => p.id == petId), isEmpty);
      });
    });

    group('hasPetWithName', () {
      test('detects same-name pet in same scope (rev5.5 同名警告用)',
          () async {
        await repo.createPet(
          groupId: 'group-uuid',
          name: 'Taro',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );

        expect(
          await repo.hasPetWithName(groupId: 'group-uuid', name: 'Taro'),
          isTrue,
        );
        expect(
          await repo.hasPetWithName(groupId: 'group-uuid', name: 'Mike'),
          isFalse,
        );
        // 別スコープには反応しない
        expect(
          await repo.hasPetWithName(groupId: 'personal', name: 'Taro'),
          isFalse,
        );
      });

      test('excludePetId option ignores specific pet', () async {
        final int taroId = await repo.createPet(
          groupId: 'group-uuid',
          name: 'Taro',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );

        // Taro自身を除外すれば、同名なし
        expect(
          await repo.hasPetWithName(
            groupId: 'group-uuid',
            name: 'Taro',
            excludePetId: taroId,
          ),
          isFalse,
        );
      });
    });

    group('watchActivePetsInScope', () {
      test('orders by sortOrder', () async {
        // 逆順にinsertしてもsortOrderの昇順で返る
        final int a = await repo.createPet(
          groupId: 'personal',
          name: 'A',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );
        final int b = await repo.createPet(
          groupId: 'personal',
          name: 'B',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );

        // BをsortOrder=0、AをsortOrder=99に
        await repo.updateSortOrder(b, 0);
        await repo.updateSortOrder(a, 99);

        final List<PetEntity> pets =
            await repo.watchActivePetsInScope('personal').first;

        expect(pets.length, 2);
        expect(pets[0].id, b);
        expect(pets[1].id, a);
      });

      test('excludes parted pets', () async {
        final int aliveId = await repo.createPet(
          groupId: 'personal',
          name: 'Alive',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );
        final int partedId = await repo.createPet(
          groupId: 'personal',
          name: 'Parted',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
        );

        final int past = DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch;
        await repo.markAsParted(petId: partedId, partedAtMsec: past);

        final List<PetEntity> active =
            await repo.watchActivePetsInScope('personal').first;
        expect(active.length, 1);
        expect(active.first.id, aliveId);

        final List<PetEntity> parted =
            await repo.watchPartedPetsInScope('personal').first;
        expect(parted.length, 1);
        expect(parted.first.id, partedId);
      });
    });
  });
}
