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

- `lib/features/bookshelf/screens/bookshelf_screen.dart` — 책장 탭 콘텐츠(읽고 싶음/읽는 중/완독/중단 4탭, 기본은 읽는 중)
- `lib/features/bookshelf/data/bookshelf_api.dart` — 책장 API 호출(전체 동기화, 증분 동기화, 완독 공개 설정 조회/수정, 카테고리 목록 GET)
- `lib/features/bookshelf/data/bookshelf_database.dart` — 로컬 DB(sqflite) 스키마(user_book/user_book_tag/sync_meta/book_category, v3)
- `lib/features/bookshelf/data/bookshelf_dao.dart` — 로컬 DB 쿼리·동기화 reconcile/applyChanges(dirty 행 보호)
- `lib/features/bookshelf/data/book_category_dao.dart` — 카테고리 마스터 목록 로컬 캐시 DAO(계정 무관, 로그아웃 시에도 유지)
- `lib/features/bookshelf/data/bookshelf_repository.dart` — 책장 기능 source of truth(화면은 항상 이 레포지토리의 로컬 조회만 사용), 최초엔 전체·이후엔 증분 동기화, 카테고리는 로컬 캐시 우선 조회
- `lib/features/bookshelf/data/finished_cover_cache_manager.dart` — 완독 목록 표지 전용 디스크 캐시(원본 바이트 저장, 디코딩 크기 제한은 `BookCover`의 `ResizeImage`가 담당)
- `lib/features/bookshelf/providers/bookshelf_providers.dart` — 책장 관련 Riverpod provider(동기화 컨트롤러, 탭별 목록, 완독 필터, 공개 설정, 카테고리 목록)

## features/book_record

- `lib/features/book_record/screens/book_record_screen.dart` — 책 기록 상세 화면(자체 AppBar, 책장에서 책 선택 시 진입), 정보/진행률/상태/출처/난이도/태그/삭제 조립
- `lib/features/book_record/data/book_record_api.dart` — 책 기록 API 호출(기본 정보 PATCH, 책 정보 PATCH(카테고리 포함), 태그 POST/DELETE, 태그 목록/플랫폼 옵션 GET, 삭제 DELETE)
- `lib/features/book_record/data/book_record_repository.dart` — 책 기록 화면 source of truth(로컬 조회는 bookshelf 레포지토리 재사용, 수정은 서버 PATCH 성공 후 로컬 반영)
- `lib/features/book_record/providers/book_record_providers.dart` — 책 기록 관련 Riverpod provider(단일 책 상태 컨트롤러, 태그 자동완성, 플랫폼 옵션)
- `lib/features/book_record/screens/widgets/book_thumbnail_field.dart` — 책 표지 이미지 선택/미리보기 공용 위젯(책 정보 수정·직접 등록에서 공유)
- `lib/features/book_record/screens/widgets/book_category_field.dart` — 카테고리 선택 필드 + 선택 팝업 공용 위젯(책 정보 수정·직접 등록에서 공유)

## features/book_search

- `lib/features/book_search/screens/book_search_screen.dart` — 책 검색 화면(하단 탭 셸 "+" 버튼으로 진입), 검색창/결과 목록/페이지네이션/직접 등록·바코드 등록 진입점 조립
- `lib/features/book_search/screens/barcode_scan_screen.dart` — 카메라로 책 바코드(ISBN-13) 스캔 화면. 기본은 ISBN을 반환해 상세로 이동, "빠른 등록" 체크 시 선택한 상태로 즉시 서재에 담고 연속 스캔
- `lib/features/book_search/data/book_search_api.dart` — 책 검색 API 호출(키워드 검색, 직접 등록 POST(표지/카테고리 포함 multipart 지원))
- `lib/features/book_search/providers/book_search_providers.dart` — 검색 화면 상태(검색어/페이지/결과) 관리 Riverpod provider

## features/book_detail

- `lib/features/book_detail/screens/book_detail_screen.dart` — 검색 결과 경유 책 상세 화면, 정보/서재 담기/구매/커뮤니티 리뷰 조립(토론·공개 독후감 탭은 미이관 기능이라 제외)
- `lib/features/book_detail/data/book_detail_api.dart` — 책 상세 API 호출(상세 조회, 서재 존재 확인, 서재 담기, 리뷰 CRUD, 좋아요, 신고)
- `lib/features/book_detail/providers/book_detail_providers.dart` — 책 상세/커뮤니티 리뷰 관련 Riverpod provider(상세+서재 포함 여부 컨트롤러, 리뷰 커서 무한 스크롤 컨트롤러)

## shared/widgets

- `lib/shared/widgets/app_alert.dart` — 공통 Alert 팝업(제목/내용/확인 버튼)
- `lib/shared/widgets/app_confirm.dart` — 공통 Confirm 팝업(확인/취소, Future<bool> 반환)
- `lib/shared/widgets/app_loading.dart` — 공통 Loading(전체 화면 `AppLoading`, 영역 단위 `AppLoadingOverlay`)
- `lib/shared/widgets/app_snackbar.dart` — 공통 SnackBar(pill 형태, 성공/정보는 아이덴티티 컬러·에러는 에러 컬러 반투명 배경 + 상태 아이콘)

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
- `docs/review/20260811-145525-book-category-edit-review.md` — 책 카테고리 수정·색상 표시의 비동기 상태·반응형·접근성·기능 의존 구조 리뷰
- `docs/review/20260811-151308-book-category-cache-final-review.md` — 책 카테고리 로컬 캐시 추가 후 상태 정합성·다이얼로그 잔여 문제 최종 리뷰
- `docs/review/20260811-155930-local-first-record-sync-review.md` — 책 기록 로컬 우선 저장의 연속 편집 경합·오프라인 재시도·마이그레이션 리뷰
- `docs/review/20260811-173548-bookshelf-filter-and-chrome-review.md` — 완독 필터·탭 바 자동 숨김 변경의 상태 복원·캐시·접근성 리뷰
- `docs/review/20260811-182433-finished-cover-disk-cache-review.md` — 완독 표지 디스크 캐시의 콜드 성능·포커스 생명주기·포맷별 리사이즈 리뷰
- `docs/review/20260813-154240-book-search-detail-barcode-review.md` — 책 검색·상세·바코드 등록의 후속 동기화·화면 상태·리뷰 상호작용 검토
- `docs/review/20260813-162239-book-detail-preview-layout-review.md` — 책 상세 미리보기 레이아웃의 평점 스케일·리뷰 접근성·표시 데이터 정합성 리뷰
- `docs/review/20260813-180341-author-and-bottom-sheet-review.md` — 저자 표시 가공과 공통 바텀시트 전환의 안전 영역 처리 리뷰
- `docs/review/20260813-183444-app-snackbar-review.md` — 공통 스낵바의 오류 색상 대비와 메시지 큐 초기화 동작 리뷰
- `docs/review/20260814-121328-app-snackbar-rereview.md` — 공통 스낵바의 미해결 색상 대비·메시지 큐 문제 재리뷰
- `docs/review/20260814-124800-reading-date-bottom-sheet-review.md` — 독서 날짜 바텀시트의 삭제 동기화·오늘 선택·접근성 리뷰
