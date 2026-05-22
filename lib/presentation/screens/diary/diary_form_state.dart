// ============================================================================
// petlo - Diary Form State
// ============================================================================

import 'package:flutter/foundation.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../widgets/forms/multi_photo_picker.dart';

@immutable
class DiaryFormErrors {
  const DiaryFormErrors({this.body, this.eventAt});

  final String? body;
  final String? eventAt;

  bool get hasAny => body != null || eventAt != null;
}

@immutable
class DiaryFormState {
  const DiaryFormState({
    this.editingDiaryId,
    this.petId,
    this.title = '',
    this.body = '',
    this.tags = const <String>[],
    this.photoSlots = const <PhotoSlot>[],
    this.eventAt,
    this.isSubmitting = false,
    this.errors = const DiaryFormErrors(),
  });

  final int? editingDiaryId;
  final int? petId;
  final String title;
  final String body;
  final List<String> tags;
  final List<PhotoSlot> photoSlots;
  final DateTime? eventAt;
  final bool isSubmitting;
  final DiaryFormErrors errors;

  bool get isEditing => editingDiaryId != null;

  DiaryFormState validate(AppLocalizations l10n) {
    final errs = DiaryFormErrors(
      body: body.trim().isEmpty ? l10n.diary_validation_body_required : null,
      eventAt: eventAt == null
          ? l10n.diary_validation_date_required
          : (eventAt!.isAfter(DateTime.now().add(const Duration(days: 1)))
              ? l10n.visit_validation_future_date
              : null),
    );
    return copyWith(errors: errs);
  }

  static DiaryFormState fromExisting({
    required int diaryId,
    required int petId,
    String? title,
    required String body,
    List<String>? tags,
    List<String>? savedPhotoPaths,
    required DateTime eventAt,
  }) {
    return DiaryFormState(
      editingDiaryId: diaryId,
      petId: petId,
      title: title ?? '',
      body: body,
      tags: tags ?? <String>[],
      photoSlots: (savedPhotoPaths ?? <String>[])
          .map((String p) => PhotoSlot(savedRelativePath: p))
          .toList(),
      eventAt: eventAt,
    );
  }

  DiaryFormState copyWith({
    Object? editingDiaryId = _sentinel,
    Object? petId = _sentinel,
    String? title,
    String? body,
    List<String>? tags,
    List<PhotoSlot>? photoSlots,
    Object? eventAt = _sentinel,
    bool? isSubmitting,
    DiaryFormErrors? errors,
  }) {
    return DiaryFormState(
      editingDiaryId: editingDiaryId == _sentinel
          ? this.editingDiaryId
          : editingDiaryId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      title: title ?? this.title,
      body: body ?? this.body,
      tags: tags ?? this.tags,
      photoSlots: photoSlots ?? this.photoSlots,
      eventAt: eventAt == _sentinel ? this.eventAt : eventAt as DateTime?,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errors: errors ?? this.errors,
    );
  }

  static const Object _sentinel = Object();
}
