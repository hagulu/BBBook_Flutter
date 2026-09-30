# 파일 인덱스

진입점 역할을 하는 파일만 기록한다. 유틸/하위 컴포넌트/구현 상세는 생략.

## app

- `lib/main.dart` — 앱 진입점
- `lib/app/app.dart` — MaterialApp 루트 위젯
- `lib/app/router.dart` — go_router 라우팅, 인증 상태 기반 redirect(AuthGuard 대응)
- `lib/app/main_shell.dart` — 로그인 후 진입하는 하단 탭 셸(책장/책 추가/마이), 기본 탭은 BOOKSHELF, 가운데 원형 책 추가 버튼으로 아래에서 올라오는 전체 화면 책 추가 진입, 포그라운드 전환 시 동기화 트리거
- `lib/app/main_shell_tab_provider.dart` — 메인 셸과 하위 기능이 공유하는 현재 하단 탭 상태

## core

- `lib/core/theme/app_theme.dart` — 밝은 숲·검정 기반 다크 역할별 색상 토큰(AppColors·AppPalette)/브랜드 고정색(AppBrandColors)/밝은·다크 ThemeData 정의
- `lib/core/theme/theme_mode_provider.dart` — 밝은·다크·시스템 테마 선택 상태·기기 저장·앱 시작 시 복원(기본 밝은 테마)
- `lib/core/network/api_client.dart` — 공통 API 클라이언트, 요청 전 세션 복구·401 refresh 1회 재시도·일시 오류 재시도 간격·이전 세션 응답 차단
- `lib/core/network/api_base_options.dart` — API 공통 base URL/timeout 정의(ApiClient·인증 전용 Dio 공유)
- `lib/core/network/patch_field.dart` — PATCH 필드 3-상태(생략=유지 / PatchField.value=수정 / PatchField.clear=명시적 null 삭제) 표현
- `lib/core/storage/token_storage.dart` — refreshToken 시큐어 스토리지 래퍼
- `lib/core/storage/client_id_storage.dart` — X-Client-Id 헤더용 설치 단위 클라이언트 식별자(UUID) 저장/재사용
- `lib/core/storage/local_image_store.dart` — 기능별 이미지 로컬 파일 저장소(선택 이미지 저장·서버 이미지 내려받기·orphan 정리, DB에는 폴더 기준 상대 경로만 보관)
- `lib/core/policy/attachment_limit_policy.dart` — 노트/독후감 이미지 첨부 한도 정책(현재 고정값: 노트 3·독후감 0, 추후 서버 등급별 값으로 교체 가능한 단일 지점) 및 서버 제한 에러코드 상수
- `lib/core/config/ad_config.dart` — AdMob 배너 광고 단위 ID 단일 관리 지점(현재는 Google 공식 테스트 ID, 실제 배포 시 이 값만 교체), release 빌드가 테스트 ID를 그대로 쓰면 막는 `assertConfiguredForRelease()`

## features/auth

- `lib/features/auth/screens/onboarding_screen.dart` — 온보딩(로그인) 화면, 소셜 로그인 아래 "로그인 없이 사용하기" 진입점
- `lib/features/auth/providers/auth_notifier.dart` — 로컬 계정으로 먼저 진입하고 뒤에서 인증 복구, 인증 무효 시 로컬 기록 보존·재로그인, 다른 계정은 확인 후 로컬 초기화, 계정 없이 시작/로그인 전환(소유자 리키)·저장 방식별 로그아웃 처리
- `lib/features/auth/providers/auth_access_providers.dart` — 로컬 기록 소유자 id(`recordOwnerIdProvider`)와 계정 필요 기능 노출 여부(`canUseAccountFeaturesProvider`) 단일 기준
- `lib/features/auth/models/standalone_session.dart` — 계정 없이 쓰는 사용자의 기록 소유자 sentinel과 로그인 시 기록 처리 선택지
- `lib/features/auth/data/local_auth_store.dart` — 기록 DB에 계정 소유자 캐시, 계정 없이 사용 중 표시 저장, 기록 소유자 일괄 변경, 기존 설치의 동기화 메타데이터에서 오프라인 계정 복원
- `lib/features/auth/data/auth_repository.dart` — 인증 세션 source of truth(API·시큐어 스토리지·소셜 SDK 오케스트레이션)
- `lib/features/auth/data/auth_api.dart` — 인증 API 호출(로그인/refresh/logout/getMe)
- `lib/features/auth/data/social_auth_service.dart` — Google/Apple/Kakao/Naver 네이티브 로그인, 공급자 토큰 획득·SDK 로그아웃
- `lib/features/auth/widgets/social_login_section.dart` — 소셜 로그인 버튼 묶음과 로그인 후처리(계정 변경 확인, 계정 없이 남긴 기록 이어가기 선택, 저장 방식 전환 화면 연결) 공용 위젯, 온보딩·MY 화면이 공유
- `lib/features/auth/widgets/auth_loading_gate.dart` — 인증 확인·라우터 전환 사이 빈 배경 표시, 로그인 사용자의 온보딩 순간 노출 방지

## features/profile

- `lib/features/profile/screens/profile_screen.dart` — 프로필(개인 페이지) 메인 화면(프로필 카드/독서 리포트 카드/내 글 모아보기 2×2 바로가기/로그아웃(서버 동기화 모드는 최종 동기화 후 미동기화 기록이 남으면 다시 시도·그래도 로그아웃 선택), 계정이 없으면 상단을 로그인 유도 카드로 대체하고 계정 전용 메뉴는 숨김), `docs/porting-reference/profile-main-screen.md` 대응
- `lib/features/profile/screens/profile_edit_screen.dart` — 프로필 수정 화면(닉네임·프로필 이미지 변경/삭제, 저장, 회원 탈퇴), `docs/porting-reference/profile-edit-screen.md` 대응
- `lib/features/profile/screens/profile_settings_screen.dart` — 설정 화면(제목 없는 3개 그룹: 공지사항·화면 테마·기록 동기화(서버/로컬 전환) / 내 기록 ZIP 내보내기·가져오기 / 오픈소스 라이선스·이용약관·개인정보 처리방침, 하단 앱 버전), 프로필 탭 AppBar 설정 아이콘으로 진입
- `lib/features/profile/screens/my_reflections_screen.dart` — 내가 작성한 독후감 목록(커서 무한 스크롤), 정상 항목은 서버 reflectionId로 로컬 행을 찾아 기존 `BookReflectionDetailScreen`(수정·삭제 포함)으로 이동
- `lib/features/profile/screens/my_reviews_screen.dart` — 내가 작성한 독자평 목록(커서 무한 스크롤), 탭해도 이동하는 상세 화면 없음
- `lib/features/profile/screens/my_discussions_screen.dart` — 내가 작성한 토론 목록(커서 무한 스크롤), 정상 항목은 `DiscussionDetailScreen`으로 이동
- `lib/features/profile/screens/my_discussion_answers_screen.dart` — 내가 작성한 토론 댓글 목록(커서 무한 스크롤, 다른 3개 목록과 동일), 항목 탭 시 원본 토론(`DiscussionDetailScreen`)으로 이동, 돌아오면 목록 재조회
- `lib/features/profile/screens/reading_stats_screen.dart` — 독서 리포트 화면(AppBar 연도 선택, 요약 3종, 장르별 비율 트리맵·토글형 숫자 상세, 월별 완독 선그래프, 추가 지표), 프로필 메인의 독서 리포트 카드 탭 시 진입, `docs/porting-reference/stats-screen.md` 대응, 데이터는 서버 API 대신 로컬 서재·노트 데이터로 직접 계산
- `lib/features/profile/data/profile_api.dart` — 프로필 API 호출(조회/수정/이미지 업로드/회원 탈퇴), 독서 리포트 카드 요약은 서버 API 대신 로컬 서재 데이터로 직접 계산
- `lib/features/profile/data/my_content_api.dart` — "내가 작성한 콘텐츠" 4개 목록 API 호출(독후감/리뷰/토론/토론 댓글 모두 커서 조회)
- `lib/features/profile/services/reading_stats_calculator.dart` — 독서 리포트 화면 요약·연도 목록을 로컬 완독 책 목록에서 계산하는 순수 함수
- `lib/features/profile/providers/profile_providers.dart` — 프로필 조회·독서 리포트 카드 요약(로컬 계산) Riverpod provider
- `lib/features/profile/providers/my_content_providers.dart` — "내가 작성한 콘텐츠" 4개 목록 Riverpod provider(모두 커서 무한 스크롤)
- `lib/features/profile/providers/reading_stats_providers.dart` — 독서 리포트 화면 연도 목록·연도별 요약 Riverpod provider(로컬 계산)

## features/bookshelf

- `lib/features/bookshelf/screens/bookshelf_screen.dart` — 책장 탭 콘텐츠(읽고 싶음/읽는 중/완독 + 중단 책이 있을 때만 노출되는 중단 탭), 로컬 데이터 최초 로딩 완료 시 읽는 중→읽을 책 우선순위로 기본 탭 1회 결정
- `lib/features/bookshelf/data/bookshelf_api.dart` — 책장 API 호출(전체 동기화, 증분 동기화, 완독 공개 설정 조회/수정, 카테고리 목록 GET)
- `lib/features/bookshelf/data/bookshelf_database.dart` — 로컬 DB(sqflite) 스키마, 기존 데이터 보존하며 오프라인 삭제·CREATE 전송 여부·표지 사본 컬럼 보강
- `lib/features/bookshelf/data/bookshelf_dao.dart` — 로컬 DB 쿼리·동기화 reconcile/applyChanges(dirty 행 보호), 태그는 `tag`/`user_book_tag_map`을 조인해 조회만 함(쓰기는 `TagDao` 전담)
- `lib/features/bookshelf/data/book_category_dao.dart` — 카테고리 마스터 목록 로컬 캐시 DAO(계정 무관, 로그아웃 시에도 유지)
- `lib/features/bookshelf/data/bookshelf_repository.dart` — 책장 기능 source of truth(화면은 항상 이 레포지토리의 로컬 조회만 사용), 최초엔 전체·이후엔 증분 동기화, 카테고리는 로컬 캐시 우선 조회
- `lib/features/bookshelf/services/book_cover_image_store.dart` — 로컬 저장 모드에서 사용자가 고른 책 표지를 보관하는 `LocalImageStore` 인스턴스(`book_covers/` 폴더)
- `lib/features/bookshelf/data/finished_cover_cache_manager.dart` — 완독 목록 표지 전용 디스크 캐시(원본 바이트 저장, 디코딩 크기 제한은 `BookCover`의 `ResizeImage`가 담당)
- `lib/features/bookshelf/data/recommendation_api.dart` — 추천 도서 API 호출(`GET /api/me/recommendations/books`, 카테고리·문구 선정은 서버 전담)
- `lib/features/bookshelf/providers/bookshelf_providers.dart` — 책장 관련 Riverpod provider(동기화 컨트롤러, 탭별 목록, 완독 필터, 공개 설정, 카테고리 목록, 읽는 중·읽을 책 탭별 추천 도서)
- `lib/features/bookshelf/models/record_patch.dart` — 책 기록 PATCH 요청 필드 묶음(바꾼 필드만 담는 요청 body 생성, dirty 스냅샷 → 요청 변환)
- `lib/features/bookshelf/models/book_recommendation.dart` — 추천 도서 API 응답 모델(추천 목록·문구·책 목록)

## features/book_record

- `lib/features/book_record/screens/book_record_screen.dart` — 책 기록 상세 화면(자체 AppBar, 책장에서 책 선택 시 진입), 정보/노트/독후감/생각나눔 4탭과 진행률/상태/출처/난이도/태그/삭제 조립, 공통 접힘 헤더·고정 탭 바와 탭별 콘텐츠 길이·스크롤 위치 분리
- `lib/features/book_record/screens/book_sharing_list.dart` — 책 기록 상세의 생각나눔 탭(ISBN 있으면 커뮤니티 미리보기 공용 위젯 — 독자평 버튼 항상 노출, 독후감 배지는 내 공개 독후감 수 제외, 없으면 안내용 진입 버튼)
- `lib/features/book_record/data/book_record_api.dart` — 책 기록 API 호출(기본 정보 PATCH(RecordPatch 기준 부분 수정), 책 정보 PATCH(카테고리 포함), ISBN 연결/해제 PATCH, 태그 자동완성 목록/플랫폼 옵션 GET, 삭제 DELETE) — 태그 추가/삭제 자체는 `TagApi`가 전담
- `lib/features/book_record/data/book_record_repository.dart` — 책 기록 화면 source of truth, 기록·책 정보·표지·출처 수정과 삭제는 로컬 우선/서버 재시도, ISBN 연결은 미전송 편집 동기화 후 직렬 처리
- `lib/features/book_record/providers/book_record_providers.dart` — 책 기록 관련 Riverpod provider(단일 책 상태 컨트롤러, 태그 자동완성, 플랫폼 옵션)
- `lib/features/book_record/screens/widgets/book_thumbnail_field.dart` — 책 표지 이미지 선택/미리보기 공용 위젯(책 정보 수정·직접 등록에서 공유)
- `lib/features/book_record/screens/widgets/book_category_field.dart` — 카테고리 선택 필드 + 선택 팝업 공용 위젯(책 정보 수정·직접 등록에서 공유)

## features/tag

- `lib/features/tag/data/tag_api.dart` — 태그 추가(POST)/삭제(DELETE) 및 증분 동기화 조회(`/api/me/tags/sync/changes`) API 호출
- `lib/features/tag/data/tag_dao.dart` — 태그(`tag`)/책-태그 매핑(`user_book_tag_map`) 로컬 DB 쿼리·dirty push 확정(같은 이름 태그 병합 포함)·전체/증분 reconcile(dirty 매핑 보호)
- `lib/features/tag/data/tag_repository.dart` — 태그 화면 source of truth, 로컬 우선 추가/삭제 직후 조용히 서버 push하고 실패 시 dirty 유지, 최초엔 전체(`/api/me/records`)·이후엔 증분(`/api/me/tags/sync/changes`) 동기화 — 책 하나에 매이지 않는 계정 전체 단위
- `lib/features/tag/providers/tag_providers.dart` — 태그 동기화 컨트롤러 등 Riverpod provider
- `lib/features/tag/models/tag_mapping.dart` — 로컬 태그(`LocalTag`)/매핑(`TagMapping`) 값 객체
- `lib/features/tag/models/tag_sync_changes_result.dart` — `/api/me/tags/sync/changes` 응답 모델

## features/book_note

- `lib/features/book_note/screens/book_note_list.dart` — 책 기록 상세의 노트 목록 탭(노트 추가·상세 진입, 당겨서 새로고침)
- `lib/features/book_note/screens/book_note_detail_screen.dart` — 노트 제목 자동 저장과 타입별 메모 타임라인·로컬 CRUD 화면
- `lib/features/book_note/screens/memo_photo_camera_screen.dart` — 공용 카메라(`shared/image`)에 메모 사진 촬영 정책을 얹은 진입점(세로 미리보기·갤러리 재인코딩·5MB 촬영 게이트)
- `lib/features/book_note/screens/widgets/book_note_ai_memo_composer_screen.dart` — AI 메모 생성 전용 긴 텍스트 입력 화면(메모 추가 시트의 "AI로 메모 만들기" 진입점), 생성 실패 시 입력 내용 보존
- `lib/features/book_note/data/book_note_api.dart` — 노트 제목 PUT, 메모 생성/수정/삭제, 사진 업로드, AI 메모 생성, 증분 동기화 조회 API 호출
- `lib/features/book_note/data/book_note_dao.dart` — 로컬 DB 쿼리·dirty push 확정·전체/증분 reconcile(dirty 행 보호, 로컬 PK와 server_id 분리)
- `lib/features/book_note/data/book_note_repository.dart` — 노트 화면 source of truth, 로컬 우선 CRUD 직후 조용히 서버 push하고 실패 시 dirty 유지, 최초엔 전체(`/api/me/records`)·이후엔 증분(`/api/me/notes/sync/changes`) 동기화, 사진은 로컬 사본 우선(업로드 후에도 유지·서버 사진은 노트를 열 때 내려받기)
- `lib/features/book_note/providers/book_note_providers.dart` — 책별 노트 목록·상세 상태 및 노트 동기화 컨트롤러 Riverpod provider
- `lib/features/book_note/services/book_note_memo_ocr_service.dart` — 촬영 이미지에서 한국어 단어와 선택용 좌표를 추출하는 온디바이스 OCR 서비스
- `lib/features/book_note/services/note_memo_image_store.dart` — 메모 사진 전용 `LocalImageStore` 인스턴스(`memo_images/` 폴더)
- `lib/features/book_note/utils/memo_highlight.dart` — 웹과 동일한 `::hl[[]]` 강조 마크업 파싱/직렬화, `isImportant` 파생 기준(`hasMemoHighlight`)
- `lib/features/book_note/screens/widgets/highlight_text_field.dart` — 강조(::hl[[]]) 편집을 지원하는 `MemoHighlightController`(TextEditingController), 커서/선택 기반 토글·타이핑 상속·range 이동
- `docs/policies/memo-highlight-toggle.md` — 강조 토글 버튼 정책 문서(상태 판단·경계 공백 삽입·IME 조합 세션 고정), 다른 화면/플랫폼에 재구현할 때 참고

## features/book_reflection

- `lib/features/book_reflection/screens/book_reflection_list.dart` — 책 기록 상세의 독후감 탭(로컬 목록, 당겨서 새로고침), 작성·상세 진입점
- `lib/features/book_reflection/screens/book_reflection_detail_screen.dart` — 독후감 상세(Quill Delta·레거시 Tiptap 리치 텍스트/이미지 읽기 및 수정 진입)
- `lib/features/book_reflection/screens/book_reflection_editor_screen.dart` — Flutter Quill 기반 독후감 작성/수정 화면(순환형 제목·목록 툴바, 본문 이미지 크기·삭제 메뉴)
- `lib/features/book_reflection/data/book_reflection_api.dart` — 독후감 작성·수정·본문 이미지 업로드·AI 독후감 초안 생성(DB 미저장)·증분 동기화 API 호출
- `lib/features/book_reflection/data/book_reflection_dao.dart` — 독후감 로컬 우선 CRUD·dirty push 확정·전체/증분 동기화 반영·본문 이미지 매칭(`reflection_image_local`) 관리
- `lib/features/book_reflection/data/book_reflection_repository.dart` — 독후감 화면 source of truth(로컬 우선 작성/수정 후 조용히 push, dirty 재시도, 전체/증분 동기화), 본문 이미지는 로컬 저장 후 push 때 업로드·치환하고 서버 이미지는 독후감을 열 때 내려받기
- `lib/features/book_reflection/providers/book_reflection_providers.dart` — 독후감 목록·상세 조회, 동기화 컨트롤러, 본문 이미지 로컬 매칭 Riverpod provider
- `lib/features/book_reflection/services/reflection_image_store.dart` — 독후감 본문 이미지 전용 `LocalImageStore` 인스턴스(`reflection_images/` 폴더)
- `lib/features/book_reflection/services/reflection_image_mapping.dart` — push 응답과 로컬 사본을 순서로 짝지어 서버 URL↔로컬 경로 매칭을 만드는 순수 함수

## features/storage_mode

- `lib/features/storage_mode/data/storage_mode_store.dart` — 저장 모드(서버/로컬)와 소유자·서버 정리 미완료 여부 읽기·쓰기 단일 창구(동기화·push 게이트가 참조, 계정 없이 사용 시 로컬 고정, 로그아웃 시 기본값으로 초기화)
- `lib/features/storage_mode/services/local_storage_migration_service.dart` — 서버 → 로컬 이전 단계 실행(기록 동기화 → 이미지 전체 확보 → 검증 → 모드 전환 → 서버 소프트 삭제 순서 보장)
- `lib/features/storage_mode/data/local_storage_migration_steps.dart` — 이전 각 단계를 기존 동기화 Repository·API로 구현
- `lib/features/storage_mode/providers/storage_mode_providers.dart` — 현재 저장 모드 및 이전 진행 상태 Riverpod provider
- `lib/features/storage_mode/screens/local_storage_migration_screen.dart` — 서버 → 로컬 이전 진행률·결과 화면(진행 중 뒤로 가기 차단)

## features/server_storage_migration

- `lib/features/server_storage_migration/data/record_import_api.dart` — 로컬 → 서버 저장 모드 재전환 Import 세션 API 호출(start/items/attachments/complete/cancel)
- `lib/features/server_storage_migration/data/record_import_snapshot_builder.dart` — Import 직전 로컬 DB 스냅샷 구성(clientRequestId 백필, 이미지 파일 확보·형식/용량 확인, 독후감 이미지·로컬 커스텀 책 표지 `local://` placeholder 치환)
- `lib/features/server_storage_migration/data/record_import_validation.dart` — 서버 400/롤백을 부르는 조합(글자 수·범위·중복 clientRequestId·태그 1:1 규칙 등)을 미리 걸러내는 순수 검증 함수
- `lib/features/server_storage_migration/data/record_import_payload_builder.dart` — 로컬 모델 → items 요청 JSON 변환과 `maxChunkItemCount` 기준 청크 분할(순수 함수)
- `lib/features/server_storage_migration/data/server_storage_migration_steps.dart` — Import 단계 인터페이스(테스트가 가짜 구현으로 순서·중단 조건 검증)
- `lib/features/server_storage_migration/data/server_storage_migration_repository_steps.dart` — 단계 인터페이스를 실제 DAO·API로 구현
- `lib/features/server_storage_migration/services/server_storage_migration_service.dart` — 준비→시작→청크 업로드→이미지 업로드→완료→로컬 반영 순서를 보장하는 오케스트레이터(로컬 DB 반영은 `/complete` 성공 후에만)
- `lib/features/server_storage_migration/providers/server_storage_migration_providers.dart` — 전환 실행/진행 상태 Riverpod provider
- `lib/features/server_storage_migration/screens/server_storage_migration_screen.dart` — 전환 진행 화면(기록 준비/기록 업로드/이미지 업로드/완료 처리 단계 표시), 프로필 설정 화면에서 진입

## features/external_record_import

- `lib/features/external_record_import/screens/external_import_guide_screen.dart` — 다른 서비스 기록 가져오기 안내 화면(서비스별 파일 확장자·가져오는 기록, 앱 업데이트 영향 안내, 파일 선택 후 분석 화면 진입), 책 추가 화면에서 진입
- `lib/features/external_record_import/screens/external_import_screen.dart` — 북적북적 CSV·북모리 BOOKMORY 파일 분석 결과와 책/메모/제외 건수를 확인하고 가져올 책을 골라 가져오는 화면
- `lib/features/external_record_import/providers/external_import_providers.dart` — 외부 파일 분석·같은 ISBN 충돌 확인·가져오기 실행 상태 관리. 동기화가 켜져 있으면 기존 기록 사전 동기화 → 서버 Import → 증분 동기화, 동기화 꺼짐·계정 없음이면 로컬 저장
- `lib/features/external_record_import/services/external_import_file_analyzer.dart` — 확장자 우선 분기와 CSV 헤더/BOOKMORY ZIP·SQLite 내부 검증을 거쳐 서비스별 파서로 연결
- `lib/features/external_record_import/services/external_record_import_service.dart` — (동기화 켜짐) 공통 외부 모델을 기존 records Import 청크로 변환해 start/items/complete를 실행하고, API 실패는 서버 자동 롤백에 맡기며 클라이언트 후처리 실패만 cancel
- `lib/features/external_record_import/services/external_record_local_import_service.dart` — (동기화 꺼짐·계정 없음) 공통 외부 모델을 사전 검증한 뒤 로컬 복원 규격으로 변환해 `RecordArchiveDao.restore`로 한 트랜잭션 저장
- `lib/features/external_record_import/widgets/external_import_share_coordinator.dart` — Android 공유/파일 열기 cold·warm start 이벤트를 앱 사용 가능 상태가 된 뒤 분석 화면으로 즉시 연결하고 캐시 파일 정리

## features/record_archive

- `lib/features/record_archive/services/record_archive_service.dart` — 로컬 기록 ZIP 내보내기·가져오기, 이미지 확보·공유 참조·검증·실패 파일 정리
- `lib/features/record_archive/data/record_archive_dao.dart` — DB 스냅샷을 export DTO로 변환하고 기존 중복 정책·dirty 상태를 적용해 한 트랜잭션으로 복원(외부 서비스 가져오기도 원격 표지와 함께 재사용)
- `lib/features/record_archive/models/record_archive.dart` — PK와 독립적인 version 1 아카이브 DTO·필드 규격·버전 파서·관계 검증
- `lib/features/record_archive/screens/record_archive_import_screen.dart` — 내 기록 가져오기 안내 화면(ZIP 형식·연결/중복/동기화 안내, 파일 선택 후 기존 가져오기 실행), 설정에서 진입
- `lib/features/record_archive/providers/record_archive_provider.dart` — 설정 화면 내보내기·가져오기 진행 상태, OS ZIP 선택·공유, 완료 후 로컬 목록 갱신
- `docs/policies/record-archive.md` — ZIP/JSON version 1 규격, 중복 대응·동기화·이미지·파일 검증 정책과 지원 한도

## features/record_sync

- `lib/features/record_sync/screens/initial_record_sync_screen.dart` — 사용 가능한 로컬 기록이 없을 때만 최초 기록 다운로드·저장 진행 상태와 재시도를 표시하는 게이트 화면
- `lib/features/record_sync/providers/background_record_sync_provider.dart` — 앱 사용 중 인증→책→노트→독후감→태그 복구 조율, 앱 복귀·통신 성공·주기 확인으로 dirty 재전송, 저장 방식 전환 중 중단
- `lib/features/record_sync/providers/logout_record_sync_provider.dart` — 서버 동기화 모드 로그아웃 직전 책→노트→독후감→태그 최종 동기화(사용자 재시도)와 남은 미동기화 기록 확인
- `lib/features/record_sync/providers/record_sync_providers.dart` — 사용자별 최초 기록 동기화 단계·진행률·재시도 상태 관리
- `lib/features/record_sync/data/record_sync_api.dart` — 전체 책장·기록 조회(`/api/me/records`)와 로컬 전환 시 서버 기록 일괄 소프트 삭제(DELETE) API 호출
- `lib/features/record_sync/data/record_sync_repository.dart` — 전체 책장·기록 조회와 원자적 로컬 저장을 조율하는 초기 동기화 source of truth

## features/book_search

- `lib/features/book_search/screens/book_search_screen.dart` — 책 추가 전체 화면(하단 탭 셸 "+" 버튼으로 아래에서 올라오는 전환), 검색창/결과 목록/페이지네이션/직접 등록·바코드 등록·다른 서비스 기록 가져오기(북적북적·북모리 보조 문구, 안내 화면으로 이동) 한 줄 버튼 진입점 조립
- `lib/features/book_search/screens/barcode_scan_screen.dart` — 카메라로 책 바코드(ISBN-13) 스캔 화면. 기본은 ISBN을 반환해 상세로 이동, "빠른 등록" 체크 시 선택한 상태로 즉시 서재에 담고 연속 스캔
- `lib/features/book_search/data/book_search_api.dart` — 책 검색 API 호출(키워드 검색, 직접 등록 POST(표지/카테고리 포함 multipart 지원))
- `lib/features/book_search/providers/book_search_providers.dart` — 검색 화면 상태(검색어/페이지/결과) 관리 Riverpod provider

## features/book_detail

- `lib/features/book_detail/screens/book_detail_screen.dart` — 검색 결과 경유 책 상세 화면, 정보/서재 담기/구매/커뮤니티 미리보기 조립
- `lib/features/book_detail/screens/book_review_list_screen.dart` — ISBN13 기준 독자평 전체 목록(커서 무한 스크롤, 본인 리뷰 수정·삭제, 공감, 신고), 작성 폼은 없음
- `lib/features/book_detail/data/book_detail_api.dart` — 책 상세 API 호출(상세 조회, 서재 존재 확인, 서재 담기, 리뷰 CRUD, 좋아요, 신고)
- `lib/features/book_detail/providers/book_detail_providers.dart` — 책 상세/커뮤니티 리뷰 관련 Riverpod provider(상세+서재 포함 여부 컨트롤러, 리뷰 커서 무한 스크롤 컨트롤러)

## features/book_community

- `lib/features/book_community/data/book_community_api.dart` — 커뮤니티 미리보기·개수 API 호출(GET community-preview, community-counts)
- `lib/features/book_community/providers/book_community_providers.dart` — isbn13 기준 미리보기(독후감/토론 개수 포함)·독자평 전체 개수 독립 조회 Riverpod provider(한쪽 실패가 다른 쪽에 영향 없음)
- `lib/features/book_community/screens/widgets/book_community_preview_section.dart` — 책 검색 상세·책 기록 상세(생각나눔 탭)가 공유하는 커뮤니티 미리보기 위젯(독자평/독후감/토론 개수 진입 버튼 + 최근 독자평 미리보기)

## features/discussion

- `lib/features/discussion/screens/discussion_list_screen.dart` — 책 한 권의 주제 토론 목록(열린 토론/전체 필터, 커서 무한 스크롤, 토론 작성 진입)
- `lib/features/discussion/screens/discussion_detail_screen.dart` — 토론 상세(선택지 결과 바·답변 작성/목록·공감·작성자 메뉴(수정/마감일/닫기·재오픈/삭제))
- `lib/features/discussion/screens/discussion_form_screen.dart` — 토론 주제 작성/수정 폼(자유 토론·선택지 토론 전환, 수정 시 기존 선택지 append-only 잠금)
- `lib/features/discussion/data/discussion_api.dart` — 토론 API 호출(주제 목록/상세/작성/수정/마감일/닫기/재오픈/삭제, 답변 CRUD, 공감, 신고)
- `lib/features/discussion/providers/discussion_providers.dart` — 토론 관련 Riverpod provider(주제 목록은 커서 무한 스크롤, 답변 목록은 서버가 페이지 번호로 응답해 `AppPagination` 숫자 페이지네이션 사용, 상세·낙관적 공감 토글)
- `lib/features/discussion/utils/discussion_poll.dart` — 선택지 색 팔레트 배정·append-only 검증·퍼센트 포맷

## features/public_reflection

- `lib/features/public_reflection/screens/public_reflection_list_screen.dart` — ISBN13 기준 공개 독후감 목록(숨김 제외, 커서 무한 스크롤)과 리더 진입점
- `lib/features/public_reflection/screens/public_reflection_reader_screen.dart` — 공개·발행 상태를 검증한 독후감의 읽기 전용 Quill 리더(이미지·헤더·인용·목록·색상·공감 지원)
- `lib/features/public_reflection/data/public_reflection_api.dart` — 공개 독후감 목록·상세 조회와 공감 추가·취소 API 호출
- `lib/features/public_reflection/services/public_reflection_service.dart` — 숨김 목록 제거와 공개·발행·ISBN 상세 노출 조건을 보장하는 조회 서비스
- `lib/features/public_reflection/providers/public_reflection_providers.dart` — 공개 독후감 목록 커서 페이징·상세 조회·낙관적 공감 토글 Riverpod provider

## features/notices

- `lib/features/notices/screens/notices_list_screen.dart` — 공지사항 목록(인증 불필요, 커서 무한 스크롤, 다음 페이지 실패 시 하단 재시도), 프로필 메인 "공지사항" 메뉴로 진입
- `lib/features/notices/screens/notice_detail_screen.dart` — 공지사항 상세(인증 불필요, 404는 재시도 없이 "찾을 수 없음" 표시)
- `lib/features/notices/data/notices_api.dart` — 공지사항 목록·상세 API 호출(둘 다 인증 불필요)
- `lib/features/notices/providers/notices_providers.dart` — 공지사항 목록 커서 무한 스크롤(다음 페이지 전용 에러 상태 포함)·상세 조회 Riverpod provider

## features/public_bookshelf

- `lib/features/public_bookshelf/screens/public_finished_bookshelf_screen.dart` — 다른 사용자의 공개 완독 책장 화면(그리드, 커서 무한 스크롤), 비공개(403)는 일반 오류와 구분해 안내
- `lib/features/public_bookshelf/data/public_bookshelf_api.dart` — 공개 완독 책장 API 호출(`GET /api/users/{userId}/books/finished`, 인증 선택)
- `lib/features/public_bookshelf/providers/public_bookshelf_providers.dart` — userId 기준 완독 책장 커서 무한 스크롤 Riverpod provider
- `lib/features/public_bookshelf/widgets/author_profile_sheet.dart` — 독후감 상세/토론 상세/독자평 작성자 영역 탭 시 뜨는 시트(웹 `UserMenu` 대응), 완독 책장 공개(`isFinishedBooksPublic`) 사용자만 탭 가능, "완독 책장 보러가기" 선택 시 공개 완독 책장 화면으로 이동

## shared/widgets

- `lib/shared/widgets/app_alert.dart` — 공통 Alert 팝업(제목/내용/확인 버튼)
- `lib/shared/widgets/app_bar_title.dart` — 공통 앱바 타이틀(전역 축소 글씨 크기, `subtitle` 지정 시 제목 아래 작게 배치)
- `lib/shared/widgets/app_confirm.dart` — 공통 Confirm 팝업(확인/취소, Future<bool> 반환 — `choose()`는 취소 버튼과 닫힘을 구분해 Future<bool?> 반환)
- `lib/shared/widgets/app_loading.dart` — 공통 Loading(전체 화면 `AppLoading`, 영역 단위 `AppLoadingOverlay`)
- `lib/shared/widgets/ai_generating_view.dart` — AI 생성 전용 대기 표시(반짝이는 아이콘 애니메이션 + 직관적 상태 문구 + 순차 점 3개, `AiGeneratingView`), 전체 화면 오버레이 버전 `AppAiLoading` — AI 메모/독후감 생성 두 진입점만 공유
- `lib/shared/widgets/app_snackbar.dart` — 공통 SnackBar(pill 형태, 성공/정보는 아이덴티티 컬러·에러는 에러 컬러 반투명 배경 + 상태 아이콘)
- `lib/shared/widgets/app_pagination.dart` — 공통 숫자 페이지네이션(항상 첫/마지막 페이지 노출, 현재 페이지 주변만 펼치고 나머지는 `···` 생략, `buildPaginationRange` 순수 함수 + `AppPagination` 위젯)
- `lib/shared/widgets/record_dialog_shell.dart` — 여러 기능의 선택·수정 폼이 공유하는 바텀시트 셸(드래그 핸들·제목·콘텐츠·공통 버튼)
- `lib/shared/widgets/app_banner_ad.dart` — 화면 상단/하단용 공통 AdMob 배너 광고 위젯(로드 전/실패 시 빈 영역 없음, 좁은 화면에서는 비율 유지 축소, 광고 단위 ID는 `AdConfig` 참조)
- `lib/shared/widgets/app_inline_banner_ad.dart` — 목록/그리드 중간 삽입용 배너 광고 위젯(로드 전부터 자리·높이를 미리 확보해 로드 시 목록이 밀리지 않음, 실패 시에만 자리 제거, 뷰포트 근처에서만 실제 로드 시작)

## shared/ads

- `lib/shared/ads/ad_slot_planner.dart` — 목록/그리드에 몇 행마다 광고를 끼워 넣을지 계산하는 순수 함수(`planRowBasedAdSlots`)와 1열 목록용 헬퍼(`interleaveAdSlots`), 완독 책장·책 검색·독후감·토론·독자평 목록이 공유
- `lib/shared/ads/ads_enabled_provider.dart` — 광고 전체 노출 여부를 결정하는 단일 지점(`adsEnabledProvider`, 지금은 항상 true), 추후 광고 제거 구매 등으로 교체할 지점

## shared/image

- `lib/shared/image/widgets/shared_image_viewer.dart` — 공용 이미지 전체화면 뷰어(핀치 확대/축소, 호출부가 넘긴 이미지 위젯 표시, 선택적 수정/삭제 액션 바)
- `lib/shared/image/screens/shared_camera_screen.dart` — 공용 카메라 화면(초기화·방향 잠금·생명주기는 공통, 미리보기 모드·가이드·갤러리 압축·촬영 용량 게이트는 `CameraCapturePolicy`로 목적별 주입), 좌하단 아이콘으로 갤러리 전환
- `lib/shared/image/screens/shared_image_editor_screen.dart` — 공용 이미지 에디터(`pro_image_editor` 래핑, JPEG 출력), 일반(크롭·회전·텍스트·그리기)/OCR(크롭·회전만) 프로필
- `lib/shared/image/services/image_gallery_picker.dart` — `image_picker` 갤러리 선택과 `LocalImageStore` 기준(jpg/jpeg/png/webp·5MB) 형식·용량 검증

## docs

- `docs/policies/offline-records.md` — 오프라인 진입·인증 복구·재전송·계정 변경 삭제 정책과 검증 항목
