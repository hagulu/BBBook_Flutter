# 리뷰 결과

## 요약
- `flutter analyze`는 통과했지만, 완독 등록의 명작 선택이 오프라인·로컬 저장 모드에서 유실되고 키보드 종료 시 바텀시트가 중복으로 닫힐 수 있으며, 새 아이콘/날짜 조작부에는 접근성 회귀가 있습니다.

## 문제점
- [문제] [높음] `lib/features/book_detail/screens/book_detail_screen.dart:83`과 `lib/features/book_search/screens/widgets/custom_book_dialog.dart:173`은 완독 팝업에서 `isMasterpiece`를 선택해도 생성 결과에 `serverId`가 있을 때만 별도 `RecordPatch`를 적용합니다. 그러나 `BookshelfRepository.createIsbnBook()`/`createCustomBook()`은 로컬 저장 모드이거나 최초 CREATE push가 네트워크 오류로 보류되면 정상적으로 로컬 책을 반환하면서 `serverId == null`일 수 있고, 생성되는 `BookItem`의 `isMasterpiece`는 항상 `false`입니다(`lib/features/bookshelf/data/bookshelf_repository.dart:406`, `lib/features/bookshelf/data/bookshelf_repository.dart:468`). 이 경우 화면은 "서재에 추가되었습니다" 또는 등록 성공으로 끝나지만 사용자가 방금 고른 명작 값은 로컬에도 남지 않아 조용히 유실됩니다.
- [문제] [보통] `lib/features/book_record/screens/widgets/meta_dialogs.dart:739`은 키보드 인셋이 0이 되는 모든 프레임에서 `_save()`를 호출하고, `lib/features/book_record/screens/widgets/meta_dialogs.dart:778`의 `onSubmitted`도 동시에 `_save()`를 호출합니다. 완료 버튼으로 첫 `Navigator.pop()`이 시작된 뒤 키보드가 내려가는 동안 바텀시트 위젯은 역방향 전환이 끝날 때까지 `mounted`일 수 있으므로 두 번째 호출이 들어올 수 있습니다. 이미 popping 상태인 바텀시트는 Navigator의 present route가 아니어서 두 번째 `pop()`이 아래의 책 기록 화면까지 닫을 수 있고, 배경 탭으로 취소하는 경우에도 키보드 인셋 콜백이 입력값을 저장 결과로 반환하는 경합이 생깁니다.
- [문제] [낮음] `lib/features/book_record/screens/widgets/meta_summary_card.dart:120`은 날짜 선택 `InkWell`의 최소 높이를 기존 36에서 30으로 줄였습니다. 텍스트 자체 높이와 세로 패딩을 합쳐도 일반적인 44~48 논리 픽셀 터치 영역을 확보하지 못해, 시작일·완독일을 누르기 어려운 작은 조작부가 됩니다.
- [문제] [낮음] `lib/features/book_record/screens/book_record_screen.dart:732`의 새 `_IconField`는 `InkWell`과 아이콘만으로 명작·또 볼래·난이도를 표현하지만 현재 값에 대한 `Semantics`가 없습니다. 스크린 리더에서는 토글의 켜짐/꺼짐 상태를 알 수 없고, 난이도는 화면에도 "난이도"라는 고정 라벨만 읽혀 쉬움·보통·어려움 중 현재 값이 전달되지 않습니다.

## 개선 제안
- 오프라인·로컬 저장의 명작 유실 → 생성 입력에 `isMasterpiece`를 포함해 최초 로컬 `BookItem`부터 선택값을 보존하고, 서버 CREATE가 이 필드를 받지 않는다면 CREATE 확정 뒤 해당 dirty 필드가 PATCH로 이어지도록 생성 확정 로직을 구성합니다. 로컬 저장 모드에서는 서버 ID와 무관하게 로컬 선택값을 그대로 유지합니다.
- 키보드 종료 시 중복 `pop` → `_isClosing` 같은 일회성 가드와 현재 route 확인으로 `_save()`를 멱등하게 만들고, 배경 닫기와 명시적 완료를 구분합니다. 가능하면 `didChangeMetrics`를 저장 트리거로 쓰지 말고 완료 액션이나 명시적 저장 버튼 한 경로에서만 결과를 반환합니다.
- 날짜 선택 터치 영역 → 시각 높이는 유지하더라도 투명 패딩이나 최소 높이 제약으로 각 날짜 조작부가 최소 44~48 논리 픽셀을 차지하게 합니다.
- 아이콘 필드의 상태 전달 → 명작·또 볼래에는 `Semantics(button: true, toggled: ...)`를 제공하고, 난이도에는 현재 `DifficultyLevel.label`을 semantics 값 또는 보조 텍스트로 전달합니다.
