import '../../../core/storage/local_image_store.dart';

/// 메모 사진(PHOTO 메모)의 로컬 파일 저장소.
///
/// `book_note_memo.local_image_path`에 저장하는 상대 경로가 이 폴더를
/// 기준으로 한다. 동작은 [LocalImageStore] 참고 — 독후감 본문 이미지
/// (`reflectionImageStore`)와 폴더만 다르고 규칙은 같다.
final noteMemoImageStore = LocalImageStore(
  directoryName: 'memo_images',
  logLabel: '메모 사진',
);
