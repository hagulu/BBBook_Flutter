import 'package:bbbook/core/policy/attachment_limit_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttachmentLimitPolicy.canAttachNoteImage', () {
    const policy = AttachmentLimitPolicy(
      noteImageLimit: 3,
      reflectionImageLimit: 0,
    );

    test('한도 미만이면 새 이미지 첨부를 허용한다', () {
      expect(
        policy.canAttachNoteImage(
          currentImageMemoCount: 2,
          memoAlreadyHasImage: false,
        ),
        isTrue,
      );
    });

    test('한도에 도달하면 새 이미지 첨부를 막는다', () {
      expect(
        policy.canAttachNoteImage(
          currentImageMemoCount: 3,
          memoAlreadyHasImage: false,
        ),
        isFalse,
      );
    });

    test('한도를 넘겨도 이미 이미지가 있던 메모의 교체는 항상 허용한다', () {
      expect(
        policy.canAttachNoteImage(
          currentImageMemoCount: 3,
          memoAlreadyHasImage: true,
        ),
        isTrue,
      );
    });
  });

  group('AttachmentLimitPolicy.reflectionImageAllowed', () {
    test('한도가 0이면 독후감 이미지 첨부가 허용되지 않는다', () {
      expect(AttachmentLimitPolicy.defaultPolicy.reflectionImageAllowed, isFalse);
    });

    test('한도가 0보다 크면 독후감 이미지 첨부가 허용된다', () {
      const policy = AttachmentLimitPolicy(
        noteImageLimit: 3,
        reflectionImageLimit: 1,
      );
      expect(policy.reflectionImageAllowed, isTrue);
    });
  });
}
