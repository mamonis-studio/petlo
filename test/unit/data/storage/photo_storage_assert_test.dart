// ============================================================================
// petlo - PhotoStorage absolute-path 防御ヘルパーのテスト
// ============================================================================
//
// build 40 で導入した assertRelativePhotoPath / assertRelativePhotoPaths が
// 絶対パスを debug ビルドで弾くことを確認する。Release では assert が消える
// のでこのテストもノーオペになる点に注意。
//
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/storage/photo_storage.dart';

void main() {
  group('assertRelativePhotoPath', () {
    test('null is allowed (skip)', () {
      expect(() => assertRelativePhotoPath(null), returnsNormally);
    });

    test('empty string is allowed (not absolute)', () {
      expect(() => assertRelativePhotoPath(''), returnsNormally);
    });

    test('typical relative path passes', () {
      expect(() => assertRelativePhotoPath('pets/42/profile.jpg'),
          returnsNormally);
      expect(() => assertRelativePhotoPath('chat_images/abc-123.jpg'),
          returnsNormally);
      expect(
          () => assertRelativePhotoPath('diaries/9/0.jpg'), returnsNormally);
    });

    test('unix absolute path fails', () {
      expect(
        () => assertRelativePhotoPath(
            '/var/mobile/Containers/Data/Application/UUID/Documents/pets/1/profile.jpg'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('relative-with-leading-dot is treated as relative', () {
      // path パッケージは "./foo" を非 absolute とみなす
      expect(() => assertRelativePhotoPath('./pets/1.jpg'), returnsNormally);
    });
  });

  group('assertRelativePhotoPaths', () {
    test('null is allowed', () {
      expect(() => assertRelativePhotoPaths(null), returnsNormally);
    });

    test('empty list is allowed', () {
      expect(() => assertRelativePhotoPaths(<String>[]), returnsNormally);
    });

    test('all-relative list passes', () {
      expect(
        () => assertRelativePhotoPaths(
            <String>['diaries/1/0.jpg', 'diaries/1/1.jpg']),
        returnsNormally,
      );
    });

    test('list with any absolute element fails', () {
      expect(
        () => assertRelativePhotoPaths(<String>[
          'diaries/1/0.jpg',
          '/var/mobile/.../diaries/1/1.jpg',
        ]),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
