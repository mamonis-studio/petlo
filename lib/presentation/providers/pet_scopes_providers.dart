// ============================================================================
// petlo - PetScopes Providers (Phase G4b, build 46)
// ============================================================================
//
// PetScopesRepository へのアクセスと、UI 用の reactive providers。
//
// build 46 (Phase G4b) で導入。G4a までは internal な repository だったが、
// G4b で PetSharePicker / pet detail の `_PetScopesSection` から消費するため
// public な provider セットを設ける。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/pet_scopes_repository.dart';
import 'database_provider.dart';

final Provider<PetScopesRepository> petScopesRepositoryProvider =
    Provider<PetScopesRepository>(
  (Ref ref) => PetScopesRepository(ref.watch(appDatabaseProvider)),
);

/// 指定ペットの生存 scope 一覧 Stream (sharedAt 昇順)。
/// 共有解除 (deleted_at) 行は除外される。
final StreamProviderFamily<List<PetScopeEntity>, int> petScopesForPetProvider =
    StreamProviderFamily<List<PetScopeEntity>, int>(
  (Ref ref, int petId) =>
      ref.watch(petScopesRepositoryProvider).watchPetScopes(petId),
);
