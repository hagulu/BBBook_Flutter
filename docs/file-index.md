# 파일 인덱스

진입점 역할을 하는 파일만 기록한다. 유틸/하위 컴포넌트/구현 상세는 생략.

## app

- `lib/main.dart` — 앱 진입점
- `lib/app/app.dart` — MaterialApp 루트 위젯
- `lib/app/router.dart` — go_router 라우팅, 인증 상태 기반 redirect(AuthGuard 대응)
- `lib/app/main_shell.dart` — 로그인 후 진입하는 하단 탭 셸(HOME/BOOKSHELF/PROFILE), 기본 탭은 BOOKSHELF, 포그라운드 전환 시 동기화 트리거

## core

- `lib/core/theme/app_theme.dart` — 색상 토큰(AppColors)/ThemeData 정의(app·feature가 공통 참조)
- `lib/core/network/api_client.dart` — 공통 API 클라이언트, 401 시 refresh 1회 재시도 후 실패하면 로그아웃 처리
- `lib/core/network/api_base_options.dart` — API 공통 base URL/timeout 정의(ApiClient·인증 전용 Dio 공유)
- `lib/core/storage/token_storage.dart` — refreshToken 시큐어 스토리지 래퍼
- `lib/core/storage/client_id_storage.dart` — X-Client-Id 헤더용 설치 단위 클라이언트 식별자(UUID) 저장/재사용

## features/auth

- `lib/features/auth/screens/onboarding_screen.dart` — 온보딩(로그인) 화면
- `lib/features/auth/providers/auth_notifier.dart` — 전역 인증 상태(AuthProvider 대응), 앱 시작 시 자동 refresh
- `lib/features/auth/data/auth_repository.dart` — 인증 세션 source of truth(API·시큐어 스토리지·소셜 SDK 오케스트레이션)
- `lib/features/auth/data/auth_api.dart` — 인증 API 호출(로그인/refresh/logout/getMe)
- `lib/features/auth/data/social_auth_service.dart` — Google/Apple 네이티브 로그인
- `lib/features/auth/widgets/auth_loading_gate.dart` — 인증 확인 중 빈 배경 표시(AuthGuard 대응)

## features/home

- `lib/features/home/screens/home_tab_placeholder.dart` — 홈 탭 임시 화면(TODO: home-feed 기능 포팅 후 교체)

## features/profile

- `lib/features/profile/screens/profile_tab_placeholder.dart` — 프로필 탭 임시 화면(TODO: profile 기능 포팅 후 교체), 로그아웃 진입점

## features/bookshelf

- `lib/features/bookshelf/screens/bookshelf_screen.dart` — 책장 탭 콘텐츠(읽는 중/완독/읽고 싶음/중단 4탭)
- `lib/features/bookshelf/data/bookshelf_api.dart` — 책장 API 호출(전체 동기화, 증분 동기화, 완독 공개 설정 조회/수정)
- `lib/features/bookshelf/data/bookshelf_database.dart` — 로컬 DB(sqflite) 스키마(user_book/user_book_tag/sync_meta)
- `lib/features/bookshelf/data/bookshelf_dao.dart` — 로컬 DB 쿼리·동기화 reconcile/applyChanges(dirty 행 보호)
- `lib/features/bookshelf/data/bookshelf_repository.dart` — 책장 기능 source of truth(화면은 항상 이 레포지토리의 로컬 조회만 사용), 최초엔 전체·이후엔 증분 동기화
- `lib/features/bookshelf/providers/bookshelf_providers.dart` — 책장 관련 Riverpod provider(동기화 컨트롤러, 탭별 목록, 완독 필터, 공개 설정)

## features/book_record

- `lib/features/book_record/screens/book_record_screen.dart` — 책 기록 상세 화면(자체 AppBar, 책장에서 책 선택 시 진입), 정보/진행률/상태/출처/난이도/태그/삭제 조립
- `lib/features/book_record/data/book_record_api.dart` — 책 기록 API 호출(기본 정보 PATCH, 책 정보 PATCH, 태그 POST/DELETE, 태그 목록/플랫폼 옵션 GET, 삭제 DELETE)
- `lib/features/book_record/data/book_record_repository.dart` — 책 기록 화면 source of truth(로컬 조회는 bookshelf 레포지토리 재사용, 수정은 서버 PATCH 성공 후 로컬 반영)
- `lib/features/book_record/providers/book_record_providers.dart` — 책 기록 관련 Riverpod provider(단일 책 상태 컨트롤러, 태그 자동완성, 플랫폼 옵션)

## shared/widgets

- `lib/shared/widgets/app_alert.dart` — 공통 Alert 팝업(제목/내용/확인 버튼)
- `lib/shared/widgets/app_confirm.dart` — 공통 Confirm 팝업(확인/취소, Future<bool> 반환)
- `lib/shared/widgets/app_loading.dart` — 공통 Loading(전체 화면 `AppLoading`, 영역 단위 `AppLoadingOverlay`)

## docs

- `docs/review/20260806-174318-initial-implementation-review.md` — 최초 구현의 구조·인증·공통 컴포넌트 심층 리뷰
- `docs/review/20260807-141513-shared-dialog-loading-review.md` — 공통 Alert/Confirm/Loading 컴포넌트 리뷰
- `docs/review/20260807-165007-finished-list-scroll-performance-review.md` — 완독 목록 스크롤 성능 병목과 튜닝 우선순위 리뷰
- `docs/review/20260807-202727-bookshelf-implementation-review.md` — 책장 구현의 계정 데이터 격리·동기화 상태·접근성 리뷰
- `docs/review/20260807-232503-book-record-and-bookshelf-review.md` — 책 기록 상세와 책장 후속 변경의 상태 최신성·동시성·포팅 누락 리뷰
- `docs/review/20260808-001248-book-record-followup-review.md` — 책 기록 후속 수정의 계정 격리·포팅 범위·상태 정합성 재리뷰
- `docs/review/20260808-172540-book-record-third-review.md` — 책 기록 추가 변경의 세션 경합·난이도 규격·접근성 재리뷰
- `docs/review/20260810-153456-book-record-layout-review.md` — 책 기록 UI 재배치의 슬라이더 렌더링·접근성 리뷰
- `docs/review/20260810-163411-book-record-status-and-icon-review.md` — 책 기록 상태 선택의 접근성·아이콘 정책 재리뷰
- `docs/review/20260810-171825-book-record-tag-interaction-review.md` — 책 기록 태그 추천의 스크롤·렌더링·요청과 진행 쪽수 입력 접근성 리뷰
