# 리뷰 결과

## 요약
- 메모 사진 작성·보기 UI와 진행률 카드 정리는 정적 분석을 통과했지만, 새 카메라 방향 제어는 초기화 경합·플랫폼별 화면 회전 제한·센서 생명주기 때문에 실제 기기에서 촬영 방향과 리소스 상태가 어긋날 수 있다.

## 문제점
- [높음] `memo_ocr_camera_screen.dart:130`과 `memo_photo_camera_screen.dart:145`는 `lockCaptureOrientation()`을 기다린 뒤 `mounted`와 `_cameraGeneration`을 다시 확인하지 않고 `nextController`를 게시한다. 대기 중 앱이 비활성화되면 `_releaseCamera()`가 현재 세대를 무효화해도 이전 초기화 작업이 백그라운드에서 컨트롤러를 다시 등록하며, 같은 구간에 새 센서 방향이 들어오면 `_controller`가 아직 `null`이라 해당 이벤트가 잠금에 반영되지 않아 다음 방향 이벤트 전까지 촬영 방향도 이전 값으로 남는다.
- [중간] `main.dart:13`의 `SystemChrome.setPreferredOrientations()`만으로는 주석의 “앱 화면 자체는 항상 세로” 전제가 iPad에서 보장되지 않는다. 이 프로젝트는 iPad를 타깃으로 하고 `Info.plist`에서 가로 방향을 허용하지만 `UIRequiresFullScreen`이 없어 멀티태스킹 상태에서는 Flutter의 방향 잠금 요청이 무시된다. 이때 화면 레이아웃이 회전하는 동시에 센서 기반 아이콘 회전과 세로 비율 프리뷰 로직도 적용되어 카메라 UI 방향이 이중으로 어긋날 수 있다.
- [중간] `memo_ocr_camera_screen.dart:68`과 `memo_photo_camera_screen.dart:83`은 방향 변경마다 `lockCaptureOrientation()` Future를 오류 처리 없이 `unawaited`로 버린다. 방향 이벤트 직후 화면을 닫거나 앱을 비활성화하면 같은 컨트롤러의 `dispose()`와 플랫폼 호출이 경합해 `CameraException`이 처리되지 않은 비동기 오류가 될 수 있고, 연속 호출의 완료 순서도 보장하지 않아 마지막 센서 방향과 실제 촬영 잠금 방향이 달라질 수 있다.
- [중간] 두 카메라 화면은 `onOrientationChanged(useSensor: true)`를 구독한 뒤 `paused` 상태에서도 communicator를 멈추지 않는다(`memo_ocr_camera_screen.dart:46`, `memo_photo_camera_screen.dart:61`). 카메라는 생명주기 콜백에서 해제하지만 방향 센서는 화면이 dispose될 때까지 계속 활성화되므로, 갤러리 앱 체류나 장시간 백그라운드 상태에서 불필요하게 센서와 이벤트 채널을 유지한다.

## 개선 제안
- 초기화 중 생명주기·방향 변경 → `await lockCaptureOrientation()` 직후에도 현재 세대와 `mounted`를 검증하고, 무효화된 컨트롤러는 dispose한다. 게시 직전 최신 `_deviceOrientation`이 잠금에 반영됐는지도 다시 확인하거나 모든 방향 잠금을 하나의 직렬화된 경로로 합친다.
- iPad 화면 회전 제한 → 앱을 실제로 세로 전용으로 운영한다면 iPad 멀티태스킹 포기 여부를 결정해 `UIRequiresFullScreen`과 지원 방향을 함께 설정한다. 멀티태스킹을 유지한다면 화면 회전을 허용하는 전제로 카메라 프리뷰와 컨트롤 회전량을 현재 UI 방향에 상대적으로 계산한다.
- 방향 잠금 Future 경합 → 세대가 포함된 전용 async 메서드에서 잠금 호출을 직렬화하고 `CameraException`을 일관된 카메라 로그·오류 상태로 처리한다.
- 백그라운드 센서 유지 → communicator를 상태 필드로 보관해 `paused`에서 `pause()`, `resumed`에서 `resume()`을 호출하고 dispose 시 구독 취소를 완료한다.

