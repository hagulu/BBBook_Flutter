# 리뷰 결과

## 요약
- `flutter analyze`와 신규 커뮤니티 API 문서 매핑은 이상 없지만, 독자평 전체 목록의 공감·페이지네이션 비동기 경합과 다이얼로그 이후 생명주기 확인이 필요하다.

## 문제점
- [문제][중간][공감 버튼을 연속으로 누르면 서버와 화면의 최종 상태가 달라질 수 있음] 새 전체 목록은 각 `ReviewItem`의 공감 버튼을 요청 중에도 계속 활성화하고, `ReviewsController.toggleLike()`도 리뷰별 진행 중 요청을 막거나 직렬화하지 않는다. 첫 번째 POST가 끝나기 전에 두 번째 DELETE가 시작되면 각 응답이 호출 시작 시점의 `wasLiked`를 기준으로 최신 항목을 다시 덮어쓴다. 서버 처리 순서와 응답 도착 순서가 엇갈릴 경우 마지막 사용자 입력과 다른 공감 상태가 화면에 남거나 서버 상태와 불일치할 수 있다. (`lib/features/book_detail/screens/book_review_list_screen.dart:60`, `lib/features/book_detail/screens/book_review_list_screen.dart:213`, `lib/features/book_detail/providers/book_detail_providers.dart:221`, `lib/features/book_detail/providers/book_detail_providers.dart:234`)
- [문제][중간][추가 페이지 요청 중 새로고침하면 오래된 페이지가 새 첫 페이지에 합쳐질 수 있음] `loadMore()`는 요청을 시작할 때의 커서로 페이지를 조회한 뒤 완료 시점의 `state.valueOrNull`에 결과를 붙이고, 새로 추가된 `refresh()`는 같은 요청이 진행 중인지 확인하지 않은 채 첫 페이지로 상태를 교체한다. 느린 추가 페이지 요청이 새로고침보다 나중에 끝나면 이전 커서 기준 결과가 새 첫 페이지에 병합된다. 그 사이 새 독자평이 생겨 첫 페이지 경계가 이동했다면 항목이 누락되거나 중복되고, 화면은 이 혼합 상태를 정상 데이터로 유지한다. (`lib/features/book_detail/providers/book_detail_providers.dart:112`, `lib/features/book_detail/providers/book_detail_providers.dart:122`, `lib/features/book_detail/providers/book_detail_providers.dart:251`, `lib/features/book_detail/providers/book_detail_providers.dart:260`)
- [문제][낮음][다이얼로그가 닫힌 뒤 해제된 화면의 `ref`를 읽을 수 있음] 수정·삭제·신고 핸들러는 바텀시트 또는 확인창을 기다린 뒤 결과만 검사하고 곧바로 `ref.read()`를 호출한다. 대기 중 인증 전환이나 상위 라우트 교체로 목록 화면이 제거되면 disposed `ConsumerState`의 `ref` 접근이 런타임 예외를 만들 수 있다. 같은 파일의 API 완료 후 SnackBar에는 `mounted` 검사가 있지만, 첫 번째 상태 접근 전에는 검사가 없다. (`lib/features/book_detail/screens/book_review_list_screen.dart:70`, `lib/features/book_detail/screens/book_review_list_screen.dart:88`, `lib/features/book_detail/screens/book_review_list_screen.dart:106`)

## 개선 제안
- 독자평 공감 연속 요청 → 리뷰 ID별 요청 진행 상태를 두고 완료 전 버튼을 비활성화하거나, 사용자의 최신 목표 상태를 기준으로 요청을 직렬화해 이전 응답이 최신 의도를 덮어쓰지 못하게 한다.
- 추가 로드와 새로고침 경합 → 요청 세대값 또는 요청 커서를 기록하고, 완료 시 현재 세대·커서가 달라졌으면 오래된 결과를 버린다. 또는 새로고침이 진행 중인 추가 로드를 취소·대기한 뒤 첫 페이지 상태만 적용한다.
- 다이얼로그 이후 `ref` 접근 → 수정·삭제·신고 모두 다이얼로그 결과 확인과 함께 `mounted`를 검사한 뒤 provider를 읽는다.
