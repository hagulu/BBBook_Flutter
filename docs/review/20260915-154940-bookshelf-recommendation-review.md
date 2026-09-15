# 리뷰 결과

## 요약
- 추천 도서 API와 빈 책장 UI의 기본 연결은 문서와 맞지만, 계정 간 캐시 격리·실패 후 재시도·기록 동기화 순서와 큰 글자 레이아웃에 출시 전 보완할 문제가 있습니다.

## 문제점
- [P1] 이전 계정의 추천 결과가 다음 계정에 그대로 노출될 수 있습니다. `bookRecommendationsProvider`는 `BookStatus`만 family 인자로 받고 auto-dispose가 아닌 provider라 응답을 계속 보관하며, 인증 쪽에서는 `canUseAccountFeaturesProvider`의 boolean만 구독합니다(`lib/features/bookshelf/providers/bookshelf_providers.dart:273-293`). 이 boolean은 `!auth.isStandalone`이라 일반 로그아웃의 `authenticated → unauthenticated`와 다른 계정의 `unauthenticated → authenticated` 전환에서 계속 `true`입니다(`lib/features/auth/providers/auth_access_providers.dart:15-22`). 또한 로그아웃·로그인 때 실행되는 `_invalidateRecordCaches()`에도 새 추천 provider가 포함되지 않았습니다(`lib/features/auth/providers/auth_notifier.dart:585-620`). 따라서 A 계정의 빈 탭에서 추천을 받은 뒤 로그아웃하고 B 계정으로 로그인하면, B 계정의 같은 빈 탭이 A 계정의 완독 성향으로 만들어진 메시지와 책을 재사용합니다.
- [P1] 추천 조회가 한 번 실패하면 같은 앱 세션에서는 사용자가 다시 시도할 경로가 없습니다. provider는 모든 예외를 빈 목록이라는 성공값으로 바꿔 캐시합니다(`lib/features/bookshelf/providers/bookshelf_providers.dart:281-293`). 빈 화면의 당겨서 새로고침은 책장·태그 동기화만 수행하고 추천 provider는 무효화하지 않으며(`lib/features/bookshelf/screens/widgets/bookshelf_refresh_indicator.dart:20-43`), 추천 provider 자체도 동기화 버전 등의 갱신 신호를 구독하지 않습니다. 일시적인 오프라인/서버 오류가 해소되어 책장 새로고침은 성공해도 추천 영역은 앱을 완전히 다시 시작할 때까지 빈 상태로 남습니다.
- [P1] 로컬 기록을 바탕으로 서버가 계산하는 추천 요청이 미전송 기록의 동기화를 기다리지 않습니다. API 문서상 추천 카테고리와 제외 도서는 사용자의 완독 기록 및 현재 책장 전체를 기준으로 하지만, 새 GET 호출에는 `ApiClient.recordDependentOptions()`가 없습니다(`lib/features/bookshelf/data/recommendation_api.dart:18-26`). 예를 들어 마지막 읽는 중 책을 방금 완독 처리하면 로컬 탭은 즉시 비어 추천 요청을 시작하지만, 서버 반영은 백그라운드에서 아직 진행 중일 수 있어 이전 완독 성향을 기준으로 응답합니다. `ApiClient`와 `BackgroundRecordSync`에는 이런 기록 의존 요청 전에 dirty 변경을 먼저 전송하는 경로가 이미 마련되어 있고(`lib/core/network/api_client.dart:71-76,121-122`, `lib/features/record_sync/providers/background_record_sync_provider.dart:67-75`), 기존 서재 포함 여부·공개 설정 API도 이를 사용합니다.
- [P2] 독서 상태 선택 카드의 행 높이를 25% 줄인 변경은 큰 글자에서 `RenderFlex` 오버플로를 재발시킵니다. `childAspectRatio`를 `1.2`에서 `1.6`으로 높이면 390dp 화면 기준 카드 높이가 약 68dp로 고정됩니다(`lib/features/book_record/screens/widgets/meta_dialogs.dart:27-35`). 그러나 셀은 세로 패딩 24dp, 아이콘 20dp, 간격 4dp와 배율이 적용되는 라벨을 한 Column에 넣습니다(`lib/features/book_record/screens/widgets/icon_option_selector.dart:136-167`). 기본 글자에서도 남는 높이가 작고 접근성 글자 배율에서는 한 줄 라벨이어도 필요한 높이가 카드 제약을 넘으며, `잠시 멈춤` 같은 라벨이 줄바꿈되면 더 크게 넘칩니다.

## 개선 제안
- 계정 간 추천 캐시 공유 → 추천 provider가 사용자 id를 구독하거나 family 키에 포함하도록 하고, 계정 전환 공통 정리인 `_invalidateRecordCaches()`에서도 명시적으로 무효화합니다. 화면 이탈 뒤 응답을 유지할 이유가 없다면 auto-dispose도 함께 적용합니다.
- 실패가 빈 성공값으로 영구 캐시됨 → 실패 시 기존 빈 화면을 유지하더라도 당겨서 새로고침 완료 시 현재 탭의 추천 provider를 무효화해 재조회하게 합니다. 계정·기록 변경으로 서버 추천 기준이 달라진 때도 같은 갱신 경로를 사용합니다.
- 미전송 기록과 서버 추천의 경합 → 추천 GET에 `ApiClient.recordDependentOptions()`를 전달해 기존 백그라운드 기록 동기화에 합류한 뒤 요청합니다. 동기화 실패 시 오래된 추천을 새 성공값처럼 고정하지 않도록 실패/재시도 정책도 함께 유지합니다.
- 고정 비율 카드의 큰 글자 오버플로 → 단순히 `1.2`로 되돌리는 최소 수정에 그치지 않고 `MediaQuery.textScalerOf(context)`를 반영한 `mainAxisExtent` 또는 콘텐츠 높이에 따라 늘어나는 배치를 사용해 카드 높이가 라벨 배율과 줄 수를 수용하도록 합니다.

---

`flutter analyze`를 실행했습니다. 프로젝트 지침에 따라 테스트와 앱 실행은 수행하지 않았습니다.
