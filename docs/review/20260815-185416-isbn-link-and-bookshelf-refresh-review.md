# 리뷰 결과

## 요약
- ISBN 연결 API 규격과 정적 분석에는 문제가 없지만, 책 정보 저장의 부분 성공과 표지 미반영, 완독 필터 결과의 상태 불일치 가능성을 보완해야 한다.

## 문제점
- [상태 정합성][높음] `lib/features/book_record/screens/widgets/book_info_edit_dialog.dart:136`~`:155`는 저장 한 번을 ISBN 연결 PATCH와 책 정보 PATCH 두 번으로 나눠 실행한다. 첫 번째 `linkBook()`이 성공한 뒤 두 번째 `updateBookInfo()`가 네트워크·이미지 업로드·입력 검증 오류로 실패하면 ISBN과 공용 책의 표시 정보는 이미 서버와 로컬에 반영됐지만 팝업에는 저장 실패만 표시된다. 사용자가 팝업을 닫으면 저장 전체가 실패했다고 인식한 상태에서 책 연결은 변경된 채 남으며, 재시도할 때도 `widget.book.isbn13`은 최초 값이라 연결 PATCH가 다시 실행된다.
- [기능 누락][중간] `lib/features/book_record/screens/widgets/book_info_edit_dialog.dart:176`~`:177`의 "불러오기"는 같은 ISBN의 상세를 조회해 `:215`에서 새 `coverUrl`을 미리보기에 넣지만, ISBN이 기존 값과 같아 `:136`의 `linkBook()`을 실행하지 않는다. 이어지는 `updateBookInfo()`와 `lib/features/book_record/data/book_record_api.dart:113`~`:119`의 요청에도 `coverImageUrl`이 없으므로 제목·저자 등은 저장돼도 새 표지는 서버에 반영되지 않고 팝업을 닫은 뒤 기존 표지로 돌아온다. 변경 검색에서 기존 ISBN을 다시 선택한 경우도 같다.
- [상태 표시][중간] `finishedBooksProvider`는 `lib/features/bookshelf/providers/bookshelf_providers.dart:190`에서 필터 자체를 의존성으로 사용한다. 필터를 바꾸면 새 쿼리가 로딩되는 동안 `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:360`의 `valueOrNull`에는 이전 필터 결과가 남는데, 화면은 이를 현재 필터의 결과로 그대로 렌더링한다. 새 쿼리가 실패해 `AsyncError`가 이전 값을 보존하면 `items != null` 분기로 들어가 오류·재시도 UI도 표시되지 않아, 선택한 필터와 다른 목록이 계속 남을 수 있다.

## 개선 제안
- 하나의 저장 동작이 두 API 사이에서 부분 성공함 → ISBN 연결을 저장과 별개의 즉시 반영 액션으로 명확히 표시하고 성공 후 팝업의 기준값을 갱신하거나, 연결과 display 정보 수정을 원자적으로 처리하는 API를 마련한다. 현재처럼 하나의 저장으로 제공하려면 두 번째 요청 실패 시 부분 반영 상태를 사용자에게 명확히 알리고 안전한 재시도·복구 흐름을 제공한다.
- 동일 ISBN 재불러오기에서 표지 URL이 저장되지 않음 → 재불러오기 의도를 별도로 추적해 같은 ISBN이어도 문서상 허용된 재연결 PATCH를 실행하거나, `book-info` 요청에 조회한 `coverImageUrl`을 명시적으로 포함한다.
- 새 필터에 이전 필터 결과를 재사용함 → 결과가 어떤 `FinishedFilter`에서 생성됐는지 함께 보존해 현재 필터와 같을 때만 이전 값을 사용한다. 예를 들어 필터를 키로 받는 `autoDispose.family` provider로 분리하면 같은 필터의 동기화 재조회에서는 기존 목록을 유지하면서 다른 필터로 전환할 때는 이전 결과를 섞지 않을 수 있다.
