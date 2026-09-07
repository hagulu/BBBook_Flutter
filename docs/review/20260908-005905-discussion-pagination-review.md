# 리뷰 결과

## 요약
- 두 API의 커서/페이지 계약과 구현은 문서에 맞고 `flutter analyze`도 통과했지만, 답변 하이라이트 탐색의 위젯 생명주기 위반과 목록 갱신·삭제 실패 경로의 상태 불일치가 남아 있습니다.

## 문제점
- [문제] [높음] `lib/features/discussion/screens/discussion_detail_screen.dart:406`은 `build()` 도중 `_ensureHighlightVisible()`을 바로 실행합니다. 대상이 첫 페이지에 없으면 이 async 함수는 첫 `await` 전 `lib/features/discussion/providers/discussion_providers.dart:335`의 `state = ...`까지 동기적으로 진행합니다. Riverpod 2.6.1은 위젯 트리를 빌드하는 동안 provider를 수정할 수 없으므로 디버그 실행에서 `Tried to modify a provider while the widget tree was building.` 오류가 발생합니다. 더구나 `discussion_detail_screen.dart:121`에서 그 예외를 삼키고 `:132`에서 검색 완료로 고정하므로, 오래된 내 댓글로 진입할 때 페이지 탐색과 강조가 조용히 중단됩니다.
- [문제] [높음] `lib/features/discussion/providers/discussion_providers.dart:130`은 토론 목록을 새로고칠 때 새 첫 페이지에 포함된 ID만 기존 누적 목록에서 제거하고, 나머지 뒷페이지 항목은 그대로 보존합니다. `lib/features/discussion/screens/discussion_list_screen.dart:81`은 상세에서 수정·닫기·삭제 후 이 메서드를 호출하므로, 두 번째 페이지 이후에서 연 토론을 삭제해도 해당 카드가 계속 남고, "열린 토론" 필터에서 닫은 항목도 사라지지 않으며, 수정한 제목도 갱신되지 않습니다.
- [문제] [보통] `lib/features/discussion/providers/discussion_providers.dart:394`는 답변 삭제 성공 직후 현재 페이지의 `items`만 줄이고 `totalElements`와 `totalPages`는 그대로 둡니다. 이어지는 보정 GET이 실패하면 `:401`에서 예외를 삼킨 채 이 상태를 유지하므로, 화면에는 삭제된 항목이 사라졌는데 전체 답변 수와 페이지 버튼은 삭제 전 값으로 남습니다. 특히 마지막 페이지의 유일한 답변을 지운 경우 빈 현재 페이지와 존재하지 않는 마지막 페이지 버튼이 함께 노출될 수 있습니다.

## 개선 제안
- 빌드 중 하이라이트 탐색 시작 → 답변 상태가 `AsyncData`가 된 뒤 `addPostFrameCallback` 또는 provider 리스너에서 한 번만 탐색을 시작하고, 페이지 조회 실패는 사용자에게 안내한 뒤 재시도할 수 있게 검색 완료 상태를 구분합니다.
- 누적 토론 목록의 첫 페이지만 병합 → 상세에서 돌아올 때 변경된 항목을 ID로 직접 제거·교체하거나, 서버에서 현재까지의 범위를 다시 조회해 누적 목록 전체를 재구성합니다. 열린 토론 필터에서는 닫힌 항목을 즉시 제거합니다.
- 삭제 후 보정 GET 실패 → 낙관적 삭제 시 `totalElements`를 함께 1 감소시키고 계산 가능한 `totalPages`를 갱신하거나, 보정 실패를 표시하고 명시적 재조회 경로를 제공합니다. 페이지 인덱스 변환·마지막 항목 삭제·보정 실패를 provider 테스트로 고정합니다.
