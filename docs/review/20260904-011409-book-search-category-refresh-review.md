# 리뷰 결과

## 요약
- `flutter analyze`는 통과했고 책 검색 응답 모델 변경은 API 문서와 일치하지만, 카테고리 주기 갱신에 처리되지 않은 비동기 예외와 로그인 시 중복 요청이 있고 앱 버전이 이전 값보다 낮아지는 배포 위험이 있습니다.

## 문제점
- [문제] [보통] `lib/app/main_shell.dart:39`와 `lib/app/main_shell.dart:52`는 `_refreshCategoriesIfStale()`을 `unawaited`로 실행하지만, `lib/app/main_shell.dart:62`의 메서드는 저장소/API 예외를 처리하지 않습니다. 오프라인·타임아웃·서버 오류가 발생하면 버려진 Future의 오류가 앱 전역의 처리되지 않은 비동기 예외로 전달됩니다. 같은 카테고리 요청을 수행하는 `lib/features/auth/providers/auth_notifier.dart:228`은 로그인 흐름을 막지 않도록 예외를 잡고 로그를 남기는데, 앱 실행 직후와 포그라운드 복귀 경로에는 그 보호가 빠져 있습니다.
- [문제] [보통] 인증 성공 시 `lib/features/auth/providers/auth_notifier.dart:73`/`:100`이 이미 `refreshCategories()`를 시작한 직후 `MainShell`이 마운트되며 `lib/app/main_shell.dart:39`에서 별도의 `refreshCategoriesIfStale()`을 시작합니다. 저장소에는 책장 동기화 컨트롤러처럼 진행 중 Future를 공유하는 장치가 없고, 첫 요청이 `lib/features/bookshelf/data/book_category_dao.dart:38`의 갱신 시각을 기록하기 전에 두 번째 요청이 시각을 조회하면 두 요청 모두 서버 호출과 캐시 교체를 수행합니다. 특히 로그아웃은 카테고리 목록은 보존하면서 `lib/features/bookshelf/data/bookshelf_database.dart:303`에서 갱신 시각이 든 `sync_meta`를 모두 지우므로 다음 로그인에는 이 중복이 반복됩니다.
- [문제] [보통] `pubspec.yaml:19`에서 앱 버전을 `1.0.0+1`에서 `0.1.1+2`로 변경해 빌드 번호는 증가하지만 사용자에게 표시되는 릴리스 버전은 낮아집니다. 기존 `1.0.0`이 배포·테스트 채널에 한 번이라도 등록됐다면 이후 버전을 `0.1.1`로 이어갈 수 없거나 업데이트가 버전 회귀로 보일 수 있습니다.

## 개선 제안
- 카테고리 갱신 예외 → `_refreshCategoriesIfStale()` 내부에서 예외를 잡아 프로젝트 형식으로 로그를 남기거나, 반환 Future에 오류 처리기를 연결해 생명주기 콜백 밖으로 예외가 새지 않게 합니다.
- 카테고리 중복 요청 → 인증 직후 강제 조회와 `MainShell`의 stale 조회 중 하나를 단일 진입점으로 통합하고, 저장소에는 진행 중 갱신 Future를 공유하는 coalescing을 적용합니다. 24시간 기준을 로그아웃 이후에도 유지하려면 카테고리 갱신 시각을 계정 데이터와 분리해 보존합니다.
- 앱 버전 회귀 → `1.0.0`이 이미 외부에 등록됐다면 `1.0.1+2`처럼 이전 릴리스보다 높은 버전을 사용합니다. 아직 어떤 채널에도 배포하지 않은 초기 개발 단계에서 의도적으로 기준 버전을 다시 잡은 경우에만 현재 값을 유지합니다.
