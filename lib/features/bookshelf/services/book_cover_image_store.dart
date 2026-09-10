import '../../../core/storage/local_image_store.dart';

/// 책 표지 이미지의 로컬 파일 저장소.
///
/// 사용자가 고른 표지를 보관한다. 메모/독후감 이미지와 달리 서버에서
/// 내려받는 경로도, 주기적 정리(orphan prune)도 없다 — 표지를 바꾸거나
/// 지울 때 이전 파일만 그 자리에서 지운다.
///
/// 저장한 상대 경로는 로컬 저장 모드에서 `user_book.cover_image_url`에
/// 그대로 들어간다. 서버로 나가는 경로는 로컬 모드에서 모두 막혀 있어 이
/// 값이 그대로 서버로 전송될 일은 없다([BookRecordRepository] 참고) —
/// 서버 저장 모드로 되돌릴 때는 Import가 이 파일을 업로드하고 값을 서버
/// URL로 바꾼다(`RecordImportSnapshotBuilder`).
///
/// **서버 저장 모드에서도 이 폴더의 파일이 참조된다.** 표지를 서버에
/// 올린 책은 `user_book.local_cover_path`(+ 짝이 되는 `local_cover_url`)로
/// 이 사본을 계속 가리켜, 표지를 다시 내려받지 않고 오프라인에서도
/// 보여준다([BookshelfDao] `_rowToBookItem`) — 이 폴더에 orphan 정리를
/// 추가한다면 `cover_image_url`뿐 아니라 `local_cover_path`도 참조로
/// 함께 세어야 한다.
final bookCoverImageStore = LocalImageStore(
  directoryName: 'book_covers',
  logLabel: '책 표지',
);
