// ============================================================================
// petlo - Notification Scheduler Provider
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_scheduler.dart';
import '../../core/notifications/notification_service.dart';
import 'medication_reminders_providers.dart';
import 'vaccinations_providers.dart';

final Provider<NotificationScheduler> notificationSchedulerProvider =
    Provider<NotificationScheduler>(
  (Ref ref) => NotificationScheduler(
    service: NotificationService.instance,
    remindersRepo: ref.watch(medicationRemindersRepositoryProvider),
    vaccinationsRepo: ref.watch(vaccinationsRepositoryProvider),
  ),
);
