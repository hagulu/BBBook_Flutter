# 리뷰 결과

## 요약

- 현재 미커밋 변경분인 공용 카메라의 iOS 촬영 방향 보정·OCR 가이드 회전을 검토했으며, 회전본 저장 실패 시 원본까지 손상될 수 있는 P2 문제 1건을 확인했습니다.
- 범위: `lib/shared/image/screens/shared_camera_screen.dart`와 메모 사진·OCR 호출부, 설치된 `camera`/`camera_avfoundation`/`image`/`native_device_orientation`의 관련 구현.
- 검증: `flutter analyze` 통과(`No issues found!`). 프로젝트 지침에 따라 앱 실행과 테스트는 수행하지 않았으며, 실기기에서의 미리보기·촬영 방향은 검증하지 않았습니다.

## 문제점

- [P2] 회전본을 원본 경로에 직접 쓰므로 저장 실패 시 촬영 파일을 잃을 수 있습니다.
  - 위치: [shared_camera_screen.dart:733](../../lib/shared/image/screens/shared_camera_screen.dart#L733). 관련 오류 처리: 같은 파일 715~724행, 성공 반환: 387~411행.
  - 조건: iOS에서 가로 또는 역세로로 촬영한 뒤, 회전 JPEG를 덮어쓰는 도중 저장 공간 부족 등의 쓰기 오류가 발생한 경우입니다.
  - 근거: `_rotateJpegFile()`은 카메라가 반환한 원본 파일에 `writeAsBytes()`를 호출합니다. 이 메서드는 기본 모드에서 기존 파일을 먼저 잘라내므로, 쓰기 도중 실패하면 원본이 빈 파일이나 불완전한 JPEG로 남을 수 있습니다. [Dart 공식 `File.writeAsBytes()` 문서](https://api.dart.dev/dart-io/File/writeAsBytes.html).
  - 영향: `_rotateCaptureToDeviceOrientation()`이 예외를 로그만 남기고 삼켜 `_takePicture()`가 해당 경로를 성공으로 반환합니다. 현재 사진·OCR 정책은 `maxCaptureBytes`를 지정하지 않아 파일 검사도 없이 편집기로 넘어갑니다. 따라서 주석의 “실패하면 원본을 그대로 둔다”는 보장이 성립하지 않으며, 정상 촬영한 사진을 다시 찍어야 할 수 있습니다. 이 오류 경로는 코드와 파일 쓰기 동작을 근거로 판단했으며 실제 저장 공간 부족을 재현하지는 않았습니다.

## 개선 제안

- 원본 직접 덮어쓰기 → 원본과 같은 디렉터리의 별도 임시 파일에 회전본 저장을 완료한 뒤 교체하세요. 쓰기 실패 시에는 임시 파일만 정리해 원본을 유지하고, 원본 보존 여부를 보장할 수 없는 오류는 호출부까지 전달하여 손상된 파일이 성공 결과로 넘어가지 않게 하세요.
