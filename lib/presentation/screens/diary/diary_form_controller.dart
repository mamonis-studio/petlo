// ============================================================================
// petlo - Diary Form Controller
// ============================================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/review/review_prompt_service.dart';
import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/diaries_providers.dart';
import '../../providers/photo_storage_provider.dart';
import '../../providers/pro_status_provider.dart';
import '../../providers/scope_providers.dart';
import '../../widgets/forms/multi_photo_picker.dart';
import 'diary_form_state.dart';

enum DiaryFormSaveOutcome { success, validationFailed, dbError, proLimitReached }

final NotifierProviderFamily<DiaryFormController, DiaryFormState, int?>
    diaryFormControllerProvider =
    NotifierProviderFamily<DiaryFormController, DiaryFormState, int?>(
  DiaryFormController.new,
);

class DiaryFormController extends FamilyNotifier<DiaryFormState, int?> {
  @override
  DiaryFormState build(int? editingDiaryId) {
    if (editingDiaryId == null) {
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId = (petIdStr == null || petIdStr == kAllPetsId)
          ? null
          : int.tryParse(petIdStr);
      return DiaryFormState(
        petId: petId,
        eventAt: DateTime.now(),
      );
    }
    Future<void>.microtask(() => _loadExisting(editingDiaryId));
    return const DiaryFormState();
  }

  Future<void> _loadExisting(int diaryId) async {
    try {
      final repo = ref.read(diariesRepositoryProvider);
      final DiaryEntity? d = await repo.getById(diaryId);
      if (d == null) return;
      state = DiaryFormState.fromExisting(
        diaryId: d.id,
        petId: d.petId,
        title: d.title,
        body: d.body,
        tags: d.tags,
        savedPhotoPaths: d.photoPaths,
        eventAt: DateTime.fromMillisecondsSinceEpoch(d.eventAt),
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to load diary for editing', error: e, stackTrace: st);
    }
  }

  // フィールド更新
  void updateTitle(String v) => state = state.copyWith(title: v);
  void updateBody(String v) => state = state.copyWith(body: v);
  void updateTags(List<String> v) => state = state.copyWith(tags: v);
  void updateEventAt(DateTime? v) => state = state.copyWith(eventAt: v);
  void updatePhotoSlots(List<PhotoSlot> slots) =>
      state = state.copyWith(photoSlots: slots);

  // Save
  Future<DiaryFormSaveOutcome> save(AppLocalizations l10n) async {
    final validated = state.validate(l10n);
    if (validated.errors.hasAny) {
      state = validated;
      return DiaryFormSaveOutcome.validationFailed;
    }
    // build 71: 新規日記時のみ Free 月上限チェック (= freeMaxDiaryPerMonth)。
    if (!state.isEditing && !ref.read(isProProvider)) {
      try {
        final DateTime now = DateTime.now();
        final int monthCount = await ref
            .read(diariesRepositoryProvider)
            .countInMonth(
              groupId: ref.read(currentGroupIdProvider),
              year: now.year,
              month: now.month,
            );
        if (monthCount >= AppConstants.freeMaxDiaryPerMonth) {
          return DiaryFormSaveOutcome.proLimitReached;
        }
      } catch (e, st) {
        PetloLogger.instance
            .w('diary count check failed', error: e, stackTrace: st);
      }
    }
    state = validated.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(diariesRepositoryProvider);
      final photoStorage = ref.read(photoStorageProvider);
      final String groupId = ref.read(currentGroupIdProvider);
      final int t = state.eventAt!.toUtc().millisecondsSinceEpoch;

      // 既存写真のパスを抜き出し(残ってるもの)
      final List<String> keptPaths = state.photoSlots
          .where((s) => s.isExisting)
          .map((s) => s.savedRelativePath!)
          .toList();

      int diaryId;
      if (state.isEditing) {
        await repo.update(
          diaryId: state.editingDiaryId!,
          title: state.title,
          clearTitle: state.title.trim().isEmpty,
          body: state.body,
          tags: state.tags,
          clearTags: state.tags.isEmpty,
          photoPaths: keptPaths.isEmpty ? null : keptPaths,
          clearPhotos: keptPaths.isEmpty,
          eventAtMsec: t,
        );
        diaryId = state.editingDiaryId!;
      } else {
        diaryId = await repo.create(
          groupId: groupId,
          petId: state.petId!,
          title: state.title,
          body: state.body,
          tags: state.tags,
          photoPaths: keptPaths.isEmpty ? null : keptPaths,
          eventAtMsec: t,
        );
        unawaited(ReviewPromptService.instance.onRecordAdded());
      }

      // 新規写真ファイルを順次保存
      final List<String> finalPaths = <String>[...keptPaths];
      int idx = keptPaths.length;
      for (final PhotoSlot slot in state.photoSlots) {
        if (slot.isNew) {
          try {
            final String relPath = await photoStorage.saveDiaryPhoto(
              diaryId: diaryId,
              index: idx,
              source: slot.file!,
            );
            finalPaths.add(relPath);
            idx++;
          } catch (e, st) {
            PetloLogger.instance.w('Failed to save diary photo[$idx]',
                error: e, stackTrace: st);
          }
        }
      }
      if (finalPaths.length != keptPaths.length) {
        await repo.update(
          diaryId: diaryId,
          photoPaths: finalPaths.isEmpty ? null : finalPaths,
          clearPhotos: finalPaths.isEmpty,
        );
      }

      state = state.copyWith(isSubmitting: false);
      return DiaryFormSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to save diary', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return DiaryFormSaveOutcome.dbError;
    }
  }
}
