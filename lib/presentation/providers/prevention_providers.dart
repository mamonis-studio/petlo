// ============================================================================
// petlo - Prevention Providers (build 72)
// ============================================================================
//
// 予防コース (フィラリア / ノミダニ) の Repository / 派生 Provider 群。
//
// 無料枠の判定 (§7):
//   コース作成は created_at 昇順で先着 1 件までを無料扱いにする。
//   year 基準にすると「年を変えれば何個でも作れる」抜け道が生まれるため。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/prevention/prevention_notification_scheduler.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/prevention_courses_repository.dart';
import '../../data/repositories/prevention_doses_repository.dart';
import 'database_provider.dart';
import 'pets_providers.dart';
import 'pro_status_provider.dart';
import 'scope_providers.dart';

// ============================================================================
// Repository
// ============================================================================

final Provider<PreventionCoursesRepository> preventionCoursesRepositoryProvider =
    Provider<PreventionCoursesRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return PreventionCoursesRepository(db);
  },
);

final Provider<PreventionDosesRepository> preventionDosesRepositoryProvider =
    Provider<PreventionDosesRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return PreventionDosesRepository(db);
  },
);

// ============================================================================
// 通知
// ============================================================================

final Provider<PreventionNotificationScheduler>
    preventionNotificationSchedulerProvider =
    Provider<PreventionNotificationScheduler>(
  (Ref ref) => PreventionNotificationScheduler(
    service: NotificationService.instance,
    coursesRepo: ref.watch(preventionCoursesRepositoryProvider),
    dosesRepo: ref.watch(preventionDosesRepositoryProvider),
    petsRepo: ref.watch(petsRepositoryProvider),
  ),
);

// ============================================================================
// コース一覧
// ============================================================================

/// 現在グループの予防コース (年の新しい順)
final StreamProvider<List<PreventionCourseEntity>>
    currentGroupPreventionCoursesProvider =
    StreamProvider<List<PreventionCourseEntity>>(
  (Ref ref) {
    final String groupId = ref.watch(currentGroupIdProvider);
    final PreventionCoursesRepository repo =
        ref.watch(preventionCoursesRepositoryProvider);
    return repo.watchForGroup(groupId);
  },
);

/// 選択中ペットの予防コース
final StreamProvider<List<PreventionCourseEntity>>
    currentPetPreventionCoursesProvider =
    StreamProvider<List<PreventionCourseEntity>>(
  (Ref ref) {
    final PreventionCoursesRepository repo =
        ref.watch(preventionCoursesRepositoryProvider);
    final String? petIdRaw = ref.watch(currentPetIdProvider);
    final int? petId = petIdRaw == null ? null : int.tryParse(petIdRaw);
    if (petId == null) {
      return Stream<List<PreventionCourseEntity>>.value(
        const <PreventionCourseEntity>[],
      );
    }
    return repo.watchForPet(petId);
  },
);

/// コース配下の dose (seq 昇順)
final StreamProviderFamily<List<PreventionDoseEntity>, int>
    preventionDosesProvider =
    StreamProviderFamily<List<PreventionDoseEntity>, int>(
  (Ref ref, int courseId) {
    final PreventionDosesRepository repo =
        ref.watch(preventionDosesRepositoryProvider);
    return repo.watchForCourse(courseId);
  },
);

/// コース 1 件
final StreamProviderFamily<PreventionCourseEntity?, int>
    preventionCourseProvider =
    StreamProviderFamily<PreventionCourseEntity?, int>(
  (Ref ref, int courseId) {
    final PreventionCoursesRepository repo =
        ref.watch(preventionCoursesRepositoryProvider);
    final String groupId = ref.watch(currentGroupIdProvider);
    return repo.watchForGroup(groupId).map(
          (List<PreventionCourseEntity> all) =>
              all.where((PreventionCourseEntity c) => c.id == courseId)
                  .firstOrNull,
        );
  },
);

// ============================================================================
// 課金ゲート (§7)
// ============================================================================

/// 新しい予防コースを作成できるか。
/// 無料プランは created_at 昇順で先着 [AppConstants.freeMaxPreventionCourses] 件。
final Provider<bool> canCreatePreventionCourseProvider = Provider<bool>(
  (Ref ref) {
    if (ref.watch(isProProvider)) return true;
    final AsyncValue<List<PreventionCourseEntity>> courses =
        ref.watch(currentGroupPreventionCoursesProvider);
    final int count = courses.valueOrNull?.length ?? 0;
    return count < AppConstants.freeMaxPreventionCourses;
  },
);

/// 無料プランで閲覧できるコース ID の集合。
/// created_at 昇順で先着 N 件だけが開放される。Pro なら全件。
final Provider<Set<int>> unlockedPreventionCourseIdsProvider =
    Provider<Set<int>>(
  (Ref ref) {
    final AsyncValue<List<PreventionCourseEntity>> async =
        ref.watch(currentGroupPreventionCoursesProvider);
    final List<PreventionCourseEntity> courses =
        async.valueOrNull ?? const <PreventionCourseEntity>[];
    if (ref.watch(isProProvider)) {
      return courses.map((PreventionCourseEntity c) => c.id).toSet();
    }
    final List<PreventionCourseEntity> byCreation =
        List<PreventionCourseEntity>.of(courses)
          ..sort((PreventionCourseEntity a, PreventionCourseEntity b) {
            final int c = a.createdAt.compareTo(b.createdAt);
            return c != 0 ? c : a.id.compareTo(b.id);
          });
    return byCreation
        .take(AppConstants.freeMaxPreventionCourses)
        .map((PreventionCourseEntity c) => c.id)
        .toSet();
  },
);

/// 過去年の履歴を閲覧できるか。
/// 無料プランは当年のコースのみ (freePreventionHistoryYears = 1)。
final ProviderFamily<bool, int> canViewPreventionYearProvider =
    ProviderFamily<bool, int>(
  (Ref ref, int year) {
    if (ref.watch(isProProvider)) return true;
    final int currentYear = DateTime.now().year;
    return year >
        currentYear - AppConstants.freePreventionHistoryYears;
  },
);
