# 리뷰 결과

## 요약
인증 요청의 기본 보호 장치는 있으나, 일부 명시적 재시도가 네트워크 대기 상태를 해제하지 않습니다. P2 1건입니다. 보안과 화면 생명주기 관련 중요 항목은 소유 기능 문서로 연결했습니다.

## 확인 범위
API 요청 전 세션 준비, 401 refresh/retry, 세션 세대, multipart 재전송, 네트워크 재시도 대기, 토큰 저장, 익명/선택 인증, 이미지 다운로드의 헤더 분리, 전역 Alert/Confirm/Loading, 라우팅과 뒤로 가기를 확인했습니다.

## 문제점

### [NET-01][P2] ‘다시 시도’를 눌러도 15초 대기가 풀리지 않는 화면이 있음

- 근거: [lib/core/network/api_client.dart:233](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/core/network/api_client.dart:233)은 연결/타임아웃/5xx 뒤 전역 `_retryAfter`를 설정하고, [lib/core/network/api_client.dart:157](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/core/network/api_client.dart:157)은 대기 중 요청을 실제 통신 전에 거절합니다. 명시적 재시도용 `requestUserRetry()`가 있으나 [lib/features/book_search/providers/book_search_providers.dart:119](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_search/providers/book_search_providers.dart:119)의 검색 재시도와 [lib/features/book_search/providers/book_search_providers.dart:153](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_search/providers/book_search_providers.dart:153)의 다음 페이지 재시도는 이를 호출하지 않습니다. 책 상세 오류 버튼도 provider invalidate만 합니다.
- 일반 재현: 검색이 연결 오류로 실패한 직후 연결을 복구하고 15초 이내에 ‘다시 시도’를 누릅니다.
- 영향: 네트워크가 복구됐어도 통신 없이 다시 오류가 표시됩니다. 사용자는 재시도 버튼이 작동하지 않는다고 보게 됩니다. 책장 사용자 새로고침은 이미 대기를 해제하므로 화면별 결과도 다릅니다.

## 개선 제안

사용자가 누른 재시도 진입점에서 기존 `requestUserRetry()`를 호출하도록 맞춥니다. 자동 재조회·스크롤마다 대기를 해제하지 말고, 자동 재시도 제한 자체도 제거하지 않습니다.

## 보안 검토 결과와 한계

- 확인한 코드에서는 refresh token이 secure storage에 있고, 이미지 외부 URL 다운로드에 인증 Dio를 재사용하지 않습니다. 일반 로그는 토큰·메모 원문 대신 작업/상태/식별자 중심입니다. 비밀 설정 파일을 출력하거나 수집하지 않았습니다.
- 선택 인증/익명 GET 경로를 구분하고 새 세션에서 이전 응답을 받지 않도록 authGeneration을 검사합니다. 서버 인가의 완전성, 실제 운영 HTTPS 설정, OS 백업·키체인 정책은 이번 정적 앱 리뷰로 보증하지 않습니다.
- 우선 보안 관련 항목은 [INIT-01](../02-sync/20261028-124818-initial-download.md)의 비공개 전환 누락, [REF-01](../04-records/20261028-124818-reflections-editor-visibility.md)의 공개 쓰기 순서, [PROF-01](../07-profile/20261028-124818-profile-settings-stats.md)의 탈퇴 후 로컬 데이터 잔존입니다.
- 모바일 SDK가 요구하는 공개 앱 식별자나 번들 설정값을 그 자체만으로 비밀 유출이라고 지적하지 않았습니다. 이번에 의존성 취약점 네트워크 감사나 서버/배포 환경 감사는 하지 않았습니다.

## 공통 UI·생명주기 관련 검토

[lib/shared/widgets/app_loading.dart:34](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/shared/widgets/app_loading.dart:34)의 Overlay 로딩은 포인터와 semantics를 막지만 route의 뒤로 가기를 직접 차단하지 않습니다. 이를 쓰는 모든 기능이 취소·종료까지 자동으로 보호된다고 가정하면 안 됩니다. 이 경계는 [ADD-01](../04-records/20261028-124818-bookshelf-search-add.md), [COMM-01](../06-community/20261028-124818-discussions.md), [PROF-01](../07-profile/20261028-124818-profile-settings-stats.md)에 필요한 기능별 가드로 다뤘습니다. 모든 로딩에서 전역적으로 뒤로 가기를 금지하는 일괄 변경은 권하지 않습니다.

컨트롤러/listener 해제와 mounted 확인은 다수 구현돼 있습니다. 다만 mounted는 UI 접근의 유효성이지 데이터 작업의 취소 신호가 아니므로, 탈퇴 정리나 서버 확정 처리를 생략하는 근거로 사용하면 안 됩니다.
