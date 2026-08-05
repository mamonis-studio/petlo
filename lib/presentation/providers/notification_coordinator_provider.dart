// ============================================================================
// petlo - Notification Coordinator Provider (build 73)
// ============================================================================
//
// 3 系統の合計を見て 64 枠に収める唯一の入口。
// 通知に影響する操作のあとは必ずこれを呼ぶ。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_coordinator.dart';
import '../../core/notifications/notification_service.dart';
import 'pets_providers.dart';
import 'prevention_providers.dart';
import 'schedules_providers.dart';
import 'vaccinations_providers.dart';

final Provider<NotificationCoordinator> notificationCoordinatorProvider =
    Provider<NotificationCoordinator>(
  (Ref ref) => NotificationCoordinator(
    service: NotificationService.instance,
    schedulesRepo: ref.watch(schedulesRepositoryProvider),
    vaccinationsRepo: ref.watch(vaccinationsRepositoryProvider),
    preventionCoursesRepo: ref.watch(preventionCoursesRepositoryProvider),
    preventionDosesRepo: ref.watch(preventionDosesRepositoryProvider),
    petsRepo: ref.watch(petsRepositoryProvider),
  ),
);
