# 리뷰 결과

## 요약

- 전체 상태: Alert/Confirm/Loading을 `lib/shared/widgets`에 모으고 공통 색상 토큰을 사용한 구조와 `StatelessWidget` 선택은 적절하며, 새 코드에서 정적 분석 오류는 발견되지 않았다. 다만 공통 컴포넌트로 사용하기 전에 다이얼로그의 제한된 화면 대응과 로딩 오버레이의 접근성 입력 차단, destructive 버튼의 색상 대비를 보완할 필요가 있다.
- 검증: `flutter analyze` 결과 error/warning은 없고 기존 인증 파일의 `prefer_initializing_formals` info 6건만 확인됐다. 변경 코드와 관련 없는 스타일 lint이므로 아래 문제점에는 포함하지 않았다. 요청 지침에 따라 앱 실행과 테스트는 수행하지 않았다.

## 문제점

- [중간][레이아웃] `lib/shared/widgets/app_dialog_shell.dart:43`의 본문 `Column`은 제목·메시지·버튼을 모두 non-flex 자식으로 배치하고 스크롤 영역을 제공하지 않는다. 메시지가 길거나 접근성 텍스트 배율이 커지면 다이얼로그의 사용 가능 높이를 넘어 `RenderFlex` overflow가 발생하고 하단 액션이 화면 밖으로 밀릴 수 있다. `lib/shared/widgets/app_dialog_shell.dart:71`의 고정 `Row`도 버튼 라벨이 길어질 때 세로 배치로 전환할 수 없다.
- [중간][접근성/입력] `lib/shared/widgets/app_loading.dart:59`의 영역 로딩은 마지막에 배치한 `ColoredBox`로 포인터 입력만 가린다. 로딩 전 포커스와 하위 semantics 노드는 그대로 남기 때문에 스크린 리더나 하드웨어 키보드 사용자는 로딩 중에도 가려진 버튼을 탐색하거나 실행할 수 있고, 로딩 상태를 설명하는 label/live region도 없다.
- [중간][접근성] `lib/shared/widgets/app_dialog_shell.dart:116`의 destructive 버튼은 `AppColors.error`(`#E03C3C`) 배경에 흰색 15px 텍스트를 사용해 명암비가 약 4.30:1이다. 일반 크기 텍스트 기준 4.5:1에 미달하므로 삭제·취소 불가 작업처럼 중요한 확인 버튼의 라벨 식별성이 떨어진다.
- [낮음][접근성] `lib/shared/widgets/app_dialog_shell.dart:38`은 Alert/Confirm을 일반 `Dialog`로 렌더링해 기본 semantics role이 `dialog`이고, 제목도 route 이름이나 별도 semantic label로 연결하지 않는다. 따라서 보조 기술이 팝업 진입 시 이를 alert dialog로 식별하고 제목을 즉시 안내하는 동작이 `AlertDialog`를 사용할 때보다 불명확하다.

## 개선 제안

- 다이얼로그 콘텐츠가 화면 높이를 넘을 수 있음 → 제목/본문 영역을 `Flexible` 안의 `SingleChildScrollView`로 구성해 액션 영역은 계속 노출하고, 액션은 `OverflowBar`처럼 가로 공간이 부족하면 세로로 전환되는 레이아웃을 사용한다.
- 영역 로딩 중 보조 입력이 계속 활성화됨 → 로딩 시 child의 포커스와 semantics를 제외하고 오버레이에서 이전 semantics를 차단한다. 동시에 `Semantics(liveRegion: true, label: '로딩 중')`처럼 상태를 안내하되, 포인터 차단 동작은 유지한다.
- destructive 버튼 명암비가 부족함 → 흰색 라벨과 4.5:1 이상이 되는 더 어두운 destructive 배경 토큰을 사용하거나, 현재 배경을 유지해야 한다면 기준을 충족하는 전경색을 별도 토큰으로 정의한다.
- Alert/Confirm의 의미가 보조 기술에 명확하지 않음 → 커스텀 형태를 유지한다면 `SemanticsRole.alertDialog`와 제목 기반 semantic label/route semantics를 제공한다. 표준 동작을 재사용할 수 있으면 `AlertDialog`의 content·actions 레이아웃을 스타일링하는 방식도 적합하다.
