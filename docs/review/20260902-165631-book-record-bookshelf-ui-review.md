# 리뷰 결과

## 요약
- `flutter analyze`는 통과했지만, iOS 전역 폰트 지정과 좁은 화면의 커뮤니티 버튼 배치에 플랫폼·레이아웃 회귀가 있고, 한줄 평 표시·완독 필터 초기화·태그 추가 버튼에도 실제 사용성 문제 3건이 있습니다.

## 문제점
- [문제] [보통] `lib/core/theme/app_theme.dart:165`는 iOS에서 전역 `fontFamily`를 `.SF Pro Text`로 덮어씁니다. Flutter 3.44의 `ThemeData`는 `defaultTargetPlatform`을 기준으로 이미 `Typography.material2021`을 구성하고, iOS 본문에는 공식 프록시인 `CupertinoSystemText`, 큰 제목에는 `CupertinoSystemDisplay`를 사용합니다. 현재 지정은 이 플랫폼별 기본값을 모든 텍스트 스타일에서 하나의 비공식 패밀리명으로 교체하므로 큰 제목용 Display 서체 선택을 잃고, OS 버전에서 해당 내부 패밀리명을 직접 찾지 못하면 폴백 서체로 렌더링될 수 있습니다.
- [문제] [보통] `lib/features/book_community/screens/widgets/book_community_preview_section.dart:241`은 검색 상세의 독후감·토론 버튼을 각각 절반 너비로 고정합니다. 일반적인 360dp 화면에서는 각 버튼이 약 158dp이고, `lib/features/book_record/screens/widgets/entry_button.dart:46`의 좌우 패딩과 48dp 아바타·간격·화살표를 빼면 라벨에 약 40dp만 남습니다. 16px 한글 3자인 "독후감"도 이보다 넓어 정상 글자 배율에서 말줄임될 수 있으며, 시스템 글자 크기를 키우거나 개수 배지 자릿수가 늘면 정보가 더 많이 잘립니다.
- [문제] [보통] `lib/features/book_record/screens/widgets/rating_review_card.dart:92`는 최대 2,000자인 `shortReview`를 `maxLines`나 접기 처리 없이 그대로 렌더링합니다. 기존 입력창은 화면에서 최대 3줄만 차지했지만, 이제 긴 한줄 평 하나가 정보 탭에서 수십 줄 높이를 차지해 아래 메타 정보와 태그까지 크게 밀어냅니다.
- [문제] [낮음] `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:672`의 새 필터 초기화 버튼은 provider의 조건만 초기화하고 `_resetScroll()`을 호출하지 않습니다. 이전 초기화 경로는 조건 변경과 함께 목록을 맨 위로 돌렸고, 같은 파일 `:184`도 필터가 바뀌면 결과 구조가 달라지므로 스크롤을 초기화해야 한다고 명시합니다. 현재는 깊이 스크롤한 상태에서 초기화하면 새 결과의 동일 픽셀 위치에 남아 전혀 다른 책부터 보이게 됩니다.
- [문제] [낮음] `lib/features/book_record/screens/widgets/tag_section.dart:90`의 태그 추가 버튼은 16dp 아이콘에 사방 6dp 패딩만 있어 실제 터치 영역이 28×28dp입니다. `Semantics` 라벨은 추가했지만 권장 최소 터치 영역인 48×48dp에 미달해 손 떨림이 있거나 작은 화면을 사용하는 사용자가 정확히 누르기 어렵습니다.

## 개선 제안
- iOS 전역 폰트 지정 → `fontFamily` 오버라이드를 제거하고 Flutter가 선택하는 `CupertinoSystemText`/`CupertinoSystemDisplay`를 그대로 사용합니다. 특정 스타일만 조정해야 한다면 문서화된 두 프록시를 해당 `TextStyle`에만 지정합니다.
- 커뮤니티 진입 버튼 → 작은 폭에서는 기존 세로 배치를 유지하거나 `LayoutBuilder`로 가용 폭을 확인해 가로/세로 배치를 전환합니다. 가로 배치를 유지하려면 전용 compact 규격에서 아바타·패딩을 줄이고 라벨과 개수 배지에 필요한 최소 폭을 보장합니다.
- 한줄 평 표시 → 카드에는 `maxLines`와 `TextOverflow.ellipsis`를 적용해 미리보기 높이를 제한하고, 전체 내용은 현재 편집 바텀시트에서 확인하도록 유지합니다.
- 필터 초기화 → `resetCriteria()`와 `_resetScroll()`을 함께 실행하는 콜백을 `_FinishedTabViewState`에 두고 시트의 초기화 버튼에 전달해 검색어는 유지하면서 목록만 맨 위로 돌립니다.
- 태그 추가 버튼 → `SizedBox`나 `ConstrainedBox`로 최소 48×48dp 터치 영역을 확보하고 원형 배경은 현재 시각 크기를 유지합니다.
