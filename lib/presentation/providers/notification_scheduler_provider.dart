// ============================================================================
// petlo - Notification Scheduler Provider
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_scheduler.dart';
import '../../core/notifications/notification_service.dart';
import 'schedules_providers.dart';
import 'vaccinations_providers.dart';

final Provider<NotificationScheduler> notificationSchedulerProvider =
    Provider<NotificationScheduler>(
  (Ref ref) => NotificationScheduler(
    service: NotificationService.instance,
    schedulesRepo: ref.watch(schedulesRepositoryProvider),
    vaccinationsRepo: ref.watch(vaccinationsRepositoryProvider),
  ),
);
