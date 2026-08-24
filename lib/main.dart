import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/api_config.dart';
import 'features/book_note/services/note_memo_image_store.dart';
import 'features/book_reflection/services/reflection_image_store.dart';
import 'features/bookshelf/services/book_cover_image_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 기기를 가로로 기울여도 앱 화면 자체는 항상 세로로 고정한다. 카메라
  // 촬영 화면은 실제 기기 자세를 센서로 별도 감지해(native_device_orientation)
  // 촬영 방향만 맞추므로, 화면 회전을 막아도 가로 촬영 자체는 가능하다.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  ApiConfig.assertConfiguredForRelease();
  // 이미지 저장 경로를 미리 캐시해, 화면이 build() 안에서 곧바로 로컬
  // 파일을 열 수 있게 한다. 특히 아직 서버에 올리지 못한 이미지는 대체할
  // URL 자체가 없어, 캐시가 없으면 앱 재실행 직후 깨져 보인다.
  await noteMemoImageStore.warmUp();
  await reflectionImageStore.warmUp();
  await bookCoverImageStore.warmUp();
  runApp(const ProviderScope(child: BBBookApp()));
}
