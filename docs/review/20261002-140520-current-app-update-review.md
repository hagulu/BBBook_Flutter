# 리뷰 결과

## 요약
- 앱 업데이트 안내 변경분에서 P2 문제 3건을 확인했으며, `flutter analyze`는 통과했다.
- 범위: 현재 미커밋 변경사항인 `lib/app/app.dart`, `lib/features/app_update/`, `test/features/app_update/`와 연관된 공통 팝업·스낵바·외부 파일 공유 흐름. API 계약은 `../../api-doc/api-app-versions-get.md`로 확인했다.
- 검증: 정적 코드 검토, 설치된 Flutter SDK의 위젯 갱신·Overlay 탐색 구현 확인, `flutter analyze`(`No issues found!`). 프로젝트 지침에 따라 테스트와 앱 실행은 수행하지 않았다. 아래 재현 조건은 코드 흐름을 기준으로 확인했으며, 기기에서 실행해 재현하지는 않았다.

## 문제점
- [P2][권장 팝업이 열려 있으면 복귀 시 강제 업데이트 정책을 확인하지 않음] `lib/features/app_update/widgets/app_update_gate.dart:85–91` — `_check()`가 `_showRecommended()`의 완료까지 기다리므로 사용자가 팝업을 닫기 전까지 `_checking`이 계속 true다. 권장 팝업을 띄운 채 홈으로 나간 사이 서버의 `minimumVersion`이 올라가도, 복귀 시 호출되는 `_check()`는 68행에서 바로 종료한다. 사용자는 이전 권장 팝업의 `그만 보기`를 눌러 현재 정책상 지원하지 않는 버전으로 앱을 계속 사용할 수 있으며, 팝업을 닫은 후에도 자동 재조회가 없다.
- [P2][강제 차단 전환이 외부 공유 파일 대기 상태를 초기화함] `lib/features/app_update/widgets/app_update_gate.dart:162–165` — 평소에는 `widget.child`를 직접 반환하고 강제 업데이트 때에는 `Stack → ExcludeFocus → widget.child`로 트리를 바꾼다. 이 child인 키 없는 `ExternalImportShareCoordinator`는 전환 때 폐기되고 새로 생성되어 `_pending` 큐와 `_opening` 상태를 잃는다. 예를 들어 공유 파일을 받은 뒤 인증 준비나 기존 가져오기 완료를 기다리는 동안 강제 정책이 적용되면 해당 파일은 대기 큐에서 사라진다. 네이티브 공유 큐도 전달 시 항목을 제거하므로, 나중에 정책이 완화되어 차단이 해제되어도 새 coordinator가 그 파일을 다시 가져올 수 없다.
- [P2][스토어 열기 실패 안내에서 Overlay 탐색 예외 발생] `lib/features/app_update/widgets/app_update_gate.dart:151–154` — `AppSnackBar.error()`에 루트 Navigator 자체의 `currentContext`를 넘긴다. 이 context는 Navigator 내부 Overlay의 조상이므로, 스낵바가 사용하는 `Overlay.of(context, rootOverlay: true)`는 Overlay를 찾지 못한다. API에서 허용하는 `storeUrl: null`이나 URL 실행 실패 시 안내 대신 예외가 발생한다. 권장 안내에서는 바깥 `_check()`가 이를 로그로만 처리하고, 강제 화면의 버튼은 `_openStore()`를 `unawaited`로 호출하므로 처리되지 않은 비동기 예외로 전파된다. 강제 화면은 Navigator 밖에서 그려지므로, context만 고쳐 루트 Overlay에 표시해도 차단 레이어 아래에 놓이는 점도 함께 처리해야 한다.

## 개선 제안
- 복귀 시 정책 검사 누락 → API 조회·판단을 마치면 조회 잠금을 해제하고, 팝업 표시 여부는 `_dialogShowing`으로 따로 관리한다. 팝업이 열려 있어도 복귀 시 최신 정책을 조회하고, 강제 정책으로 바뀌면 기존 권장 팝업을 정리한 뒤 차단 상태를 적용한다.
- 공유 파일 대기 상태 초기화 → 항상 같은 `Stack`과 `ExcludeFocus` 구조 안에 child를 유지한다. 강제 여부에 따라 focus 제외 값과 차단 레이어만 변경하여 기존 coordinator와 공유 파일 큐의 생명주기를 유지한다.
- 스토어 실패 안내 예외 → 권장 안내에서는 실제 Overlay 아래의 유효한 context를 사용한다. 강제 화면에서는 차단 레이어 위에서 확인할 수 있는 오류 상태를 표시하고, 공통 안내 컴포넌트를 호출할 때 필요한 Overlay 범위를 보장한다. `storeUrl`이 없는 경우에도 수동 업데이트 안내가 사용자에게 보이도록 처리한다.
