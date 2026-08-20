# 리뷰 결과

## 요약
- 메모 사진 작성·보기 UI와 세로 화면 고정은 정적 분석을 통과했지만, 카메라 방향 잠금의 비동기 처리와 센서 생명주기에서 실제 기기 리소스가 잘못 복구되거나 오류가 누락될 수 있다.

## 문제점
- [높음] `memo_ocr_camera_screen.dart:130`과 `memo_photo_camera_screen.dart:145`는 `lockCaptureOrientation()`을 기다리기 전에만 `_cameraGeneration`을 확인한다. 방향 잠금을 기다리는 동안 앱이 `inactive`/`paused`가 되면 `_releaseCamera()`가 세대를 올리고 카메라를 해제하지만, 대기 중이던 초기화 작업은 복귀 후 다시 검사하지 않고 `setState()`에서 이전 `nextController`를 `_controller`로 등록한다. 그 결과 백그라운드에서 카메라가 다시 활성화되거나, 다음 `resumed` 초기화와 두 컨트롤러가 경합할 수 있다.
- [중간] `memo_ocr_camera_screen.dart:68`과 `memo_photo_camera_screen.dart:83`의 방향 변경 처리는 `lockCaptureOrientation()` Future를 오류 처리 없이 `unawaited`로 버린다. 회전 직후 화면을 닫거나 앱이 비활성화되어 컨트롤러가 dispose되면 플랫폼 호출이 `CameraException`으로 끝날 수 있고, 이 오류는 현재 카메라 오류 UI나 로그 어느 쪽에도 전달되지 않는다. 연속 방향 이벤트의 잠금 호출도 직렬화되지 않아 마지막 감지 방향보다 먼저 시작한 요청이 뒤늦게 반영될 여지가 있다.
- [중간] 두 카메라 화면은 `NativeDeviceOrientationCommunicator().onOrientationChanged(useSensor: true)`를 구독한 뒤 앱이 `paused`되어도 communicator를 `pause()`하지 않는다. 패키지가 제공하는 `NativeDeviceOrientationReader`도 백그라운드 진입 시 명시적으로 센서 listener를 중지하도록 구현되어 있으므로, 현재 코드는 갤러리 앱 체류나 장시간 백그라운드 상태에서도 방향 센서를 계속 유지할 수 있다.

## 개선 제안
- 방향 잠금 중 생명주기 변경 → `await nextController.lockCaptureOrientation(...)` 직후에도 `mounted`와 `generation == _cameraGeneration`을 다시 확인하고, 무효화되었으면 `nextController`를 dispose한 뒤 반환한다.
- 방향 변경 잠금의 오류·순서 경합 → 방향 잠금을 하나의 Future 체인으로 직렬화하고 각 호출의 `CameraException`을 현재 세대 기준으로 처리한다. 최소한 `catchError` 또는 전용 async 메서드에서 오류를 로그로 남겨 처리되지 않은 Future 오류가 되지 않게 한다.
- 백그라운드 센서 유지 → communicator를 상태 필드로 보관하고 `paused`에서 `pause()`, `resumed`에서 `resume()`을 호출한다. dispose 시 구독 취소와 함께 센서 listener가 확실히 정리되는지도 동일한 생명주기 경로에서 보장한다.
