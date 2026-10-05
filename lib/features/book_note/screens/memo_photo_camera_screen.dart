import 'package:flutter/material.dart';

import '../../../shared/image/screens/shared_camera_screen.dart';

/// 메모 사진 조각용 촬영 정책 — 세로 고정 미리보기, 갤러리는 이미지 정책
/// (JPEG·긴 변 1600px·85%)대로 압축한다. 촬영 사진은 저장 시점에 같은
/// 정책으로 압축되므로 촬영 용량은 제한하지 않는다.
const _memoPhotoCapturePolicy = CameraCapturePolicy(
  previewMode: CameraPreviewMode.rotatedAspectRatio,
);

/// 메모 사진 조각용 촬영 화면을 열고, 촬영하거나(좌하단 아이콘으로) 갤러리에서
/// 고른 이미지의 로컬 경로를 반환한다. 취소하면 null.
Future<String?> captureMemoPhoto(BuildContext context) {
  return showSharedCameraScreen(context, policy: _memoPhotoCapturePolicy);
}
