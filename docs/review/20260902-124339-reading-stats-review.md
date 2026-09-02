# 리뷰 결과

## 요약
- 통계 계산과 화면 분리는 대체로 적절하지만, 연도 선택 취소가 필터를 바꾸는 기능 오류 1건과 접근성·레이아웃·공통 로딩 정책 문제 3건이 있습니다.

## 문제점
- [문제] `lib/features/profile/screens/widgets/reading_stats_year_picker.dart:22`에서 바텀시트 결과 타입을 `int?`로 두고 "전체" 선택도 `null`로 반환합니다. 모달을 뒤로 가기나 바깥 영역 탭으로 취소할 때도 같은 `null`이 반환되므로, 특정 연도를 선택한 상태에서 시트만 닫아도 `:47`의 `onChanged(null)`이 실행되어 필터가 의도치 않게 "전체"로 바뀝니다.
- [문제] `lib/features/profile/screens/profile_screen.dart:208`의 통계 카드가 `semanticsLabel`을 넘기면 `_SectionCard`가 `:599`에서 모든 하위 시맨틱스를 제외합니다. 따라서 TalkBack/VoiceOver는 완독 권수·읽은 쪽수·많이 읽은 분야 값을 읽지 못하고 "독서 통계" 버튼으로만 인식합니다. 또한 `reading_stats_year_picker.dart:52`도 현재 선택 텍스트를 제외하면서 라벨에 현재 연도를 포함하지 않아 선택 상태를 알 수 없습니다.
- [문제] `lib/features/profile/screens/reading_stats_screen.dart:214`의 요약 카드 3개는 좁은 화면에서도 한 줄에 고정되고, `:273`의 통계 값 `Text`에는 `Flexible`, 줄 수 제한, 오버플로 처리가 없습니다. 읽은 페이지나 메모 값의 자릿수가 커지거나 시스템 글자 크기를 키우면 값과 단위가 카드 폭을 넘어 `RenderFlex overflow`가 발생할 수 있습니다.
- [문제] `lib/features/profile/screens/reading_stats_screen.dart:74`는 화면 전용 `_LoadingState`를 만들어 사용합니다. 프로젝트의 공통 로딩 정책과 달리 `AppLoadingOverlay`를 재사용하지 않아 공통 스피너, `liveRegion`, 로딩 중 시맨틱스 차단 동작이 적용되지 않습니다.

## 개선 제안
- 연도 선택 결과를 `YearSelection(int? year)` 같은 non-null 래퍼로 반환하고, 모달 결과 자체가 `null`이면 취소로 간주해 아무 상태도 변경하지 않습니다. 같은 구분 방식은 기존 `CategorySelection` 구현을 재사용해 맞출 수 있습니다.
- 프로필 통계 카드는 하위 통계 값의 시맨틱스를 유지하거나 카드 라벨에 현재 통계 값을 함께 포함합니다. 연도 선택 버튼 라벨도 "연도 선택, 현재 2026년"처럼 현재 선택을 포함합니다.
- 요약 카드 값 영역을 `Flexible`로 감싸고 `maxLines: 1`과 적절한 오버플로 처리를 적용해 작은 화면과 큰 텍스트 배율에서도 단위와 함께 카드 안에 머물도록 합니다.
- 통계 콘텐츠 영역을 공통 `AppLoadingOverlay`로 감싸 로딩 정책을 통일하고, 화면 제목과 연도 선택기를 계속 노출해야 한다면 해당 헤더는 오버레이 범위 밖에 유지합니다.
