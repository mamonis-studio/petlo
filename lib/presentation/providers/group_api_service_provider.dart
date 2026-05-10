// ============================================================================
// petlo - Group API Service Provider
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/groups/group_api_service.dart';

final Provider<GroupApiService> groupApiServiceProvider =
    Provider<GroupApiService>((Ref ref) => GroupApiService());
