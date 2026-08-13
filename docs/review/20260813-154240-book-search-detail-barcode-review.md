# 리뷰 결과

## 요약

- 책 검색·상세·바코드 등록의 API 경로와 요청 구조는 문서에 맞지만, 서버 변경 성공 뒤 후속 조회·로컬 동기화가 실패한 경우를 구분하지 않아 중복 리뷰 등록과 로컬 표시 불일치가 발생할 수 있다.
- 검증: `flutter analyze`는 `No issues found`로 통과했다. 프로젝트 지침에 따라 앱 실행과 테스트는 수행하지 않았다.

## 문제점

- [문제][중간][데이터/리뷰 등록] `lib/features/book_detail/providers/book_detail_providers.dart:146`~`:157`은 리뷰 POST가 성공한 뒤 첫 페이지 GET까지 성공해야 `submitReview`를 성공으로 완료한다. `lib/features/book_detail/screens/widgets/community_reviews_section.dart:245`~`:261`은 이 전체 Future가 실패하면 입력값을 남기고 등록 오류를 표시한다. 따라서 POST는 저장됐지만 후속 GET만 네트워크 오류로 실패한 경우에도 사용자는 등록이 실패했다고 인식하며, 같은 내용을 다시 눌러 중복 리뷰를 생성할 수 있다.
- [문제][중간][상태/로컬 동기화] `lib/features/bookshelf/providers/bookshelf_providers.dart:84`~`:88`의 `ensureSynced`는 최종 로컬 존재 여부를 `bool`로 반환하지만, `lib/features/book_search/screens/widgets/custom_book_dialog.dart:155`~`:158`, `lib/features/book_detail/screens/book_detail_screen.dart:72`~`:81`, `lib/features/book_search/screens/barcode_scan_screen.dart:128`~`:139`은 반환값을 모두 무시한다. 또한 동기화 예외는 `lib/features/bookshelf/providers/bookshelf_providers.dart:109`~`:112`에서 상태로만 저장되고 Future에는 다시 던져지지 않는다. 서버 등록 후 두 번의 동기화가 모두 실패하면 직접 등록은 로컬에 없는 ID로 책 기록 화면을 열어 “책을 찾을 수 없습니다”를 보여주고, 상세·바코드 등록은 로컬 책장에 책이 없는데도 등록 완료를 표시한다.
- [문제][중간][상태/화면 재진입] `lib/features/book_search/providers/book_search_providers.dart:146`~`:149`의 검색 provider는 `autoDispose`가 아닌 전역 `NotifierProvider`라 화면을 닫아도 마지막 검색어와 결과가 유지된다. 반면 `lib/features/book_search/screens/book_search_screen.dart:22`~`:28`은 화면을 열 때마다 빈 `TextEditingController`를 새로 만든다. 검색 후 화면을 닫았다가 다시 열면 검색창은 비어 있는데 `state.hasQuery`는 true여서 이전 검색 결과가 표시되고, 화면 입력값과 실제 조회 상태가 어긋난다.
- [문제][중간][비동기/좋아요] `lib/features/book_detail/providers/book_detail_providers.dart:210`~`:233`의 좋아요 토글은 일반 네트워크 실패 시 낙관적 상태를 되돌린 뒤 예외를 다시 던진다. 그러나 `lib/features/book_detail/screens/widgets/community_reviews_section.dart:42`~`:47`, `:161`~`:188`은 이 비동기 함수를 `void Function`으로 전달하고 `ReviewItem`의 탭 콜백에서 Future를 기다리거나 오류를 처리하지 않는다. 결과적으로 실패가 처리되지 않은 비동기 예외로 남고 사용자 안내도 없으며, 연속 탭을 막는 상태가 없어 POST와 DELETE 응답 순서에 따라 마지막 탭과 다른 좋아요 상태가 남을 수도 있다.
- [문제][낮음][구조/기능 의존성] 두 기능에서 공유한다고 명시한 `book_category_field.dart`와 `book_thumbnail_field.dart`가 `lib/features/book_record/screens/widgets/`에 있고, `book_search`가 이를 직접 가져온다. `book_detail`과 `book_search`도 별점·선택기·다이얼로그 셸 등 `book_record` 화면 구현에 의존한다. 여러 기능에서 반복 사용하는 UI는 `shared/widgets`에 둔다는 프로젝트 구조 규칙과 달라, 책 기록 화면 내부 구현 변경이 검색·상세 기능까지 전파된다.

## 개선 제안

- 리뷰 생성과 목록 새로고침을 하나의 성공 조건으로 묶음 → POST 성공 즉시 작성 폼은 성공 처리하고, 첫 페이지 갱신은 별도 단계로 실행한다. 갱신 실패 시에는 “리뷰는 등록됐지만 목록을 새로고치지 못했습니다”를 안내하고 POST가 아닌 목록 GET만 다시 시도하게 한다.
- `ensureSynced` 결과를 무시하고 후속 화면·성공 UI를 진행함 → 호출부가 `false`를 명시적으로 처리하게 하거나 동기화 실패를 typed error로 전달한다. 직접 등록은 로컬 행이 확인된 뒤에만 책 기록 화면으로 이동하고, 상세·바코드는 서버 등록 성공과 로컬 갱신 실패를 구분해 재동기화 동작을 제공한다.
- 화면보다 오래 사는 검색 상태와 매번 새로 생성되는 입력 controller를 함께 사용함 → 검색 상태를 화면 수명에 맞춰 `autoDispose`하거나 화면 초기화 시 provider의 `query`로 controller를 복원한다. 상태 보존 여부를 한쪽으로 통일해 입력창과 결과가 항상 같은 검색어를 나타내게 한다.
- 좋아요 Future를 `void` 콜백으로 버리고 중복 요청을 허용함 → 콜백 타입을 `Future<void> Function`으로 유지해 UI에서 await·오류 안내를 처리하고, 리뷰 ID별 요청 중 상태를 두어 완료 전 추가 탭을 막거나 마지막 의도만 직렬 반영한다.
- 기능 간 공유 위젯을 `book_record/screens/widgets`에 둠 → 두 기능 이상에서 사용하는 책 폼 필드와 범용 입력 위젯만 `lib/shared/widgets/`의 적절한 하위 구성으로 옮기고, 기능 전용 다이얼로그는 각 feature에 남겨 의존 방향을 단순화한다.
