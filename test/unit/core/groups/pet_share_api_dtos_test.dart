// ============================================================================
// petlo - PetShareApiDtos tests (Phase G4a, build 45)
// ============================================================================
//
// PetShareDto.fromJson / PetSharesListDto.fromJson の入力 tolerance を確認。
// Backend (G3-D) が camelCase / snake_case どちらで返してきても扱えること、
// is_primary が 0/1 か true/false でも吸収できることを担保する。
//
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/groups/pet_share_api_dtos.dart';
import 'package:petlo/data/local/database_enums.dart';

void main() {
  group('PetShareDto.fromJson', () {
    test('camelCase canonical form', () {
      final dto = PetShareDto.fromJson(<String, dynamic>{
        'id': 'scope-uuid',
        'petId': 'pet-uuid',
        'groupId': 'group-uuid',
        'permission': 'editor',
        'isPrimary': false,
        'sharedAt': 1748000000000,
        'sharedByUserId': 'user-uuid',
        'deletedAt': null,
      });
      expect(dto.scopeId, 'scope-uuid');
      expect(dto.petServerId, 'pet-uuid');
      expect(dto.groupId, 'group-uuid');
      expect(dto.permission, MemberPermission.editor);
      expect(dto.isPrimary, isFalse);
      expect(dto.sharedAt.millisecondsSinceEpoch, 1748000000000);
      expect(dto.sharedByUserId, 'user-uuid');
      expect(dto.deletedAt, isNull);
    });

    test('isPrimary as integer 1', () {
      final dto = PetShareDto.fromJson(<String, dynamic>{
        'id': 's',
        'petId': 'p',
        'groupId': 'g',
        'permission': 'owner',
        'isPrimary': 1,
        'sharedAt': 0,
      });
      expect(dto.isPrimary, isTrue);
      expect(dto.permission, MemberPermission.owner);
    });

    test('isPrimary as integer 0', () {
      final dto = PetShareDto.fromJson(<String, dynamic>{
        'id': 's',
        'petId': 'p',
        'groupId': 'g',
        'permission': 'viewer',
        'isPrimary': 0,
        'sharedAt': 0,
      });
      expect(dto.isPrimary, isFalse);
      expect(dto.permission, MemberPermission.viewer);
    });

    test('deletedAt as number is parsed', () {
      final dto = PetShareDto.fromJson(<String, dynamic>{
        'id': 's',
        'petId': 'p',
        'groupId': 'g',
        'permission': 'editor',
        'isPrimary': 0,
        'sharedAt': 0,
        'deletedAt': 1748999999999,
      });
      expect(dto.deletedAt, isNotNull);
      expect(dto.deletedAt!.millisecondsSinceEpoch, 1748999999999);
    });

    test('legacy field names (scopeId / petServerId)', () {
      final dto = PetShareDto.fromJson(<String, dynamic>{
        'scopeId': 'legacy-scope',
        'petServerId': 'legacy-pet',
        'groupId': 'g',
        'permission': 'editor',
        'isPrimary': false,
        'sharedAt': 1,
      });
      expect(dto.scopeId, 'legacy-scope');
      expect(dto.petServerId, 'legacy-pet');
    });

    test('unknown permission falls back to editor (safe middle)', () {
      final dto = PetShareDto.fromJson(<String, dynamic>{
        'id': 's',
        'petId': 'p',
        'groupId': 'g',
        'permission': 'admin', // 未知
        'isPrimary': 0,
        'sharedAt': 0,
      });
      expect(dto.permission, MemberPermission.editor);
    });
  });

  group('PetSharesListDto.fromJson', () {
    test('shares array parsed', () {
      final dto = PetSharesListDto.fromJson(<String, dynamic>{
        'shares': <Map<String, dynamic>>[
          {
            'id': 'a',
            'petId': 'p',
            'groupId': 'g1',
            'permission': 'owner',
            'isPrimary': 1,
            'sharedAt': 1,
          },
          {
            'id': 'b',
            'petId': 'p',
            'groupId': 'g2',
            'permission': 'editor',
            'isPrimary': 0,
            'sharedAt': 2,
          },
        ],
      });
      expect(dto.shares.length, 2);
      expect(dto.shares[0].isPrimary, isTrue);
      expect(dto.shares[1].permission, MemberPermission.editor);
    });

    test('missing shares key returns empty list', () {
      final dto = PetSharesListDto.fromJson(<String, dynamic>{});
      expect(dto.shares, isEmpty);
    });

    test('non-map elements filtered out', () {
      final dto = PetSharesListDto.fromJson(<String, dynamic>{
        'shares': <dynamic>[
          {'id': 'a', 'petId': 'p', 'groupId': 'g', 'permission': 'owner',
           'isPrimary': 1, 'sharedAt': 1},
          'bogus',
          42,
        ],
      });
      expect(dto.shares.length, 1);
    });
  });
}
