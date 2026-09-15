# 리뷰 결과

## 요약
- 계정 간 추천 캐시 격리와 실패 후 재시도는 보완됐지만, 추천 문구 언어·진행 중 동기화 순서·독서 상태 카드 레이아웃 문제가 남아 있습니다.

## 문제점
- [P2] 한국어 앱에서 추천 문구가 영어로 표시됩니다. API 문서는 `message`가 `Accept-Language` 기준이며 헤더가 없으면 영어가 기본이라고 명시하지만, 추천 GET은 `size`와 기록 의존 옵션만 전달합니다(`lib/features/bookshelf/data/recommendation_api.dart:30-34`). 공통 `buildApiBaseOptions()`에도 언어 헤더가 없어(`lib/core/network/api_base_options.dart:7-13`), 서버가 만든 `group.message`를 그대로 그리는 추천 섹션(`lib/features/bookshelf/screens/widgets/recommended_books_section.dart:79-89`)만 나머지 한국어 UI와 다른 언어로 노출됩니다.
- [P2] 기록 동기화가 이미 실행 중이면 추천 요청이 그 완료를 기다리지 않아 이전 기록 기준 응답을 캐시할 수 있습니다. 추천 GET에 `ApiClient.recordDependentOptions()`를 붙였지만(`lib/features/bookshelf/data/recommendation_api.dart:18-34`), 실제 콜백인 `BackgroundRecordSync.beforeNetworkRequest()`는 `_inFlight != null`이면 즉시 반환합니다(`lib/features/record_sync/providers/background_record_sync_provider.dart:82-92`). 앱 시작 시 `MainShell`이 백그라운드 동기화를 먼저 예약하고(`lib/app/main_shell.dart:100-103`, `lib/features/record_sync/providers/background_record_sync_provider.dart:54-58`), 이전 세션에서 남은 dirty 완독 변경을 전송 중인 상태로 빈 탭이 추천을 조회하면 GET이 push보다 먼저 서버에 도착할 수 있습니다. 이 경우 주석이 보장한다고 설명한 “미전송 dirty 변경을 먼저 반영”하는 순서가 실제로는 성립하지 않습니다.
- [P2] 독서 상태 선택 카드의 높이를 줄인 변경은 좁은 화면에서 기본 글자 배율부터 오버플로할 수 있습니다. 바텀시트는 좌우 24dp 패딩을 쓰므로 320dp 화면에서 3열과 열 간격을 제외한 셀 폭은 약 85dp이고, `childAspectRatio: 1.6`이면 높이는 약 53dp로 고정됩니다(`lib/features/book_record/screens/widgets/meta_dialogs.dart:27-35`, `lib/shared/widgets/record_dialog_shell.dart:11-24`). 그러나 셀은 세로 패딩 24dp, 아이콘 20dp, 간격 4dp와 11sp 라벨을 같은 Column에 배치해 기본 배율에서도 약 61dp 이상이 필요합니다(`lib/features/book_record/screens/widgets/icon_option_selector.dart:175-214`). 큰 글자에서는 `잠시 멈춤`·`읽기 중단`의 줄바꿈까지 겹쳐 `RenderFlex` 오버플로가 더 커집니다.

## 개선 제안
- 추천 문구 기본 영어 → 추천 GET에 `Accept-Language: ko`를 명시하거나 앱 locale을 공통 API 헤더로 전달해 서버 문구와 앱 언어를 일치시킵니다.
- 이미 실행 중인 동기화를 건너뜀 → 외부 기록 의존 요청은 기존 `_inFlight`를 기다리고, 동기화 내부에서 발생한 요청만 재귀 대기를 생략할 수 있도록 호출 문맥을 구분합니다. 이 경로는 진행 중 동기화와 추천 GET의 전송 순서를 검증하는 테스트로 고정합니다.
- 고정 비율 카드 높이 부족 → `childAspectRatio` 축소만으로 맞추지 말고 화면 폭과 `MediaQuery.textScalerOf(context)`를 반영한 `mainAxisExtent` 또는 콘텐츠 높이에 따라 늘어나는 배치를 사용합니다.

---

`flutter analyze`를 실행했습니다. 프로젝트 지침에 따라 테스트와 앱 실행은 수행하지 않았습니다.
