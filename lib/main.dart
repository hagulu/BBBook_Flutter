import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/api_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 기기를 가로로 기울여도 앱 화면 자체는 항상 세로로 고정한다. 카메라
  // 촬영 화면은 실제 기기 자세를 센서로 별도 감지해(native_device_orientation)
  // 촬영 방향만 맞추므로, 화면 회전을 막아도 가로 촬영 자체는 가능하다.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  ApiConfig.assertConfiguredForRelease();
  runApp(const ProviderScope(child: BBBookApp()));
}
