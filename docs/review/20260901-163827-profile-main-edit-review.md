# 리뷰 결과

## 요약
- `flutter analyze`는 통과했지만, 프로필 메인 메뉴가 동작하지 않는 문제와 로컬 저장 데이터 삭제 경고 회귀를 포함해 기능·상태 갱신·생명주기 문제 5건이 있다.

## 문제점
- [문제] [높음] `lib/features/profile/screens/profile_screen.dart:198`, `lib/features/profile/screens/profile_screen.dart:346`, `lib/features/profile/screens/profile_screen.dart:352`, `lib/features/profile/screens/profile_screen.dart:358`, `lib/features/profile/screens/profile_screen.dart:364`, `lib/features/profile/screens/profile_screen.dart:384`의 독서 통계·내 콘텐츠 4종·공지사항 항목은 화살표와 터치 효과가 있는 버튼으로 노출되지만 `onTap: () {}`만 실행한다. 포팅 문서에 명시된 여섯 이동 경로가 모두 동작하지 않아 사용자는 탭해도 아무 반응을 받지 못한다.
- [문제] [높음] `lib/features/profile/screens/profile_screen.dart:451`의 로그아웃 확인 문구가 저장 모드와 무관하게 단순 확인만 보여주지만, `lib/features/auth/providers/auth_notifier.dart:136`의 직접 로그아웃은 `lib/features/auth/providers/auth_notifier.dart:141`에서 로컬 DB와 사진을 항상 지운다. 로컬 저장 모드에서는 서버 사본이 이미 정리되어 기기 데이터가 유일본인데도 이 비가역적 삭제 사실을 알리지 않는다. 삭제된 `profile_tab_placeholder.dart`에는 로컬 모드 전용 경고가 있었으므로 이번 교체로 안전장치가 사라졌다.
- [문제] [보통] `lib/features/profile/providers/profile_providers.dart:29`의 통계 provider는 로컬 DB를 한 번 조회할 뿐 `bookshelfSyncVersionProvider`를 구독하지 않는다. `lib/app/main_shell.dart:82`의 `IndexedStack`이 프로필 탭을 계속 마운트하므로 `autoDispose`도 캐시를 폐기하지 않는다. 최초 계산 후 책을 완독 처리하거나 쪽수·카테고리를 수정하고 프로필 탭으로 돌아와도 완독 권수, 읽은 쪽수, 많이 읽은 분야가 이전 값으로 남는다.
- [문제] [보통] `lib/features/profile/screens/profile_edit_screen.dart:132`의 이미지 선택 흐름은 갤러리와 파일 검증을 두 번 `await`한 뒤 `lib/features/profile/screens/profile_edit_screen.dart:140`에서 `mounted` 확인 없이 `setState()`를 호출한다. 이미지 선택 중 인증 만료나 외부 라우팅 등으로 수정 화면이 제거되면 dispose된 State를 갱신해 예외가 발생할 수 있다.
- [문제] [낮음] `lib/features/profile/screens/profile_edit_screen.dart:261`은 닉네임 입력값으로 기본 아바타 글자를 만들지만, `lib/features/profile/screens/profile_edit_screen.dart:272`의 `onChanged`는 기존 에러가 있을 때만 `setState()`를 호출한다. 프로필 이미지가 없는 사용자가 정상 상태에서 닉네임을 바꾸면 아바타 첫 글자는 입력값을 따라 갱신되지 않는다.

## 개선 제안
- 동작하지 않는 메뉴 → 각 항목을 포팅 문서의 대상 화면에 연결한다. 대상 화면 구현이 이번 범위 밖이라면 실제 화면이 준비될 때까지 버튼·화살표를 노출하지 않거나 준비 중임을 명확히 안내해 무반응 버튼을 없앤다.
- 로컬 모드 로그아웃 → `storageModeProvider`를 구독해 로컬 저장 모드에서는 서버 사본이 없고 로그아웃 즉시 모든 기록과 사진이 삭제된다는 전용 확인 문구를 복원한다. 서버 모드에서도 미동기화 로컬 데이터 삭제 가능성을 함께 안내한다.
- 통계 캐시 → `profileStatsSummaryProvider`에서 `bookshelfSyncVersionProvider`를 구독해 동기화와 기록 수정 후 로컬 DB를 다시 집계하도록 한다.
- 이미지 선택 생명주기 → 갤러리 선택과 검증이 끝난 뒤 성공·실패 분기 전에 `if (!mounted) return;`으로 State 접근을 막는다.
- 기본 아바타 미리보기 → 닉네임 변경 시 항상 필요한 최소 상태만 갱신하거나 `TextEditingController`의 `ValueListenableBuilder`로 아바타를 구독해 첫 글자를 즉시 반영한다.
