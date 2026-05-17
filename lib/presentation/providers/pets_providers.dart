// ============================================================================
// petlo - Pets Providers
// ============================================================================
//
// PetsRepository とその派生Provider群。
//
// 階層:
//   Database → PetsRepository → 派生(currentGroupPets, currentPet)
//
// 派生Providerは全画面で使われるため、currentGroupId / currentPetId に
// 自動連動する設計。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/pets_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

// ============================================================================
// Repository本体
// ============================================================================

final Provider<PetsRepository> petsRepositoryProvider = Provider<PetsRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return PetsRepository(db);
  },
);

// ============================================================================
// 派生1: 現在グループのペット一覧 (Stream)
// ============================================================================

/// 現在のスコープ (Personal / Group) のペット一覧。
/// グループ切替時は自動的に再subscribe。
/// メモリアル(parted_at != null)は除外。
final StreamProvider<List<PetEntity>> currentGroupPetsProvider =
    StreamProvider<List<PetEntity>>(
  (Ref ref) {
    final String groupId = ref.watch(currentGroupIdProvider);
    final PetsRepository repo = ref.watch(petsRepositoryProvider);
    return repo.watchActivePetsInScope(groupId);
  },
);

/// 現在グループのお別れ済みペット (メモリアル一覧用)。
final StreamProvider<List<PetEntity>> currentGroupPartedPetsProvider =
    StreamProvider<List<PetEntity>>(
  (Ref ref) {
    final String groupId = ref.watch(currentGroupIdProvider);
    final PetsRepository repo = ref.watch(petsRepositoryProvider);
    return repo.watchPartedPetsInScope(groupId);
  },
);

// ============================================================================
// 派生2: 現在選択中のペット詳細 (Stream)
// ============================================================================

/// 現在 currentPetIdProvider で選択されているペットの詳細。
///
/// 'all' モード時、未選択時、ペットIDが無効な時は AsyncData(null) を返す。
final StreamProvider<PetEntity?> currentPetProvider =
    StreamProvider<PetEntity?>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<PetEntity?>.value(null);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<PetEntity?>.value(null);
    }
    final PetsRepository repo = ref.watch(petsRepositoryProvider);
    return repo.watchPet(petId);
  },
);

// ============================================================================
// 派生 2.5: 任意スコープのペット一覧 (build 20 ペット共有 picker 用)
// ============================================================================

/// 指定 groupId のスコープ内 active ペット一覧。
/// `currentGroupPetsProvider` は currentGroupId に追従するため、
/// 「現在いるグループから personal を覗き見たい」みたいなケースに使う。
final StreamProviderFamily<List<PetEntity>, String> petsInScopeProvider =
    StreamProvider.family<List<PetEntity>, String>(
  (Ref ref, String groupId) {
    final PetsRepository repo = ref.watch(petsRepositoryProvider);
    return repo.watchActivePetsInScope(groupId);
  },
);

// ============================================================================
// 派生3: 「ペットが1匹も登録されていない」判定
// ============================================================================

/// 現在グループにペットが0匹かどうか。
/// オンボーディング初回登録への誘導判定に使う。
final Provider<AsyncValue<bool>> hasNoPetsProvider = Provider<AsyncValue<bool>>(
  (Ref ref) {
    final AsyncValue<List<PetEntity>> pets = ref.watch(currentGroupPetsProvider);
    return pets.whenData((List<PetEntity> list) => list.isEmpty);
  },
);
