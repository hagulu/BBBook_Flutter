import '../../../core/storage/local_image_store.dart';

/// 책 표지 이미지의 로컬 파일 저장소.
///
/// 로컬 저장 모드에서 사용자가 고른 표지를 보관한다. 서버 저장 모드에서는
/// 표지가 항상 서버 URL이라 이 저장소를 쓰지 않는다 — 그래서 메모/독후감
/// 이미지와 달리 서버에서 내려받는 경로도, 주기적 정리도 없고, 표지를
/// 바꾸거나 지울 때 이전 파일만 그 자리에서 지운다.
///
/// 저장한 상대 경로는 `user_book.cover_image_url`에 그대로 들어간다(로컬
/// 모드 전용 값이다). 서버로 나가는 경로는 로컬 모드에서 모두 막혀 있어
/// 이 값이 서버로 전송될 일은 없다([BookRecordRepository] 참고).
final bookCoverImageStore = LocalImageStore(
  directoryName: 'book_covers',
  logLabel: '책 표지',
);
