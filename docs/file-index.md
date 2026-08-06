# 파일 인덱스

진입점 역할을 하는 파일만 기록한다. 유틸/하위 컴포넌트/구현 상세는 생략.

## app

- `lib/main.dart` — 앱 진입점
- `lib/app/app.dart` — MaterialApp 루트 위젯
- `lib/app/router.dart` — go_router 라우팅, 인증 상태 기반 redirect(AuthGuard 대응)
- `lib/app/placeholder_home_screen.dart` — 로그인 후 진입 임시 화면(TODO: home-feed 기능 포팅 후 교체)

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

## docs

- `docs/review/20260806-174318-initial-implementation-review.md` — 최초 구현의 구조·인증·공통 컴포넌트 심층 리뷰
