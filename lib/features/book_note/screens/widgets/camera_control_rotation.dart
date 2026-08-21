import 'package:flutter/widgets.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

/// 화면 회전 잠금 상태에서도 실제 기기 자세에 맞춰 컨트롤 아이콘을 돌리기
/// 위한 회전량(턴 단위). 레이아웃(버튼 위치)은 그대로 두고 아이콘만 돌려
/// 기기를 가로로 들었을 때도 아이콘이 위를 향하도록 한다.
double controlIconTurnsFor(NativeDeviceOrientation orientation) {
  switch (orientation) {
    case NativeDeviceOrientation.landscapeLeft:
      return 0.25;
    case NativeDeviceOrientation.landscapeRight:
      return -0.25;
    case NativeDeviceOrientation.portraitDown:
      return 0.5;
    case NativeDeviceOrientation.portraitUp:
    case NativeDeviceOrientation.unknown:
      return 0;
  }
}

/// 카메라 촬영 화면의 컨트롤 버튼 아이콘. 버튼 자체의 위치는 그대로 두고
/// 아이콘만 [orientation]에 맞춰 부드럽게 회전시킨다.
class RotatedControlIcon extends StatelessWidget {
  const RotatedControlIcon({
    super.key,
    required this.orientation,
    required this.icon,
    this.size,
    this.color,
  });

  final NativeDeviceOrientation orientation;
  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: controlIconTurnsFor(orientation),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Icon(icon, size: size, color: color),
    );
  }
}
