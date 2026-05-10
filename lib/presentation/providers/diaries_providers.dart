// ============================================================================
// petlo - Diaries Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/diaries_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

final Provider<DiariesRepository> diariesRepositoryProvider =
    Provider<DiariesRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return DiariesRepository(db);
  },
);

/// 現在ペットの日記(新しい順)
final StreamProvider<List<DiaryEntity>> currentPetDiariesProvider =
    StreamProvider<List<DiaryEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<DiaryEntity>>.value(<DiaryEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<DiaryEntity>>.value(<DiaryEntity>[]);
    }
    final DiariesRepository repo = ref.watch(diariesRepositoryProvider);
    return repo.watchForPet(petId);
  },
);

/// ホーム表示用の最新3件
final StreamProvider<List<DiaryEntity>> recentDiariesForHomeProvider =
    StreamProvider<List<DiaryEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<DiaryEntity>>.value(<DiaryEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<DiaryEntity>>.value(<DiaryEntity>[]);
    }
    final DiariesRepository repo = ref.watch(diariesRepositoryProvider);
    return repo.watchForPet(petId, limit: 3);
  },
);

/// 写真付き日記のみ(ギャラリー画面用)
final StreamProvider<List<DiaryEntity>>
    currentPetDiariesWithPhotosProvider =
    StreamProvider<List<DiaryEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<DiaryEntity>>.value(<DiaryEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<DiaryEntity>>.value(<DiaryEntity>[]);
    }
    final DiariesRepository repo = ref.watch(diariesRepositoryProvider);
    return repo.watchWithPhotos(petId);
  },
);
