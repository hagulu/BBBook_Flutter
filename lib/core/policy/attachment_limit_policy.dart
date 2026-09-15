import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 노트·독후감 이미지 첨부 가능 여부·한도를 판단하는 정책.
///
/// 지금은 고정값(무료 등급 기준)이지만, 추후 서버가 FREE/PLUS 등 사용자
/// 등급별 한도를 내려주게 되면 이 클래스와 [attachmentLimitPolicyProvider]만
/// 교체하면 된다 — 화면·Repository·API는 이 정책을 통해서만 판단하고 숫자를
/// 직접 하드코딩하지 않는다.
class AttachmentLimitPolicy {
  const AttachmentLimitPolicy({
    required this.noteImageLimit,
    required this.reflectionImageLimit,
  });

  /// 노트 1개당 이미지가 첨부된 메모의 최대 개수.
  final int noteImageLimit;

  /// 독후감에 첨부 가능한 이미지 개수(0이면 첨부 자체가 불가능하다는 뜻).
  ///
  /// 지금은 화면(`book_reflection_editor_screen.dart`)이 [reflectionImageAllowed]
  /// (0 초과 여부)만으로 첨부 버튼·메모 삽입을 막는다 — "이번 편집에서 새로
  /// 추가한 이미지 수"가 아니라 "허용 여부"만 판단한다. 값이 0을 벗어나는
  /// 순간(예: 구독 등급 도입) 기존 저장 이미지와 새로 추가한 이미지를
  /// 구분해 세는 로직이 별도로 필요하다 — 지금은 항상 0이라 구분할 대상
  /// 자체가 없으므로 의도적으로 만들지 않았다.
  final int reflectionImageLimit;

  static const AttachmentLimitPolicy defaultPolicy = AttachmentLimitPolicy(
    noteImageLimit: 3,
    reflectionImageLimit: 0,
  );

  bool get reflectionImageAllowed => reflectionImageLimit > 0;

  /// [currentImageMemoCount]는 노트 안에서 이미지가 첨부된(삭제되지 않은)
  /// 메모의 개수, [memoAlreadyHasImage]는 지금 편집 중인 메모가 이미 그
  /// 개수에 포함돼 있는지 여부다. 기존 이미지를 교체하는 동작은 새로
  /// 개수를 늘리지 않으므로 한도와 무관하게 항상 허용한다.
  bool canAttachNoteImage({
    required int currentImageMemoCount,
    required bool memoAlreadyHasImage,
  }) {
    if (memoAlreadyHasImage) return true;
    return currentImageMemoCount < noteImageLimit;
  }

  String get noteImageLimitMessage =>
      '노트에는 이미지를 최대 $noteImageLimit개까지 첨부할 수 있어요.';

  String get reflectionImageNotAllowedMessage => '독후감에는 이미지를 첨부할 수 없어요.';
}

/// 로컬 DB 쓰기 트랜잭션이 노트 이미지 한도 재검사에서 막았을 때 던지는
/// 예외. 편집 화면을 연 시점의 스냅샷 개수만으로는 그 사이 동기화가 다른
/// 기기의 사진 메모를 반영하는 경계 사례를 막지 못하므로, 실제 로컬 쓰기
/// 직전에 [BookNoteDao]가 다시 한번 원자적으로 개수를 확인한다.
class NoteImageLimitExceededException implements Exception {
  const NoteImageLimitExceededException();
}

/// 서버가 이미지 첨부 제한 위반 시 내려주는 errorCode(ErrorCode enum 이름).
class AttachmentLimitErrorCodes {
  const AttachmentLimitErrorCodes._();

  static const noteImageLimitExceeded = 'NOTE_IMAGE_LIMIT_EXCEEDED';
  static const reflectionImageNotAllowed = 'REFLECTION_IMAGE_NOT_ALLOWED';
}

final attachmentLimitPolicyProvider = Provider<AttachmentLimitPolicy>((ref) {
  return AttachmentLimitPolicy.defaultPolicy;
});
