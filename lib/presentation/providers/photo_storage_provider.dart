// ============================================================================
// petlo - Photo Storage Provider
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage/photo_storage.dart';

final Provider<PhotoStorage> photoStorageProvider = Provider<PhotoStorage>(
  (Ref ref) => PhotoStorage(),
);
