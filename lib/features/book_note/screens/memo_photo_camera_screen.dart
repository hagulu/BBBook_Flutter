import 'package:flutter/material.dart';

import '../../../shared/image/screens/shared_camera_screen.dart';

/// 메모 사진 조각용 촬영 정책 — 세로 고정 미리보기, 갤러리는 재인코딩으로
/// 압축(JPEG·최대 1600px), 촬영 결과는 저장 계층의 5MB 제한을 넘기지
/// 않도록 촬영 시점에 미리 걸러낸다.
const _memoPhotoCapturePolicy = CameraCapturePolicy(
  previewMode: CameraPreviewMode.rotatedAspectRatio,
  galleryImageQuality: 85,
  galleryMaxWidth: 1600,
  // BookNoteRepository._maxImageBytes와 같은 값으로 맞춘다 — 저장 계층의
  // 허용치와 어긋나면 여기 통과한 사진이 결국 저장 시점에 거절된다.
  maxCaptureBytes: 5 * 1024 * 1024,
);

/// 메모 사진 조각용 촬영 화면을 열고, 촬영하거나(좌하단 아이콘으로) 갤러리에서
/// 고른 이미지의 로컬 경로를 반환한다. 취소하면 null.
Future<String?> captureMemoPhoto(BuildContext context) {
  return showSharedCameraScreen(context, policy: _memoPhotoCapturePolicy);
}
