# 리뷰 결과

## 요약

- 현재 미커밋 변경사항을 검토한 결과, 저장 정합성 2건과 레이아웃 2건을 확인했다. `flutter analyze`는 통과했다.
- 코드와 호출 경로를 기준으로 검토했으며 앱 실행·테스트는 수행하지 않았다. 기존 변경사항은 수정하지 않았다.

## 문제점

- [P2 문제] 오프라인 완독 등록에서 명작 선택이 유실된다.
  - 위치: `lib/features/book_detail/screens/book_detail_screen.dart:87`, `lib/features/book_search/screens/widgets/custom_book_dialog.dart:175`
  - 서버 저장 모드에서 CREATE가 네트워크 오류로 대기하면 `serverId == null`이므로 명작 저장을 건너뛴다. 생성 레포지토리는 `isMasterpiece: false`로 로컬 행을 만들기 때문에 사용자가 선택한 true는 로컬에도, 재시도할 변경사항에도 남지 않는다. 등록은 성공으로 안내되어 사용자가 유실을 알 수 없다. 이전 리뷰에서 지적한 문제는 로컬 저장 모드에 대해서만 보완된 상태다.

- [P2 문제] 완독 팝업에서 오디오북을 선택해도 이전 쪽수 기준으로 진행률을 저장한다.
  - 위치: `lib/features/book_record/screens/book_record_screen.dart:596`, `lib/features/book_record/screens/book_record_screen.dart:604`
  - 책 유형이 미설정인 책은 완독 팝업에서 오디오북을 선택할 수 있다. 그러나 `currentPage`는 선택 전 `book.progressUpperBound`로 계산하고 `sourceType`만 선택 결과로 바꾼다. 예를 들어 총 80쪽인 책이면 오디오북 완독 기록에 80%가 저장되고, 300쪽이면 300이 저장된다. 총쪽수가 없으면 기존 진행 값이 유지된다. `BookItem.copyWithRecord`도 두 필드를 그대로 적용하여 단위를 보정하지 않는다.

- [P2 문제] 독서 상태 선택 그리드의 높이가 셀 콘텐츠보다 작다.
  - 위치: `lib/features/book_record/screens/widgets/meta_dialogs.dart:28`, `lib/features/book_record/screens/widgets/icon_option_selector.dart:174`
  - 3열에 `childAspectRatio: 1.8`을 적용하지만 셀에는 세로 패딩 24dp, 아이콘, 간격 4dp, 라벨이 필요하다. 360dp 화면에서는 패딩을 전혀 제외하지 않아도 셀 높이가 약 64dp 이하이고, 실제 시트 좌우 패딩까지 제외하면 더 작아진다. 내부 Column의 고정 콘텐츠가 이를 초과해 세로 overflow가 발생하는 구조다. `minHeight: 48`은 그리드의 고정 높이를 늘리지 못한다.

- [P2 문제] 상태 요약을 반쪽 폭에 배치하면서 라벨 줄바꿈을 막아 가로 overflow가 발생한다.
  - 위치: `lib/features/book_record/screens/book_record_screen.dart:188`, `lib/features/book_record/screens/widgets/reading_status_tile.dart:54`
  - 읽는 중·중단 등의 상태에서 책 유형과 폭을 절반씩 나누고, 상태 영역 안에서도 원형 아이콘 48dp와 간격 14dp를 먼저 사용한다. 360dp 화면 기준 외부 여백 32dp, 카드 패딩 32dp, 구분선과 여백 25dp를 빼면 상태 영역은 약 135.5dp이고 텍스트에는 약 73.5dp만 남는다. 내부 Row의 Text는 폭 제한이나 줄바꿈을 받지 않아 `잠시 멈춤`, `읽기 중단` 같은 16sp 라벨이 넘친다. 완독 횟수를 함께 표시하거나 글자 크기를 키우면 더 악화된다.

## 개선 제안

- 명작 선택 유실 → 생성 단계부터 선택값을 로컬에 보존하고, CREATE 응답 반영 뒤 별도 PATCH가 필요한 필드를 유지·재시도하도록 처리한다. CREATE 성공 여부에 따라 입력을 버리지 않는다.
- 진행률 단위 불일치 → 선택 결과를 반영한 최종 책 유형 기준으로 완독 진행값을 계산한다. 오디오북이면 100, 그 외는 유효한 전체 쪽수를 사용한다.
- 상태 그리드 높이 부족 → 고정 종횡비를 조정하거나 콘텐츠와 텍스트 배율을 수용하는 행 높이를 사용한다.
- 상태 요약 폭 부족 → 라벨과 횟수에 유연한 줄바꿈을 적용하고, 좁은 폭에서는 아이콘 크기·간격 또는 책 유형과의 배치를 조정한다.
