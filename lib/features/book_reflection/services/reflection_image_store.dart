import '../../../core/storage/local_image_store.dart';

/// 독후감 본문 이미지의 로컬 파일 저장소.
///
/// 서버 `content_json`은 이미지 URL만 갖고 로컬 경로는 모르므로, URL과
/// 로컬 파일의 짝은 로컬 전용 테이블(`reflection_image_local`)이 관리한다
/// ([BookReflectionDao] 참고). 동작은 [LocalImageStore] 참고.
final reflectionImageStore = LocalImageStore(
  directoryName: 'reflection_images',
  logLabel: '독후감 이미지',
);
