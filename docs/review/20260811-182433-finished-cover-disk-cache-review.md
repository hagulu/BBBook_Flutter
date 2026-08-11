# 리뷰 결과

## 요약

- 월별 그룹 캐시와 keep-alive 적용 방식 자체는 Flutter 생명주기에 맞지만, 완독 표지의 콜드 캐시 성능·탭 전환 시 검색 포커스·이미지 포맷별 리사이즈 보장이 보완되어야 한다.
- 검증: `flutter analyze`는 `No issues found`로 통과했다. 프로젝트 지침에 따라 앱 실행과 테스트는 수행하지 않았다.

## 문제점

- [문제][중간][성능/콜드 캐시] `lib/features/bookshelf/screens/widgets/book_cover.dart:65`~`:70`은 새 카드가 화면에 나타나는 순간 `CachedNetworkImageProvider(maxWidth: ...)`로 리사이즈 파일 생성을 시작한다. 사용 중인 `ImageCacheManager`는 리사이즈 캐시가 없으면 원본을 한 번 디코딩해 크기를 확인하고, 목표 크기로 다시 디코딩한 뒤 PNG 인코딩과 디스크 쓰기를 수행하며, provider는 그 결과 파일을 화면 표시용으로 다시 디코딩한다. 따라서 재방문은 빨라지지만 콜드 캐시에서 긴 완독 목록을 처음 빠르게 스크롤할 때는 기존 `Image.network(cacheWidth: ...)`의 목표 크기 디코딩 한 번보다 훨씬 많은 작업이 스크롤 경로에 추가되어, 해결하려던 첫 스크롤 버벅임을 오히려 키울 수 있다.
- [문제][중간][상태/포커스] `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:70`~`:93`이 완독 탭 State를 항상 keep-alive하므로 `:644`~`:647`의 검색 `TextField`와 `FocusNode`도 탭 밖에서 폐기되지 않는다. 그러나 `lib/features/bookshelf/screens/bookshelf_screen.dart:59`~`:63`의 탭 변경 처리는 탭 바 노출만 복원하고 포커스를 해제하지 않는다. 검색창에 커서를 둔 채 다른 책장 탭을 누르거나 스와이프하면 보이지 않는 검색창이 계속 포커스를 가져 키보드가 남고, 물리 키보드 입력도 숨은 검색어/필터를 변경할 수 있다.
- [문제][낮음][성능/이미지 포맷] `lib/features/bookshelf/screens/widgets/book_cover.dart:65`~`:70`은 `maxWidth`가 모든 표지의 디스크 리사이즈와 표시 디코딩 크기를 제한한다고 가정한다. 하지만 `flutter_cache_manager 3.4.2`의 `ImageCacheManager`는 JPG/JPEG/PNG/TGA/CUR/ICO만 리사이즈하고 WebP/GIF/BMP 또는 확장자를 판별할 수 없는 응답은 원본 파일을 그대로 반환한다. 이때 `CachedNetworkImageProvider.maxWidth`는 Flutter 메모리 디코더의 `cacheWidth`가 아니라 디스크 리사이즈 요청이므로, 해당 표지는 재방문 때도 원본 해상도로 디코딩되어 기존 `Image.network(cacheWidth: ...)`가 제공하던 메모리·GPU 비용 제한이 사라진다. `coverImageUrl` 타입에는 포맷 제약이 없어 실제 데이터에 이런 응답이 들어올 수 있다.

## 개선 제안

- 화면 진입 중 즉시 원본 디코딩·PNG 생성 → 콜드/웜 캐시를 분리해 profile 모드에서 비교한 뒤, 우선 `CachedNetworkImageProvider`로 원본 파일만 디스크 캐시하고 `ResizeImage.resizeIfNeeded`로 표시 디코딩 크기를 제한한다. 리사이즈 파일을 반드시 영속화해야 한다면 현재 화면에 들어오는 카드의 빌드 경로가 아니라 유휴 시점에 제한적으로 생성해 첫 스크롤 프레임과 분리한다.
- 탭 State와 검색 포커스를 함께 영구 유지 → `BookshelfScreen._handleTabChanged()`에서 탭 인덱스가 바뀔 때 현재 primary focus를 해제하거나, 완독 탭에 활성 여부를 전달해 비활성화 시 `_searchFocusNode.unfocus()`를 호출한다. 검색어·필터·스크롤 상태는 그대로 보존하고 키보드 포커스만 해제하면 keep-alive 목적을 유지할 수 있다.
- 디스크 리사이즈 미지원 포맷에서 원본 해상도 디코딩 → 최종 provider를 `ResizeImage.resizeIfNeeded(bucketedCacheWidth, null, provider)`로 감싸 포맷과 무관하게 표시 디코딩 상한을 보장한다. 이 보장은 디스크 리사이즈 파일 생성 여부와 독립적으로 유지해야 한다.
