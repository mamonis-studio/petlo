// ============================================================================
// petlo - sync_service _upsertByPk CASCADE 回帰テスト (build 56)
// ============================================================================
//
// 検証対象 (build 56 案 F 修正):
//   - pet を pull で upsert しても、FK CASCADE で pet_scopes が消えないこと。
//
// 背景:
//   旧 _upsertByPk は `INSERT OR REPLACE INTO ...` で書いていた。SQLite の
//   INSERT OR REPLACE は内部的に「該当行 DELETE → INSERT」を行うため、
//   `pet_scopes.pet_id` が pets(id) への ON DELETE CASCADE FK を持っている
//   この DB では、pets を upsert するたびに pet_scopes が消滅してしまう。
//
//   新 _upsertByPk は `INSERT ... ON CONFLICT(id) DO UPDATE SET ...` 構文に
//   切替済。これは純粋な in-place UPDATE なので CASCADE は発火しない。
//
// 本テストは _upsertByPk が private のため SQL レベルで等価文を実行して
// 動作を比較する。
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

void main() {
  late AppDatabase db;

  setUpAll(() async {
    await PetloLogger.initialize();
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // sync_service の本番経路と同じく FK を有効化する。
    // (AppDatabase.beforeOpen でも有効化しているが、forTesting コンストラクタは
    // beforeOpen を実行しないので念のため明示。)
    await db.customStatement('PRAGMA foreign_keys = ON');
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedPet({String name = 'Mike', String groupId = 'personal'}) {
    final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
    return db.into(db.pets).insert(PetsCompanion.insert(
          groupId: Value(groupId),
          name: name,
          type: PetType.dog,
          createdAt: t,
          updatedAt: t,
        ));
  }

  Future<int> seedScope(int petId, String groupId) {
    final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
    return db.into(db.petScopes).insert(PetScopesCompanion.insert(
          petId: petId,
          groupId: groupId,
          permission: MemberPermission.owner,
          isPrimary: const Value(true),
          sharedAt: t,
          createdAt: t,
          updatedAt: t,
          syncStatus: const Value(SyncStatus.synced),
        ));
  }

  Future<int> countPetScopesForPet(int petId) async {
    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM pet_scopes WHERE pet_id = ?',
          variables: <Variable<Object>>[Variable<int>(petId)],
        )
        .get();
    return rows.first.read<int>('c');
  }

  // --------------------------------------------------------------------------
  // 1. 構造的バグの記録: 旧 INSERT OR REPLACE が CASCADE で
  //    pet_scopes を消すこと自体を確認する(ドキュメント目的)。
  // --------------------------------------------------------------------------
  group('regression: FK CASCADE on pets', () {
    test(
      'INSERT OR REPLACE INTO pets DOES cascade-delete pet_scopes '
      '(documents the bug fixed by build 56)',
      () async {
        final int petId = await seedPet();
        await seedScope(petId, 'personal');
        expect(await countPetScopesForPet(petId), 1);

        // 旧 _upsertByPk の SQL 文と等価。
        final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
        await db.customStatement(
          'INSERT OR REPLACE INTO pets '
          '(id, group_id, name, type, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          <Object?>[petId, 'personal', 'Mike', 'dog', t, t],
        );

        // ↑ この時点で pet_scopes は CASCADE で削除されてしまう。
        // これが build 56 で修正した unwanted behavior。
        expect(
          await countPetScopesForPet(petId),
          0,
          reason:
              'INSERT OR REPLACE triggers DELETE→INSERT which fires '
              'FK CASCADE on pet_scopes. This is the bug build 56 fixes.',
        );
      },
    );

    // ------------------------------------------------------------------------
    // 2. build 56 修正の検証: ON CONFLICT DO UPDATE は CASCADE を発火しない。
    // ------------------------------------------------------------------------
    test(
      'INSERT ... ON CONFLICT(id) DO UPDATE preserves pet_scopes '
      '(build 56 fix)',
      () async {
        final int petId = await seedPet();
        await seedScope(petId, 'personal');
        expect(await countPetScopesForPet(petId), 1);

        // 新 _upsertByPk の SQL 文と等価。
        final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
        await db.customStatement(
          'INSERT INTO pets '
          '(id, group_id, name, type, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(id) DO UPDATE SET '
          'group_id = excluded.group_id, '
          'name = excluded.name, '
          'type = excluded.type, '
          'created_at = excluded.created_at, '
          'updated_at = excluded.updated_at',
          <Object?>[petId, 'personal', 'Mike', 'dog', t, t],
        );

        expect(
          await countPetScopesForPet(petId),
          1,
          reason:
              'UPSERT performs in-place UPDATE without DELETE, so the FK '
              'CASCADE does NOT fire. pet_scopes row stays intact.',
        );
      },
    );

    test(
      'UPSERT 経由でも row 内容は正しく更新される',
      () async {
        final int petId = await seedPet(name: 'OldName');
        await seedScope(petId, 'personal');

        final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
        await db.customStatement(
          'INSERT INTO pets '
          '(id, group_id, name, type, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(id) DO UPDATE SET '
          'group_id = excluded.group_id, '
          'name = excluded.name, '
          'type = excluded.type, '
          'created_at = excluded.created_at, '
          'updated_at = excluded.updated_at',
          <Object?>[petId, 'family-uuid', 'NewName', 'cat', t, t],
        );

        final PetEntity? pet =
            await (db.select(db.pets)..where((t) => t.id.equals(petId)))
                .getSingleOrNull();
        expect(pet, isNotNull);
        expect(pet!.name, 'NewName');
        expect(pet.type, PetType.cat);
        expect(pet.groupId, 'family-uuid');
        // pet_scopes も生きている
        expect(await countPetScopesForPet(petId), 1);
      },
    );
  });
}
