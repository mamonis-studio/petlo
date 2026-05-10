// ============================================================================
// petlo - FoodsRepository Tests
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/repositories/foods_repository.dart';

void main() {
  group('FoodsRepository', () {
    late AppDatabase db;
    late FoodsRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = FoodsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('upsertByName creates new food', () async {
      final int id = await repo.upsertByName(
        name: 'Royal Canin',
        brand: 'Royal Canin SAS',
        defaultAmountG: 80,
      );
      expect(id, greaterThan(0));

      final FoodEntity? f = await repo.getById(id);
      expect(f, isNotNull);
      expect(f!.name, 'Royal Canin');
      expect(f.useCount, 1);
    });

    test('upsertByName returns existing id and increments useCount', () async {
      final int id1 = await repo.upsertByName(name: 'Hill\'s');
      final int id2 = await repo.upsertByName(name: 'Hill\'s');

      expect(id1, id2);

      final FoodEntity? f = await repo.getById(id1);
      expect(f!.useCount, 2);
    });

    test('watchRecentFoods returns most-recently-used first', () async {
      // 3つ作って使用順を変える
      await repo.upsertByName(name: 'A');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.upsertByName(name: 'B');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.upsertByName(name: 'C');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Aを再使用 → 最新になる
      await repo.upsertByName(name: 'A');

      final List<FoodEntity> recent = await repo.watchRecentFoods().first;
      expect(recent.length, 3);
      expect(recent[0].name, 'A'); // 一番最近使った
      expect(recent[1].name, 'C');
      expect(recent[2].name, 'B');
    });

    test('watchRecentFoods limits to 3', () async {
      for (int i = 0; i < 5; i++) {
        await repo.upsertByName(name: 'Food $i');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final List<FoodEntity> recent = await repo.watchRecentFoods().first;
      expect(recent.length, 3);
    });

    test('searchByName performs LIKE search', () async {
      await repo.upsertByName(name: 'Royal Canin Indoor');
      await repo.upsertByName(name: 'Royal Canin Outdoor');
      await repo.upsertByName(name: 'Hill\'s Science');

      final List<FoodEntity> royals = await repo.searchByName('Royal');
      expect(royals.length, 2);

      final List<FoodEntity> empty = await repo.searchByName('');
      expect(empty, isEmpty);
    });

    test('findByExactName matches case-sensitively', () async {
      await repo.upsertByName(name: 'Taro Special');

      final FoodEntity? hit = await repo.findByExactName('Taro Special');
      expect(hit, isNotNull);

      final FoodEntity? miss = await repo.findByExactName('taro special');
      expect(miss, isNull);
    });

    test('deleteFood removes the row', () async {
      final int id = await repo.upsertByName(name: 'X');
      expect(await repo.deleteFood(id), isTrue);
      expect(await repo.getById(id), isNull);
    });

    test('touchUsage increments count and updates lastUsedAt', () async {
      final int id = await repo.upsertByName(name: 'Y');
      final FoodEntity? before = await repo.getById(id);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.touchUsage(id);

      final FoodEntity? after = await repo.getById(id);
      expect(after!.useCount, before!.useCount + 1);
      expect(after.lastUsedAt, greaterThan(before.lastUsedAt));
    });
  });
}
