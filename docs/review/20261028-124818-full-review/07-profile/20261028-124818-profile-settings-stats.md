# 리뷰 결과

## 요약
프로필 저장과 통계 계산은 대체로 분리돼 있지만, 탈퇴 중 화면 종료에 따른 로컬 정리 누락과 동기화 끄기 안내에 문제가 있습니다. P1 1건, P2 1건입니다.

## 확인 범위
MY 프로필/오프라인 대체 표시, 닉네임·사진 변경/삭제, 회원 탈퇴, 로그아웃, 테마·동기화 설정, 서버 정리 재시도, ZIP 진입, 내 글 목록, 독서 리포트의 연도·메모·태그·카테고리 집계를 확인했습니다.

## 문제점

### [PROF-01][P1] 서버 탈퇴 성공 뒤 화면이 닫혀 있으면 로컬 계정·기록을 지우지 않음

- 근거: [lib/features/profile/screens/profile_edit_screen.dart:233](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/profile/screens/profile_edit_screen.dart:233)은 `deleteMe()`가 끝난 직후 `if (!mounted) return`을 실행하고, 그 다음에야 `logout(deletingAccount: true)`로 로컬 데이터를 삭제합니다. `_isDeletingAccount`는 저장/탈퇴 버튼을 막지만 앱바 뒤로 가기와 시스템 pop을 막는 PopScope는 없습니다.
- 일반 재현: 탈퇴 확인 후 서버 처리 중 뒤로 가기로 프로필 편집 화면을 닫습니다. 그 뒤 DELETE가 성공합니다.
- 영향: 서버 계정은 탈퇴됐지만 기기의 기록·사진·로컬 계정 상태 정리가 생략됩니다. 이후 인증 오류가 발생해도 자동 인증 해제는 기록 보존 정책이므로, 탈퇴 때 약속한 로컬 영구 삭제를 대신하지 않습니다. 화면이 사라졌다는 이유로 반드시 해야 하는 계정 정리가 취소되는 문제입니다.

### [SET-01][P2] 동기화 끄기 확인창이 실제와 다른 로그아웃 삭제 정책을 안내함

- 근거: [lib/features/profile/screens/profile_settings_screen.dart:166](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/profile/screens/profile_settings_screen.dart:166)은 ‘동기화를 끄면 … 로그아웃하면 이 기기의 기록이 삭제됩니다’라고 안내합니다. 현재 [lib/features/auth/providers/auth_notifier.dart:436](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/providers/auth_notifier.dart:436)의 로컬 모드 로그아웃은 기록을 보존하고 계정만 분리합니다. MY 로그아웃 안내도 그 보존 정책을 설명합니다.
- 영향: 같은 사용자에게 서로 반대인 기록 보존 안내가 표시되어, 유일본 보관 여부를 잘못 이해하고 동기화 전환을 결정할 수 있습니다.

## 개선 제안

- PROF-01: 서버 탈퇴 성공 뒤 필수 로컬 정리는 위젯 mounted와 무관하게 실행되게 합니다. await 전에 인증 정리 대상을 확보하고, mounted 검사는 UI 조작에만 사용합니다. 전송 중 뒤로 가기 차단은 보조 방어로 적용하되 이것만으로 정리 책임을 해결하지 않습니다.
- SET-01: 현재 보존 동작에 맞게 확인창 문구를 수정합니다. 실제 로그아웃 구현을 삭제 정책으로 되돌릴 필요는 없습니다.

## 확인된 보호 장치

프로필 이미지 업로드와 프로필 PATCH가 분리돼 있고 실패를 구별해 안내합니다. 프로필 저장·탈퇴 중 중복 버튼 요청은 막습니다. 통계는 서버 API 대신 로컬 책·노트 범위로 계산하고 소유자/연도를 적용합니다. 계정 없이 사용하는 사용자는 서버 기능을 감추며 로컬 통계와 ZIP 기능을 사용할 수 있습니다.

## 관련 항목

로컬 모드 로그아웃 후 재실행과 다른 계정으로 이어받기는 [AUTH-01/02](../01-auth/20261028-124818-login-logout-ownership.md), 저장 방식 전환 중 외부 가져오기 배타 문제는 [IMP-02](../03-imports/20261028-124818-external-import.md)입니다.

## 후속 확인 시나리오

탈퇴 요청 중 화면 닫기, 사진 선택 취소·업로드 실패, 오프라인 프로필 표시, 로컬 로그아웃 재실행, 연도별 완독·메모 범위, 별점 없음/카테고리 없음/완독일 없는 과거 기록의 통계 표시를 확인합니다. 이번에는 기본 계산 규칙의 취향 차이나 전체 통계 구조 변경을 개선 항목으로 넣지 않았습니다.
